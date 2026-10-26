import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../crypto/vault_crypto.dart';
import 'login_import.dart';
import 'models.dart';
import '../i18n.dart';

enum VaultStatus { loading, needsSetup, locked, unlocked }

/// 備份已驗證通過（密碼正確），但寫入本機時失敗（例如空間不足）。
class RestoreWriteException implements Exception {
  RestoreWriteException(this.cause);
  final Object cause;
  @override
  String toString() => '$cause';
}

/// 還原備份後的統計。
class BackupSummary {
  const BackupSummary({
    required this.added,
    required this.updated,
    required this.kept,
    required this.images,
    this.removed = 0,
    this.localOnly = 0,
  });

  final int localOnly; // 只有本機有、雲端沒有的項目（需要再上傳）
  final int removed; // 因為其他裝置已永久刪除而移除的筆記
  bool get changed => added + updated + removed > 0;
  bool get needsPush => kept > 0 || localOnly > 0;

  final int added; // 新增的筆記
  final int updated; // 被備份裡較新的版本覆蓋的筆記
  final int kept; // 目前這支手機上較新、保留不動的筆記
  final int images; // 還原的圖片數
}

/// 匯入 CSV 帳密後的統計。
class LoginImportSummary {
  const LoginImportSummary({
    required this.created,
    required this.merged,
    required this.accounts,
    required this.duplicates,
  });

  final int created; // 新建的筆記
  final int merged; // 補進既有筆記的數量
  final int accounts; // 新增的帳號數
  final int duplicates; // 完全相同而略過的帳號數
}

/// 加密資料庫。
///
/// 金鑰架構：
/// - 隨機產生資料金鑰 DEK，用來加密 vault.enc 與所有圖片。
/// - 主密碼經 PBKDF2 推導出 KEK，只用來包裹（加密）DEK，存在 header.json。
///   因此修改主密碼不需要重新加密所有資料。
/// - 啟用指紋後，DEK 另存於 Android Keystore 保護的 secure storage，
///   每次取用前都要先通過生物辨識。
class VaultStore extends ChangeNotifier {
  VaultStatus status = VaultStatus.loading;
  final List<Note> notes = <Note>[];
  final List<Folder> folders = <Folder>[];
  bool biometricEnabled = false;

  /// 沒有設定主密碼：資料金鑰存在裝置的安全儲存區，開啟 App 不需要輸入密碼。
  bool noPassword = false;

  // 筆記鎖定密碼（和主密碼互相獨立）。只存加鹽雜湊，存在加密資料庫裡。
  String? _lockSalt;
  String? _lockHash;
  int _lockIter = 100000;
  bool get hasLockPassword => _lockHash != null;

  /// 永久刪除的記號（id → 刪除時間），讓同步時不會把已刪除的筆記從別台裝置「救回來」。
  final Map<String, DateTime> tombstones = <String, DateTime>{};
  final Map<String, DateTime> folderTombstones = <String, DateTime>{};

  /// 外部畫面（相簿、相機、指紋視窗）開啟期間為 true，避免被誤判成「離開 App」而鎖定。
  bool externalBusy = false;

  /// 編輯時遞增，用來重置閒置計時。
  final ValueNotifier<int> activity = ValueNotifier<int>(0);

  static const String _bioKey = 'mido_dek_bio';
  static const String _nopwKey = 'mido_dek_nopw';
  static const int _trashDays = 30;

  late Directory _dir;
  SecretKey? _dek;
  final FlutterSecureStorage _secure = const FlutterSecureStorage();
  final LocalAuthentication _auth = LocalAuthentication();
  final Uuid _uuid = const Uuid();
  final Map<String, Uint8List> _imageCache = <String, Uint8List>{};
  final List<Future<void> Function()> _beforeLock = <Future<void> Function()>[];
  Future<void> _saveChain = Future<void>.value();

  /// 最近一次存檔失敗的錯誤（成功則為 null）；上次備份讀不到的附件數。
  Object? lastSaveError;
  int lastBackupMissing = 0;

  /// 等待目前排隊中的存檔全部寫完。
  Future<void> flush() => _saveChain;

  /// 重新嘗試存檔（儲存失敗後使用）。
  Future<void> retrySave() => _persist();

  File get _headerFile => File('${_dir.path}/header.json');
  File get _vaultFile => File('${_dir.path}/vault.enc');
  File _imageFile(String id) => File('${_dir.path}/images/$id.enc');

  // ───────────────────────── 初始化 / 建立 / 解鎖 ─────────────────────────

  Future<void> init() async {
    _dir = await getApplicationSupportDirectory();
    await Directory('${_dir.path}/images').create(recursive: true);
    if (await _headerFile.exists()) {
      Map<String, dynamic>? h;
      try {
        h = await _readHeader();
      } catch (_) {}
      if (h != null && h['nopw'] == true) {
        // 無密碼模式：直接用安全儲存區裡的金鑰開啟
        try {
          final b64 = await _secure.read(key: _nopwKey);
          if (b64 != null) {
            await _openVault(SecretKey(base64Decode(b64)));
            noPassword = true;
            return;
          }
        } catch (e) {
          debugPrint('no-password open failed: $e');
        }
        // 金鑰不見了（例如清除過 App 資料）：資料已無法解開，只能重新開始或從備份還原
        status = VaultStatus.needsSetup;
        notifyListeners();
        return;
      }
      status = VaultStatus.locked;
      try {
        biometricEnabled = (await _secure.read(key: _bioKey)) != null;
      } catch (_) {
        biometricEnabled = false;
      }
    } else {
      status = VaultStatus.needsSetup;
    }
    notifyListeners();
  }

  Future<void> createVault(String password) async {
    final salt = VaultCrypto.randomBytes(VaultCrypto.saltLength);
    final kek = await VaultCrypto.deriveKey(
      password,
      salt,
      VaultCrypto.kdfIterations,
    );
    final dek = await VaultCrypto.newDataKey();
    final wrapped = await VaultCrypto.encrypt(await dek.extractBytes(), kek);
    await _writeHeader(salt, VaultCrypto.kdfIterations, wrapped);
    try {
      await _secure.delete(key: _bioKey);
    } catch (_) {}
    try {
      await _secure.delete(key: _nopwKey);
    } catch (_) {}
    noPassword = false;
    biometricEnabled = false;
    _dek = dek;
    notes.clear();
    folders.clear();
    tombstones.clear();
    folderTombstones.clear();
    _lockSalt = null;
    _lockHash = null;
    await _persist();
    status = VaultStatus.unlocked;
    notifyListeners();
  }

  /// 不設定主密碼，直接使用。資料金鑰存在裝置的安全儲存區。
  Future<void> createVaultNoPassword() async {
    final dek = await VaultCrypto.newDataKey();
    await _secure.write(key: _nopwKey, value: base64Encode(await dek.extractBytes()));
    await _writeNoPwHeader();
    try {
      await _secure.delete(key: _bioKey);
    } catch (_) {}
    biometricEnabled = false;
    noPassword = true;
    _dek = dek;
    notes.clear();
    folders.clear();
    tombstones.clear();
    folderTombstones.clear();
    _lockSalt = null;
    _lockHash = null;
    await _persist();
    status = VaultStatus.unlocked;
    notifyListeners();
  }

  Future<void> _writeNoPwHeader() => _atomicWrite(
        _headerFile,
        utf8.encode(jsonEncode({'v': 1, 'nopw': true})),
      );

  /// 從「無密碼模式」改成設定主密碼。
  Future<bool> setMasterPassword(String password) async {
    final dek = _dek;
    if (dek == null || !noPassword) return false;
    try {
      final salt = VaultCrypto.randomBytes(VaultCrypto.saltLength);
      final kek = await VaultCrypto.deriveKey(
        password,
        salt,
        VaultCrypto.kdfIterations,
      );
      final wrapped = await VaultCrypto.encrypt(await dek.extractBytes(), kek);
      await _writeHeader(salt, VaultCrypto.kdfIterations, wrapped);
      try {
        await _secure.delete(key: _nopwKey);
      } catch (_) {}
      noPassword = false;
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('setMasterPassword failed: $e');
      return false;
    }
  }

  /// 移除主密碼（改成無密碼模式）。需要先輸入目前的主密碼。
  Future<bool> removeMasterPassword(String currentPw) async {
    final dek = _dek;
    if (dek == null || noPassword) return false;
    if (!await checkPassword(currentPw)) return false;
    try {
      await _secure.write(
        key: _nopwKey,
        value: base64Encode(await dek.extractBytes()),
      );
      if ((await _secure.read(key: _nopwKey)) == null) return false;
      await _writeNoPwHeader();
      try {
        await _secure.delete(key: _bioKey);
      } catch (_) {}
      biometricEnabled = false;
      noPassword = true;
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('removeMasterPassword failed: $e');
      return false;
    }
  }

  // ───────────────────────── 筆記鎖定密碼 ─────────────────────────

  Future<String> _lockDerive(String pw, List<int> salt, int iter) async {
    final k = await VaultCrypto.deriveKey(pw, salt, iter);
    return base64Encode(await k.extractBytes());
  }

  Future<void> setLockPassword(String pw) async {
    final salt = VaultCrypto.randomBytes(VaultCrypto.saltLength);
    _lockIter = 100000;
    _lockHash = await _lockDerive(pw, salt, _lockIter);
    _lockSalt = base64Encode(salt);
    notifyListeners();
    await _persist();
  }

  Future<bool> verifyLockPassword(String pw) async {
    final h = _lockHash;
    final s = _lockSalt;
    if (h == null || s == null) return false;
    try {
      final got = await _lockDerive(pw, base64Decode(s), _lockIter);
      if (got.length != h.length) return false;
      var diff = 0;
      for (var i = 0; i < got.length; i++) {
        diff |= got.codeUnitAt(i) ^ h.codeUnitAt(i);
      }
      return diff == 0;
    } catch (_) {
      return false;
    }
  }

  Future<bool> changeLockPassword(String oldPw, String newPw) async {
    if (!await verifyLockPassword(oldPw)) return false;
    await setLockPassword(newPw);
    return true;
  }

  /// 移除鎖定密碼，同時解除所有筆記的鎖定。
  Future<bool> removeLockPassword(String oldPw) async {
    if (!await verifyLockPassword(oldPw)) return false;
    _lockHash = null;
    _lockSalt = null;
    final now = DateTime.now();
    for (final n in notes) {
      if (n.locked) {
        n.locked = false;
        n.updatedAt = now;
      }
    }
    notifyListeners();
    await _persist();
    return true;
  }

  void setNoteLocked(String id, bool locked) {
    final n = byId(id);
    if (n == null) return;
    n.locked = locked;
    n.updatedAt = DateTime.now();
    notifyListeners();
    _persist();
  }

  Map<String, dynamic>? _lockJson() => (_lockHash == null || _lockSalt == null)
      ? null
      : {'salt': _lockSalt, 'hash': _lockHash, 'iter': _lockIter};

  void _readLock(Object? raw) {
    if (raw is Map && raw['hash'] is String && raw['salt'] is String) {
      _lockHash = raw['hash'] as String;
      _lockSalt = raw['salt'] as String;
      _lockIter = (raw['iter'] as int?) ?? 100000;
    } else {
      _lockHash = null;
      _lockSalt = null;
    }
  }

  Future<bool> unlockWithPassword(String password) async {
    try {
      final header = await _readHeader();
      final kek = await VaultCrypto.deriveKey(
        password,
        base64Decode(header['salt'] as String),
        header['iter'] as int,
      );
      final dekBytes = await VaultCrypto.decrypt(
        base64Decode(header['wrapped'] as String),
        kek,
      );
      await _openVault(SecretKey(dekBytes));
      return true;
    } catch (e) {
      debugPrint('unlock failed: $e');
      return false;
    }
  }

  Future<bool> unlockWithBiometric() async {
    if (!biometricEnabled) return false;
    try {
      final ok = await authenticate(tr('解鎖 Mido筆記'));
      if (!ok) return false;
      final b64 = await _secure.read(key: _bioKey);
      if (b64 == null) return false;
      await _openVault(SecretKey(base64Decode(b64)));
      return true;
    } catch (e) {
      debugPrint('biometric unlock failed: $e');
      return false;
    }
  }

  Future<void> _openVault(SecretKey dek) async {
    final loadedNotes = <Note>[];
    final loadedFolders = <Folder>[];
    Map<String, dynamic>? map0;
    if (await _vaultFile.exists()) {
      final plain = await VaultCrypto.decrypt(await _vaultFile.readAsBytes(), dek);
      final map = jsonDecode(utf8.decode(plain)) as Map<String, dynamic>;
      map0 = map;
      for (final e in (map['notes'] as List?) ?? const <dynamic>[]) {
        loadedNotes.add(Note.fromJson(e as Map<String, dynamic>));
      }
      for (final e in (map['folders'] as List?) ?? const <dynamic>[]) {
        loadedFolders.add(Folder.fromJson(e as Map<String, dynamic>));
      }
    }
    final tomb = _readTomb(map0?['tomb']);
    final ftomb = _readTomb(map0?['ftomb']);
    _readLock(map0?['lockpw']);
    _dek = dek;
    tombstones
      ..clear()
      ..addAll(tomb);
    folderTombstones
      ..clear()
      ..addAll(ftomb);
    notes
      ..clear()
      ..addAll(loadedNotes);
    folders
      ..clear()
      ..addAll(loadedFolders);
    _purgeOldTrash();
    status = VaultStatus.unlocked;
    notifyListeners();
  }

  /// 鎖定前會先呼叫已註冊的 hook（例如編輯中的筆記先存檔）。
  Future<void> lock() async {
    if (status != VaultStatus.unlocked) return;
    for (final cb in List<Future<void> Function()>.of(_beforeLock)) {
      try {
        await cb();
      } catch (_) {}
    }
    await _saveChain;
    if (lastSaveError != null) {
      await _persist(); // 上次存檔失敗：鎖定前再試一次，免得未存的內容被清掉
    }
    if (noPassword) return; // 無密碼模式不鎖定
    _dek = null;
    _lockHash = null;
    _lockSalt = null;
    notes.clear();
    folders.clear();
    tombstones.clear();
    folderTombstones.clear();
    _imageCache.clear();
    status = VaultStatus.locked;
    notifyListeners();
  }

  void addBeforeLock(Future<void> Function() cb) => _beforeLock.add(cb);
  void removeBeforeLock(Future<void> Function() cb) => _beforeLock.remove(cb);
  void bump() => activity.value++;

  Future<T> withExternal<T>(Future<T> Function() action) async {
    externalBusy = true;
    try {
      return await action();
    } finally {
      Future<void>.delayed(const Duration(milliseconds: 1000), () {
        externalBusy = false;
      });
    }
  }

  // ───────────────────────── 指紋 / 主密碼 ─────────────────────────

  Future<bool> authenticate(String reason) {
    return withExternal(
      () => _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      ),
    );
  }

  Future<bool> enableBiometric() async {
    final dek = _dek;
    if (dek == null) return false;
    try {
      if (!await _auth.isDeviceSupported()) return false;
      if ((await _auth.getAvailableBiometrics()).isEmpty) return false;
      if (!await authenticate(tr('啟用指紋解鎖'))) return false;
      await _secure.write(
        key: _bioKey,
        value: base64Encode(await dek.extractBytes()),
      );
      biometricEnabled = true;
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('enable biometric failed: $e');
      return false;
    }
  }

  Future<void> disableBiometric() async {
    try {
      await _secure.delete(key: _bioKey);
    } catch (_) {}
    biometricEnabled = false;
    notifyListeners();
  }

  Future<bool> changePassword(String oldPw, String newPw) async {
    final dek = _dek;
    if (dek == null) return false;
    try {
      final header = await _readHeader();
      final oldKek = await VaultCrypto.deriveKey(
        oldPw,
        base64Decode(header['salt'] as String),
        header['iter'] as int,
      );
      // 驗證舊密碼（錯誤會丟出例外）
      await VaultCrypto.decrypt(base64Decode(header['wrapped'] as String), oldKek);

      final salt = VaultCrypto.randomBytes(VaultCrypto.saltLength);
      final kek = await VaultCrypto.deriveKey(
        newPw,
        salt,
        VaultCrypto.kdfIterations,
      );
      final wrapped = await VaultCrypto.encrypt(await dek.extractBytes(), kek);
      await _writeHeader(salt, VaultCrypto.kdfIterations, wrapped);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>> _readHeader() async =>
      jsonDecode(await _headerFile.readAsString()) as Map<String, dynamic>;

  Future<void> _writeHeader(List<int> salt, int iterations, List<int> wrapped) {
    return _atomicWrite(
      _headerFile,
      utf8.encode(jsonEncode({
        'v': 1,
        'iter': iterations,
        'salt': base64Encode(salt),
        'wrapped': base64Encode(wrapped),
      })),
    );
  }

  // ───────────────────────── 筆記 / 資料夾 ─────────────────────────

  Note newNote(NoteType type, {String? folderId}) =>
      Note(id: _uuid.v4(), type: type, folderId: folderId);

  Note? byId(String id) {
    for (final n in notes) {
      if (n.id == id) return n;
    }
    return null;
  }

  void upsertNote(Note n, {bool touch = true}) {
    if (status != VaultStatus.unlocked) return;
    if (touch) n.updatedAt = DateTime.now();
    final i = notes.indexWhere((e) => e.id == n.id);
    if (i >= 0) {
      notes[i] = n;
    } else {
      notes.add(n);
    }
    notifyListeners();
    _persist();
  }

  void setColor(String id, int color) {
    final n = byId(id);
    if (n == null) return;
    n.color = color;
    n.updatedAt = DateTime.now();
    notifyListeners();
    _persist();
  }

  void setPinned(String id, bool pinned) {
    final n = byId(id);
    if (n == null) return;
    n.pinned = pinned;
    n.updatedAt = DateTime.now();
    notifyListeners();
    _persist();
  }

  void moveToFolder(String id, String? folderId) {
    final n = byId(id);
    if (n == null) return;
    n.folderId = folderId;
    n.updatedAt = DateTime.now();
    notifyListeners();
    _persist();
  }

  /// 複製一則記事本到 [folderId]（null = 不分類）。名稱自動命名：「原名 複製」，
  /// 同一個資料夾裡已經有同名的就加編號（「原名 複製 2」…）。附件會一併複製成獨立的檔案，
  /// 之後刪掉其中一則不會影響另一則。
  Future<Note?> duplicateNote(Note src, String? folderId) async {
    if (status != VaultStatus.unlocked) return null;
    final base = src.displayTitle;
    final taken = <String>{
      for (final n in notes)
        if (!n.isTrashed && n.folderId == folderId) n.title.trim(),
    };
    var title = '$base ${tr('複製')}';
    var k = 2;
    while (taken.contains(title)) {
      title = '$base ${tr('複製')} $k';
      k++;
    }
    final newImages = <String>[];
    for (final id in src.imageIds) {
      final bytes = await loadImage(id);
      if (bytes == null) continue;
      if (isMediaId(id)) {
        final parts = id.split('-');
        newImages.add(await addMedia(
          bytes,
          video: id.startsWith('vid-'),
          ext: parts.length > 2 ? parts[1] : '',
        ));
      } else {
        newImages.add(await addImage(bytes));
      }
    }
    final now = DateTime.now();
    final copy = Note(
      id: _uuid.v4(),
      type: src.type,
      title: title,
      body: src.body,
      site: src.site,
      credentials: [for (final c in src.credentials) Credential(username: c.username, password: c.password)],
      fields: [for (final f in src.fields) CustomField(label: f.label, value: f.value, secret: f.secret)],
      tags: List<String>.of(src.tags),
      folderId: folderId,
      pinned: false,
      color: src.color,
      locked: src.locked,
      imageIds: newImages,
      createdAt: now,
      updatedAt: now,
    );
    notes.add(copy);
    notifyListeners();
    _persist();
    return copy;
  }

  void moveToTrash(String id) {
    final n = byId(id);
    if (n == null) return;
    n.deletedAt = DateTime.now();
    n.updatedAt = n.deletedAt!;
    notifyListeners();
    _persist();
  }

  void restore(String id) {
    final n = byId(id);
    if (n == null) return;
    n.deletedAt = null;
    n.updatedAt = DateTime.now();
    notifyListeners();
    _persist();
  }

  void deleteForever(String id) {
    final n = byId(id);
    if (n == null) return;
    for (final img in n.imageIds) {
      deleteImageFile(img);
    }
    notes.removeWhere((e) => e.id == id);
    tombstones[id] = DateTime.now();
    notifyListeners();
    _persist();
  }

  void emptyTrash() {
    final ids = notes.where((n) => n.isTrashed).map((n) => n.id).toList();
    for (final id in ids) {
      final n = byId(id);
      if (n == null) continue;
      for (final img in n.imageIds) {
        deleteImageFile(img);
      }
    }
    final now = DateTime.now();
    for (final id in ids) {
      tombstones[id] = now;
    }
    notes.removeWhere((n) => n.isTrashed);
    notifyListeners();
    _persist();
  }

  void _purgeOldTrash() {
    final limit = DateTime.now().subtract(const Duration(days: _trashDays));
    final old = notes
        .where((n) => n.deletedAt != null && n.deletedAt!.isBefore(limit))
        .toList();
    if (old.isEmpty) return;
    for (final n in old) {
      for (final img in n.imageIds) {
        deleteImageFile(img);
      }
    }
    final now = DateTime.now();
    for (final n in old) {
      tombstones[n.id] = now;
    }
    notes.removeWhere((n) => old.contains(n));
    _persist();
  }

  Folder addFolder(String name) {
    final f = Folder(id: _uuid.v4(), name: name.trim());
    folders.add(f);
    notifyListeners();
    _persist();
    return f;
  }

  void renameFolder(String id, String name) {
    for (final f in folders) {
      if (f.id == id) f.name = name.trim();
    }
    notifyListeners();
    _persist();
  }

  void deleteFolder(String id) {
    folders.removeWhere((f) => f.id == id);
    folderTombstones[id] = DateTime.now();
    for (final n in notes) {
      if (n.folderId == id) {
        n.folderId = null;
        n.updatedAt = DateTime.now();
      }
    }
    notifyListeners();
    _persist();
  }

  // ───────────────────────── 圖片（加密後存成獨立檔案） ─────────────────────────

  Future<String> addImage(Uint8List bytes) async {
    final dek = _dek;
    if (dek == null) throw StateError('vault locked');
    final id = _uuid.v4();
    final enc = await VaultCrypto.encrypt(bytes, dek);
    await _atomicWrite(_imageFile(id), enc);
    _cachePut(id, bytes);
    return id;
  }

  /// 影片／錄音附件的代號長這樣：vid-mp4-<uuid>、aud-m4a-<uuid>。
  /// 副檔名放在代號裡，開啟時才知道要用什麼檔名交給系統播放器。
  static bool isMediaId(String id) => id.startsWith('vid-') || id.startsWith('aud-');

  /// 加密儲存影片／錄音（不放進記憶體快取，檔案可能很大）。
  Future<String> addMedia(Uint8List bytes, {required bool video, required String ext}) async {
    final dek = _dek;
    if (dek == null) throw StateError('vault locked');
    final e = ext.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    final id = '${video ? 'vid' : 'aud'}-${e.isEmpty ? (video ? 'mp4' : 'm4a') : e}-${_uuid.v4()}';
    final enc = await VaultCrypto.encrypt(bytes, dek);
    await _atomicWrite(_imageFile(id), enc);
    return id;
  }

  Future<Uint8List?> loadImage(String id) async {
    final cached = _imageCache[id];
    if (cached != null) return cached;
    final dek = _dek;
    if (dek == null) return null;
    try {
      final f = _imageFile(id);
      if (!await f.exists()) return null;
      final bytes = await VaultCrypto.decrypt(await f.readAsBytes(), dek);
      if (!isMediaId(id)) _cachePut(id, bytes);
      return bytes;
    } catch (_) {
      return null;
    }
  }

  void _cachePut(String id, Uint8List bytes) {
    if (_imageCache.length >= 40) {
      _imageCache.remove(_imageCache.keys.first);
    }
    _imageCache[id] = bytes;
  }

  /// 要刪除的附件先登記，等「資料庫已成功寫入」後才真的刪檔，
  /// 避免寫入失敗時附件已經不見。就算清理失敗，最多只留下孤立的加密檔。
  final Set<String> _pendingImageDeletes = <String>{};

  Future<void> deleteImageFile(String id) async {
    _imageCache.remove(id);
    _pendingImageDeletes.add(id);
  }

  Future<void> _flushPendingDeletes() async {
    if (_pendingImageDeletes.isEmpty) return;
    final inUse = <String>{for (final n in notes) ...n.imageIds};
    final ids = List<String>.of(_pendingImageDeletes);
    _pendingImageDeletes.clear();
    for (final id in ids) {
      if (inUse.contains(id)) continue; // 仍被引用就不能刪
      try {
        final f = _imageFile(id);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
  }

  // ───────────────────────── 標籤 ─────────────────────────

  List<String> get sortedTags {
    final s = <String>{};
    for (final n in notes) {
      if (!n.isTrashed) s.addAll(n.tags);
    }
    return s.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }

  // ───────────────────────── 加密備份檔 ─────────────────────────
  //
  // 檔案格式：
  //   "MDBK"(4) | 版本(1) | PBKDF2 次數(4, big-endian) | salt(16) | AES-256-GCM(gzip(JSON))
  // 備份密碼和主密碼互相獨立；備份檔本身不含主密碼或資料金鑰。

  static const List<int> _backupMagic = <int>[0x4D, 0x44, 0x42, 0x4B]; // "MDBK"

  static List<int> _u32(int v) =>
      (ByteData(4)..setUint32(0, v)).buffer.asUint8List();

  Future<Uint8List> buildBackup(String password) async {
    if (_dek == null) throw StateError('vault locked');
    final images = <String, String>{};
    var missing = 0;
    for (final n in notes) {
      for (final id in n.imageIds) {
        if (images.containsKey(id)) continue;
        final b = await loadImage(id);
        if (b != null) {
          images[id] = base64Encode(b);
        } else {
          missing++;
        }
      }
    }
    lastBackupMissing = missing;
    final payload = jsonEncode({
      'v': 1,
      'app': 'mido_notes',
      'exportedAt': DateTime.now().toIso8601String(),
      'notes': notes.map((n) => n.toJson()).toList(),
      'folders': folders.map((f) => f.toJson()).toList(),
      'tomb': _writeTomb(tombstones),
      'ftomb': _writeTomb(folderTombstones),
      'lockpw': _lockJson(),
      'images': images,
    });
    final packed = gzip.encode(utf8.encode(payload));
    final salt = VaultCrypto.randomBytes(VaultCrypto.saltLength);
    const iter = VaultCrypto.kdfIterations;
    final key = await VaultCrypto.deriveKey(password, salt, iter);
    final enc = await VaultCrypto.encrypt(packed, key);
    final out = BytesBuilder()
      ..add(_backupMagic)
      ..addByte(1)
      ..add(_u32(iter))
      ..add(salt)
      ..add(enc);
    return out.toBytes();
  }

  /// 檢查檔頭是不是 Mido筆記 的備份檔（不需要密碼）。
  static bool looksLikeBackup(Uint8List data) {
    return data.length >= 53 &&
        data[0] == _backupMagic[0] &&
        data[1] == _backupMagic[1] &&
        data[2] == _backupMagic[2] &&
        data[3] == _backupMagic[3];
  }

  Future<Map<String, dynamic>> _openBackup(Uint8List data, String password) async {
    if (!looksLikeBackup(data)) {
      throw FormatException(tr('這不是 Mido筆記 的備份檔'));
    }
    if (data[4] != 1) {
      throw FormatException(tr('這個備份檔的版本太新，請先更新 App'));
    }
    final iter = ByteData.sublistView(data, 5, 9).getUint32(0);
    if (iter < 10000 || iter > 5000000) {
      throw FormatException(tr('備份檔已損毀'));
    }
    final salt = data.sublist(9, 25);
    final body = data.sublist(25);
    final key = await VaultCrypto.deriveKey(password, salt, iter);
    // 密碼錯誤或檔案被改過，這一步會丟出例外
    final plain = await VaultCrypto.decrypt(body, key);
    final json = utf8.decode(gzip.decode(plain));
    return jsonDecode(json) as Map<String, dynamic>;
  }

  static Map<String, DateTime> _readTomb(Object? raw) {
    final out = <String, DateTime>{};
    final cutoff = DateTime.now().subtract(const Duration(days: 120));
    if (raw is Map) {
      for (final e in raw.entries) {
        final t = DateTime.tryParse('${e.value}');
        if (t != null && t.isAfter(cutoff)) out['${e.key}'] = t;
      }
    }
    return out;
  }

  static Map<String, String> _writeTomb(Map<String, DateTime> m) =>
      {for (final e in m.entries) e.key: e.value.toIso8601String()};

  /// 最近一次資料變更的時間（含永久刪除），用來判斷需不需要同步上傳。
  DateTime? get lastChangeAt {
    DateTime? t;
    void see(DateTime? d) {
      if (d != null && (t == null || d.isAfter(t!))) t = d;
    }

    for (final n in notes) {
      see(n.updatedAt);
      see(n.deletedAt);
    }
    tombstones.values.forEach(see);
    folderTombstones.values.forEach(see);
    return t;
  }

  /// 只驗證備份密碼是否正確（不會改動任何資料）。密碼錯誤會丟出例外。
  Future<void> verifyBackup(Uint8List data, String password) async {
    await _openBackup(data, password);
  }

  /// 不解鎖，只檢查輸入的是不是目前的主密碼。
  Future<bool> checkPassword(String password) async {
    try {
      final header = await _readHeader();
      final kek = await VaultCrypto.deriveKey(
        password,
        base64Decode(header['salt'] as String),
        header['iter'] as int,
      );
      await VaultCrypto.decrypt(base64Decode(header['wrapped'] as String), kek);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 新裝置第一次使用：用雲端備份建立資料庫，並以備份密碼當作主密碼。
  Future<BackupSummary> createVaultFromBackup(
    Uint8List data,
    String password,
  ) async {
    final map = await _openBackup(data, password); // 密碼錯誤會在這裡丟出例外
    await createVault(password);
    return _applyBackup(map, replace: true);
  }

  /// 還原備份。[replace] 為 true 時整個取代；否則「合併」：
  /// 沒有的就新增，兩邊都有的以修改時間較新的為準；
  /// 別台裝置已永久刪除的筆記也會一併移除。
  Future<BackupSummary> restoreBackup(
    Uint8List data,
    String password, {
    required bool replace,
  }) async {
    if (_dek == null) throw StateError('vault locked');
    final map = await _openBackup(data, password); // 密碼錯誤／檔案損毀會在這裡丟出
    try {
      final s = await _applyBackup(map, replace: replace);
      await _saveChain;
      if (lastSaveError != null) throw lastSaveError!;
      return s;
    } catch (e) {
      throw RestoreWriteException(e);
    }
  }

  Future<BackupSummary> _applyBackup(
    Map<String, dynamic> map, {
    required bool replace,
  }) async {
    final dek = _dek;
    if (dek == null) throw StateError('vault locked');

    final inNotes = <Note>[
      for (final e in (map['notes'] as List?) ?? const <dynamic>[])
        Note.fromJson(e as Map<String, dynamic>),
    ];
    final inFolders = <Folder>[
      for (final e in (map['folders'] as List?) ?? const <dynamic>[])
        Folder.fromJson(e as Map<String, dynamic>),
    ];
    final inTomb = _readTomb(map['tomb']);
    final inFTomb = _readTomb(map['ftomb']);
    final images = (map['images'] as Map?) ?? const <dynamic, dynamic>{};
    if (replace || !hasLockPassword) {
      if (map['lockpw'] != null || replace) _readLock(map['lockpw']);
    }

    var imgCount = 0;
    for (final e in images.entries) {
      final id = e.key as String;
      if (!replace && File(_imageFile(id).path).existsSync()) continue;
      final bytes = base64Decode(e.value as String);
      final enc = await VaultCrypto.encrypt(bytes, dek);
      await _atomicWrite(_imageFile(id), enc);
      imgCount++;
    }
    _imageCache.clear();

    var added = 0;
    var updated = 0;
    var kept = 0;
    var removed = 0;
    var localOnly = 0;
    if (replace) {
      final keep = <String>{};
      for (final n in inNotes) {
        keep.addAll(n.imageIds);
      }
      for (final n in notes) {
        for (final id in n.imageIds) {
          if (!keep.contains(id)) deleteImageFile(id);
        }
      }
      notes
        ..clear()
        ..addAll(inNotes);
      folders
        ..clear()
        ..addAll(inFolders);
      tombstones
        ..clear()
        ..addAll(inTomb);
      folderTombstones
        ..clear()
        ..addAll(inFTomb);
      added = inNotes.length;
    } else {
      // 1. 合併刪除記號（取較新的時間）
      for (final e in inTomb.entries) {
        final cur = tombstones[e.key];
        if (cur == null || e.value.isAfter(cur)) tombstones[e.key] = e.value;
      }
      for (final e in inFTomb.entries) {
        final cur = folderTombstones[e.key];
        if (cur == null || e.value.isAfter(cur)) folderTombstones[e.key] = e.value;
      }
      // 2. 套用刪除：本機筆記若在刪除之後沒再修改，就移除
      for (final e in tombstones.entries) {
        final i = notes.indexWhere((x) => x.id == e.key);
        if (i >= 0 && !notes[i].updatedAt.isAfter(e.value)) {
          for (final img in notes[i].imageIds) {
            deleteImageFile(img);
          }
          notes.removeAt(i);
          removed++;
        }
      }
      // 3. 資料夾
      for (final f in inFolders) {
        final t = folderTombstones[f.id];
        if (t != null) continue;
        if (!folders.any((x) => x.id == f.id)) folders.add(f);
      }
      folders.removeWhere((f) => folderTombstones.containsKey(f.id));
      // 4. 筆記
      for (final n in inNotes) {
        final t = tombstones[n.id];
        if (t != null) {
          if (n.updatedAt.isAfter(t)) {
            tombstones.remove(n.id); // 刪除後又被編輯過，保留編輯的版本
          } else {
            continue; // 已被永久刪除，不要復活
          }
        }
        final i = notes.indexWhere((x) => x.id == n.id);
        if (i < 0) {
          notes.add(n);
          added++;
        } else if (n.updatedAt.isAfter(notes[i].updatedAt)) {
          notes[i] = n;
          updated++;
        } else if (notes[i].updatedAt.isAfter(n.updatedAt)) {
          kept++; // 本機比較新
        }
      }
      final inIds = inNotes.map((n) => n.id).toSet();
      localOnly = notes.where((n) => !inIds.contains(n.id)).length +
          tombstones.keys.where((k) => !inTomb.containsKey(k)).length;
      // 5. 指到已不存在的資料夾，放回「未分類」
      final ids = folders.map((f) => f.id).toSet();
      for (final n in notes) {
        if (n.folderId != null && !ids.contains(n.folderId)) n.folderId = null;
      }
    }
    notifyListeners();
    await _persist();
    return BackupSummary(
      added: added,
      updated: updated,
      kept: kept,
      images: imgCount,
      removed: removed,
      localOnly: localOnly,
    );
  }

  // ───────────────────────── 匯入 CSV 帳密 ─────────────────────────

  /// 把匯入的帳密依網站合併成「帳號密碼」筆記（同一個網站的多個帳號放在同一則）。
  /// 已經有同網站的筆記時，直接補上缺少的帳號；完全相同的帳號會略過，所以重複匯入不會產生重複資料。
  Future<LoginImportSummary> importLogins(
    List<ImportedLogin> items, {
    List<String> tags = const <String>[],
  }) async {
    if (_dek == null) throw StateError('vault locked');

    final groups = <String, List<ImportedLogin>>{};
    var anon = 0;
    for (final it in items) {
      var key = siteKey(it.url, it.name);
      if (key.isEmpty) key = '#${anon++}';
      groups.putIfAbsent(key, () => <ImportedLogin>[]).add(it);
    }

    var created = 0;
    var merged = 0;
    var accounts = 0;
    var duplicates = 0;
    final now = DateTime.now();

    for (final e in groups.entries) {
      final list = e.value;
      Note? existing;
      if (!e.key.startsWith('#')) {
        for (final n in notes) {
          if (n.type == NoteType.login &&
              !n.isTrashed &&
              siteKey(n.site, n.title) == e.key) {
            existing = n;
            break;
          }
        }
      }

      final first = list.first;
      final target = existing ??
          Note(
            id: _uuid.v4(),
            type: NoteType.login,
            title: first.name.isNotEmpty ? first.name : first.url,
            site: first.url.isNotEmpty ? first.url : first.name,
            tags: List<String>.of(tags),
          );

      var addedHere = 0;
      for (final it in list) {
        final same = target.credentials.any(
          (c) => c.username == it.username && c.password == it.password,
        );
        if (same) {
          duplicates++;
          continue;
        }
        target.credentials.add(
          Credential(username: it.username, password: it.password),
        );
        addedHere++;
        final note = it.note.trim();
        if (note.isNotEmpty) {
          final line = it.username.isNotEmpty ? '${it.username}：$note' : note;
          target.body = target.body.isEmpty ? line : '${target.body}\n$line';
        }
      }
      if (addedHere == 0) continue;

      if (existing == null) {
        notes.add(target);
        created++;
      } else {
        target.updatedAt = now;
        merged++;
      }
      accounts += addedHere;
    }

    notifyListeners();
    await _persist();
    return LoginImportSummary(
      created: created,
      merged: merged,
      accounts: accounts,
      duplicates: duplicates,
    );
  }

  // ───────────────────────── 存檔 ─────────────────────────

  Future<void> _persist() {
    final dek = _dek;
    if (dek == null) return Future<void>.value();
    // 先在同步階段取得快照，之後的修改不會混進這次存檔。
    final json = jsonEncode({
      'v': 1,
      'notes': notes.map((n) => n.toJson()).toList(),
      'folders': folders.map((f) => f.toJson()).toList(),
      'tomb': _writeTomb(tombstones),
      'ftomb': _writeTomb(folderTombstones),
      'lockpw': _lockJson(),
    });
    _saveChain = _saveChain.then((_) async {
      final enc = await VaultCrypto.encrypt(utf8.encode(json), dek);
      await _atomicWrite(_vaultFile, enc);
      lastSaveError = null;
      await _flushPendingDeletes();
    }).catchError((Object e) {
      lastSaveError = e;
      debugPrint('save failed: $e');
    });
    return _saveChain;
  }

  Future<void> _atomicWrite(File target, List<int> data) async {
    final tmp = File('${target.path}.tmp');
    await tmp.writeAsBytes(data, flush: true);
    await tmp.rename(target.path);
  }
}
