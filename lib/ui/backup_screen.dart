import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../app_state.dart';
import '../data/login_import.dart';
import '../data/vault_store.dart';
import 'common.dart';
import '../i18n.dart';

/// 備份與還原：加密備份檔的匯出／匯入，以及匯入 Chrome／Google 密碼 CSV。
class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  bool _busyOpen = false;
  static final bool _desktop =
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  static Map<int, String> get _remindOptions => <int, String>{
    0: tr('不提醒'),
    7: tr('每 7 天'),
    14: tr('每 14 天'),
    30: tr('每 30 天'),
  };

  // ───────────────────────── 共用對話框 ─────────────────────────

  void _showBusy(String msg) {
    _busyOpen = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
              const SizedBox(width: 20),
              Expanded(child: Text(msg)),
            ],
          ),
        ),
      ),
    );
  }

  void _hideBusy() {
    if (_busyOpen && mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
    _busyOpen = false;
  }

  Future<void> _info(String title, String message) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr('知道了')),
          ),
        ],
      ),
    );
  }

  Future<String?> _askPassword({
    required String title,
    String? message,
    bool confirm = false,
  }) {
    final c1 = TextEditingController();
    final c2 = TextEditingController();
    String? error;
    var obscure = true;
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          void submit() {
            if (confirm) {
              if (c1.text.length < 8) {
                setState(() => error = tr('備份密碼至少需要 8 個字元'));
                return;
              }
              if (c1.text != c2.text) {
                setState(() => error = tr('兩次輸入的密碼不一致'));
                return;
              }
            } else if (c1.text.isEmpty) {
              setState(() => error = tr('請輸入密碼'));
              return;
            }
            Navigator.pop(ctx, c1.text);
          }

          return AlertDialog(
            title: Text(title),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (message != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        message,
                        style: Theme.of(ctx).textTheme.bodySmall,
                      ),
                    ),
                  TextField(
                    controller: c1,
                    obscureText: obscure,
                    autofocus: true,
                    enableSuggestions: false,
                    autocorrect: false,
                    enableIMEPersonalizedLearning: false,
                    keyboardType: TextInputType.visiblePassword,
                    decoration: InputDecoration(
                      labelText: tr('備份密碼'),
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscure ? Icons.visibility : Icons.visibility_off,
                        ),
                        onPressed: () => setState(() => obscure = !obscure),
                      ),
                    ),
                  ),
                  if (confirm) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: c2,
                      obscureText: obscure,
                      enableSuggestions: false,
                      autocorrect: false,
                      enableIMEPersonalizedLearning: false,
                      keyboardType: TextInputType.visiblePassword,
                      decoration: InputDecoration(
                        labelText: tr('再次輸入備份密碼'),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        error!,
                        style: TextStyle(color: Theme.of(ctx).colorScheme.error),
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(tr('取消')),
              ),
              FilledButton(onPressed: submit, child: Text(tr('確定'))),
            ],
          );
        },
      ),
    );
  }

  // ───────────────────────── 匯出加密備份 ─────────────────────────

  Future<void> _export() async {
    final pw = await _askPassword(
      title: tr('設定備份密碼'),
      message: tr('還原備份時需要輸入這組密碼，忘記就無法還原。可以和主密碼相同，也可以另外設定。'),
      confirm: true,
    );
    if (pw == null || !mounted) return;

    _showBusy(tr('正在加密備份…'));
    File file;
    try {
      final bytes = await vault.buildBackup(pw);
      final dir = await getTemporaryDirectory();
      // 清掉先前留在暫存區的舊備份檔
      for (final e in dir.listSync()) {
        if (e is File && e.path.endsWith('.mdbk')) {
          try {
            e.deleteSync();
          } catch (_) {}
        }
      }
      final d = DateTime.now();
      String two(int n) => n.toString().padLeft(2, '0');
      final stamp = '${d.year}${two(d.month)}${two(d.day)}_${two(d.hour)}${two(d.minute)}';
      file = File('${dir.path}/MidoNotes_$stamp.mdbk');
      await file.writeAsBytes(bytes, flush: true);
    } catch (e) {
      _hideBusy();
      if (mounted) await _info(tr('備份失敗'), '$e');
      return;
    }
    _hideBusy();
    if (!mounted) return;
    if (vault.lastBackupMissing > 0) {
      await _info(
        tr('部分附件沒有備份'),
        tr('有 ${vault.lastBackupMissing} 個附件讀取失敗（可能已損毀或遺失），沒有放進這份備份。請先檢查那些筆記的圖片／錄音。'),
      );
      if (!mounted) return;
    }

    if (_desktop) {
      try {
        final path = await vault.withExternal(
          () => FilePicker.platform.saveFile(
            dialogTitle: tr('儲存加密備份檔'),
            fileName: file.uri.pathSegments.last,
            type: FileType.any,
          ),
        );
        if (path != null) {
          await File(path).writeAsBytes(await file.readAsBytes(), flush: true);
          await appSettings.markBackupDone();
          if (mounted) {
            await _info(tr('備份檔已儲存'), tr('已存到：$path\n\n請放到安全的地方。還原時需要你剛才設定的備份密碼。'));
          }
        }
      } catch (e) {
        if (mounted) await _info(tr('儲存失敗'), '$e');
      }
      return;
    }

    try {
      final result = await vault.withExternal(
        () => Share.shareXFiles(
          [XFile(file.path, mimeType: 'application/octet-stream')],
          subject: tr('Mido筆記 加密備份'),
        ),
      );
      if (result.status != ShareResultStatus.dismissed) {
        await appSettings.markBackupDone();
        if (mounted) {
          await _info(
            tr('備份檔已建立'),
            tr('請確認有存到雲端硬碟或其他安全的地方。還原時需要你剛才設定的備份密碼。'),
          );
        }
      }
    } catch (e) {
      if (mounted) await _info(tr('無法開啟分享選單'), '$e');
    }
  }

  // ───────────────────────── 匯入備份檔 ─────────────────────────

  Future<void> _import() async {
    final res = await vault.withExternal(
      () => FilePicker.platform.pickFiles(type: FileType.any, withData: true),
    );
    if (res == null || res.files.isEmpty || !mounted) return;
    final f = res.files.single;
    final bytes = f.bytes;
    if (bytes == null) {
      await _info(tr('讀取失敗'), tr('沒辦法讀取這個檔案，請換一個位置再試一次。'));
      return;
    }
    await _restoreFlow(bytes, cleanupPath: f.path);
  }

  /// 還原流程。[presetPw] 有值時先用它嘗試，不對再詢問。
  Future<void> _restoreFlow(
    Uint8List bytes, {
    String? cleanupPath,
    String? presetPw,
  }) async {
    if (!VaultStore.looksLikeBackup(bytes)) {
      await _info(tr('不是備份檔'), tr('這個檔案不是 Mido筆記 的加密備份檔。'));
      return;
    }

    final mode = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('怎麼還原？')),
        content: Text(
          tr('合併（建議）：保留目前這支手機上的內容，補上備份裡沒有的；兩邊都有的以修改時間較新的為準。\n\n'
          '取代全部：整個換成備份裡的內容，目前這支手機上的筆記會消失。'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr('取消')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'replace'),
            child: Text(tr('取代全部')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'merge'),
            child: Text(tr('合併')),
          ),
        ],
      ),
    );
    if (mode == null || !mounted) return;

    var pw = presetPw;
    var attempt = 0;
    while (true) {
      if (pw == null) {
        pw = await _askPassword(title: tr('輸入備份密碼'));
        if (pw == null || !mounted) return;
      }
      _showBusy(tr('正在還原…'));
      try {
        final s =
            await vault.restoreBackup(bytes, pw, replace: mode == 'replace');
        _hideBusy();
        await _deleteIfPickerCopy(cleanupPath);
        if (!mounted) return;
        await _info(
          tr('還原完成'),
          mode == 'replace'
              ? tr('已還原 ${s.added} 則筆記、${s.images} 張圖片。')
              : tr('新增 ${s.added} 則、以備份較新版本更新 ${s.updated} 則、保留手機上較新的 ${s.kept} 則；還原 ${s.images} 張圖片。'),
        );
        return;
      } on FormatException catch (e) {
        _hideBusy();
        if (mounted) await _info(tr('無法還原'), e.message);
        return;
      } on RestoreWriteException catch (e) {
        _hideBusy();
        if (mounted) {
          await _info(
            tr('還原失敗'),
            tr('備份密碼正確，但寫入這支裝置時失敗（可能是儲存空間不足）。請清出空間後再試。\n\n${e.cause}'),
          );
        }
        return;
      } catch (_) {
        _hideBusy();
        attempt++;
        if (!mounted) return;
        if (attempt >= 5) {
          await _info(tr('無法還原'), tr('備份密碼錯誤，或備份檔已損毀。'));
          return;
        }
        pw = null; // 密碼不對，改為請使用者輸入
        await _info(tr('密碼不正確'), tr('備份密碼錯誤，或備份檔已損毀。請再輸入一次。'));
      }
    }
  }

  // ───────────────────────── 匯入 CSV ─────────────────────────

  String? _pickedCsvPath;

  Future<void> _importCsv() async {
    try {
      await _importCsvCore();
    } finally {
      await _deleteIfPickerCopy(_pickedCsvPath); // 內含明文密碼的暫存複本
      _pickedCsvPath = null;
    }
  }

  /// 只刪除檔案選擇器在 App 暫存區產生的複本；絕不刪使用者自己的原始檔
  /// （桌面版選擇器回傳的是原檔路徑，不是複本）。
  Future<void> _deleteIfPickerCopy(String? path) async {
    if (path == null || _desktop) return;
    try {
      final t = (await getTemporaryDirectory()).path;
      final sep = Platform.pathSeparator;
      final root = t.endsWith(sep) ? t : '$t$sep';
      if (!path.startsWith(root)) return;
      await File(path).delete();
    } catch (_) {}
  }

  Future<void> _importCsvCore() async {
    final go = await confirmDialog(
      context,
      title: tr('匯入 Chrome / Google 密碼'),
      message: tr('請先在 Chrome 的「密碼管理工具 → 設定 → 匯出密碼」匯出 CSV 檔。\n\n'
          'CSV 裡的密碼是明文，匯入完成後請務必刪除這個檔案，並清空手機的垃圾桶。'),
      confirmText: tr('選擇檔案'),
    );
    if (!go || !mounted) return;

    final res = await vault.withExternal(
      () => FilePicker.platform.pickFiles(type: FileType.any, withData: true),
    );
    if (res == null || res.files.isEmpty || !mounted) return;
    final f = res.files.single;
    final bytes = f.bytes;
    if (bytes == null) {
      await _info(tr('讀取失敗'), tr('沒辦法讀取這個檔案，請換一個位置再試一次。'));
      return;
    }

    final parsed = parseLoginCsv(utf8.decode(bytes, allowMalformed: true));
    _pickedCsvPath = f.path; // 匯入結束後才清（見 _importCsv）
    if (parsed == null) {
      if (mounted) {
        await _info(tr('看不出是密碼檔'), tr('這個檔案不像帳號密碼的 CSV（需要有 password 欄位）。'));
      }
      return;
    }
    if (!mounted) return;

    final groups = countSiteGroups(parsed.items);
    final ok = await confirmDialog(
      context,
      title: tr('準備匯入'),
      message: tr('讀到 ${parsed.items.length} 筆帳號密碼，會依網站合併成約 $groups 則「帳號密碼」筆記'
          '（同一個網站的多個帳號放在同一則）。\n\n'
          '已經有的同網站筆記會直接補上帳號，完全相同的會略過。新增的筆記會加上「匯入」標籤，方便你檢查。'),
      confirmText: tr('匯入'),
    );
    if (!ok || !mounted) return;

    _showBusy(tr('正在匯入…'));
    try {
      final s = await vault.importLogins(parsed.items, tags: [tr('匯入')]);
      _hideBusy();
      if (!mounted) return;
      await _info(
        tr('匯入完成'),
        tr('新增 ${s.created} 則筆記、補進 ${s.merged} 則既有筆記，共新增 ${s.accounts} 組帳號') +
            (s.duplicates > 0 ? tr('（略過 ${s.duplicates} 組完全相同的）') : '') +
            tr('。\n\n別忘了刪除原本的 CSV 檔案。'),
      );
    } catch (e) {
      _hideBusy();
      if (mounted) await _info(tr('匯入失敗'), '$e');
    }
  }

  // ───────────────────────── 提醒設定 ─────────────────────────

  Future<void> _pickRemind() async {
    final r = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(tr('備份提醒')),
        children: [
          for (final e in _remindOptions.entries)
            ListTile(
              leading: Icon(
                appSettings.backupRemindDays == e.key
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
              ),
              title: Text(e.value),
              onTap: () => Navigator.pop(ctx, e.key),
            ),
        ],
      ),
    );
    if (r != null) await appSettings.setBackupRemindDays(r);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([vault, appSettings]),
      builder: (context, _) {
        final live = vault.notes.where((n) => !n.isTrashed).length;
        final images = vault.notes.fold<int>(0, (s, n) => s + n.imageIds.length);
        final last = appSettings.lastBackupAt;
        final cs = Theme.of(context).colorScheme;
        final tt = Theme.of(context).textTheme;
        return Scaffold(
          appBar: AppBar(title: Text(tr('備份與還原'))),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Card(
                margin: EdgeInsets.zero,
                color: cs.surfaceContainerLow,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tr('目前有 $live 則筆記、$images 張圖片'), style: tt.titleSmall),
                      const SizedBox(height: 4),
                      Text(
                        last == null
                            ? tr('尚未備份過')
                            : tr('上次備份：${fmtDate(last, full: true)}'),
                        style: tt.bodyMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        tr('資料只存在這支手機。解除安裝 App 或換手機就會消失，請定期匯出備份並存到雲端硬碟。'),
                        style: tt.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _export,
                icon: const Icon(Icons.upload_file),
                label: Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text(tr('匯出加密備份檔')),
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _import,
                icon: const Icon(Icons.download),
                label: Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text(tr('從備份檔還原')),
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.notifications_outlined),
                title: Text(tr('備份提醒')),
                subtitle: Text(
                  _remindOptions[appSettings.backupRemindDays] ?? tr('不提醒'),
                ),
                onTap: _pickRemind,
              ),
              const Divider(height: 32),
              Text(tr('匯入其他地方的密碼'), style: tt.titleSmall),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _importCsv,
                icon: const Icon(Icons.table_chart_outlined),
                label: Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text(tr('匯入 Chrome / Google 密碼（CSV）')),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                tr('也支援 Edge、Firefox、Bitwarden、1Password 匯出的 CSV。同一個網站的多個帳號（例如很多個 Google 帳號）會合併成同一則筆記。'),
                style: tt.bodySmall,
              ),
            ],
          ),
        );
      },
    );
  }
}
