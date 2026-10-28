import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../app_state.dart';
import '../data/vault_store.dart';
import '../i18n.dart';
import 'drive_api.dart';
import 'google_auth.dart';

class SyncException implements Exception {
  SyncException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// 透過 Google 雲端硬碟 appDataFolder 在多台裝置之間同步（上傳的是加密過的檔案）。
///
/// 流程：先下載雲端檔（若比上次看到的新）並「合併」進本機，再視需要把合併後的結果上傳。
/// 合併規則沿用「備份還原 → 合併」：以每則筆記的修改時間為準，並處理刪除記號。
class SyncService extends ChangeNotifier with WidgetsBindingObserver {
  final GoogleAuth auth = GoogleAuth();
  late final DriveSync drive = DriveSync(auth);

  static const FlutterSecureStorage _secure = FlutterSecureStorage();
  static const String _pwKey = 'mido_sync_pw';

  bool syncing = false;
  String? lastError;
  String? lastWarning;

  Timer? _debounce;
  VaultStatus? _prev;
  bool _again = false;

  void init() {
    WidgetsBinding.instance.addObserver(this);
    vault.addListener(_onVault);
    vault.addBeforeLock(_beforeLock);
    _prev = vault.status;
    // 無主密碼模式啟動時已經是解鎖狀態，不會再有「剛解鎖」事件，這裡補一次拉取。
    if (appSettings.syncEnabled && _prev == VaultStatus.unlocked) {
      unawaited(syncNow());
    }
  }

  // ───────────────────────── 設定 ─────────────────────────

  Future<bool> hasPassword() async {
    try {
      final p = await _secure.read(key: _pwKey);
      return p != null && p.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<void> setPassword(String pw) => _secure.write(key: _pwKey, value: pw);

  Future<void> enable() async {
    await appSettings.setSyncState(enabled: true);
    unawaited(syncNow());
  }

  Future<void> disable() async {
    _debounce?.cancel();
    await appSettings.setSyncState(enabled: false);
  }

  /// 登出 Google 並清除同步設定（不會刪除雲端上的檔案）。
  Future<void> signOut() async {
    _debounce?.cancel();
    await auth.signOut();
    try {
      await _secure.delete(key: _pwKey);
    } catch (_) {}
    await appSettings.setSyncState(
      enabled: false,
      clearState: true,
    );
    lastError = null;
    notifyListeners();
  }

  /// 用目前的同步密碼把本機資料整份覆蓋到雲端（用於更換同步密碼）。
  Future<bool> overwriteRemote(String pw) async {
    if (vault.status != VaultStatus.unlocked) return false;
    if (syncing) return false;
    syncing = true;
    lastError = null;
    notifyListeners();
    try {
      await setPassword(pw);
      final file = await drive.find();
      final snap = vault.lastChangeAt;
      final data = await vault.buildBackup(pw);
      final up = await drive.upload(data, id: file?.id);
      await appSettings.setSyncState(
        remoteMd5: up.md5 ?? '',
        uploadedChange: snap?.toIso8601String() ?? '',
        lastSyncAt: DateTime.now(),
      );
      return true;
    } catch (e) {
      lastError = _msg(e);
      return false;
    } finally {
      syncing = false;
      notifyListeners();
    }
  }

  Future<void> deleteRemote() async {
    final file = await drive.find();
    if (file != null) await drive.delete(file.id);
    await appSettings.setSyncState(clearState: true);
  }

  // ───────────────────────── 觸發時機 ─────────────────────────

  bool get _isDirty =>
      (vault.lastChangeAt?.toIso8601String() ?? '') !=
      (appSettings.syncUploadedChange ?? '');

  void _onVault() {
    final st = vault.status;
    final becameUnlocked = st == VaultStatus.unlocked && _prev != VaultStatus.unlocked;
    _prev = st;
    if (!appSettings.syncEnabled || st != VaultStatus.unlocked) return;
    if (becameUnlocked) {
      unawaited(syncNow());
      return;
    }
    if (_isDirty) _schedule();
  }

  void _schedule() {
    if (syncing) {
      _again = true;
      return;
    }
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 6), () => unawaited(syncNow()));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        appSettings.syncEnabled &&
        vault.status == VaultStatus.unlocked) {
      unawaited(syncNow());
    }
  }

  Future<void> _beforeLock() async {
    if (!appSettings.syncEnabled || syncing || !_isDirty) return;
    _debounce?.cancel();
    try {
      await syncNow().timeout(const Duration(seconds: 15));
    } catch (_) {}
  }

  // ───────────────────────── 同步 ─────────────────────────

  String _msg(Object e) {
    if (e is RestoreWriteException) {
      return tr('寫入這支裝置時失敗（可能是儲存空間不足）：') + '${e.cause}';
    }
    final s = '$e';
    if (e is GoogleAuthException || e is DriveException || e is SyncException) {
      return s;
    }
    if (e is TimeoutException) return tr('連線逾時，請檢查網路後再試。');
    return tr('同步失敗：') + s;
  }

  Future<bool> syncNow() async {
    if (syncing) {
      _again = true;
      return false;
    }
    if (vault.status != VaultStatus.unlocked) return false;
    String? pw;
    try {
      pw = await _secure.read(key: _pwKey);
    } catch (_) {}
    if (pw == null || pw.isEmpty) {
      lastError = tr('尚未設定同步密碼。');
      notifyListeners();
      return false;
    }

    syncing = true;
    lastError = null;
    lastWarning = null;
    notifyListeners();
    var ok = false;
    try {
      final dirtyBefore = _isDirty;
      final file = await drive.find();
      var push = file == null || dirtyBefore;

      if (file != null && file.md5 != appSettings.syncRemoteMd5) {
        final Uint8List bytes = await drive.download(file.id);
        try {
          final s = await vault.restoreBackup(bytes, pw, replace: false);
          if (s.needsPush) push = true;
        } on RestoreWriteException {
          rethrow;
        } on FormatException catch (e) {
          throw SyncException(e.message);
        } catch (_) {
          throw SyncException(
            tr('同步密碼不正確，或雲端檔案已損毀。請確認兩台裝置設定的同步密碼相同。'),
          );
        }
      }

      if (push) {
        final snap = vault.lastChangeAt;
        final data = await vault.buildBackup(pw);
        final up = await drive.upload(data, id: file?.id);
        if (vault.lastBackupMissing > 0) {
          lastWarning = tr('有 ${vault.lastBackupMissing} 個附件讀取失敗，沒有同步上去。');
        }
        await appSettings.setSyncState(
          remoteMd5: up.md5 ?? '',
          uploadedChange: snap?.toIso8601String() ?? '',
        );
      } else {
        await appSettings.setSyncState(
          remoteMd5: file?.md5 ?? '',
          uploadedChange: vault.lastChangeAt?.toIso8601String() ?? '',
        );
      }
      await appSettings.setSyncState(lastSyncAt: DateTime.now());
      ok = true;
    } catch (e) {
      lastError = _msg(e);
      debugPrint('sync failed: $e');
    } finally {
      syncing = false;
      notifyListeners();
      if (_again) {
        _again = false;
        if (ok && _isDirty && appSettings.syncEnabled) _schedule();
      }
    }
    return ok;
  }
}

final SyncService syncService = SyncService();
