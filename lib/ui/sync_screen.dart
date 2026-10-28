import 'package:flutter/material.dart';

import '../app_state.dart';
import '../data/vault_store.dart';
import '../i18n.dart';
import '../sync/sync_service.dart';
import 'common.dart';

/// 雲端同步（Google 雲端硬碟）設定與狀態。
class SyncScreen extends StatefulWidget {
  const SyncScreen({super.key});

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  bool? _signedIn;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final s = await syncService.auth.isSignedIn();
    if (mounted) setState(() => _signedIn = s);
  }

  Future<void> _info(String title, String msg) => showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(msg),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(tr('確定')),
            ),
          ],
        ),
      );

  Future<String?> _askPw({required String title, String? message, bool confirm = true}) {
    final c1 = TextEditingController();
    final c2 = TextEditingController();
    String? error;
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (message != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(message),
                  ),
                TextField(
                  controller: c1,
                  obscureText: true,
                  autofocus: true,
                  decoration: InputDecoration(labelText: tr('同步密碼')),
                ),
                if (confirm)
                  TextField(
                    controller: c2,
                    obscureText: true,
                    decoration: InputDecoration(labelText: tr('再輸入一次')),
                  ),
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
            FilledButton(
              onPressed: () {
                if (c1.text.length < 8) {
                  setState(() => error = tr('同步密碼至少需要 8 個字元'));
                  return;
                }
                if (confirm && c1.text != c2.text) {
                  setState(() => error = tr('兩次輸入的密碼不一致'));
                  return;
                }
                Navigator.pop(ctx, c1.text);
              },
              child: Text(tr('確定')),
            ),
          ],
        ),
      ),
    );
  }

  String get _pwHelp =>
      tr('兩台裝置要設定「相同」的同步密碼。雲端檔案會用這組密碼加密，Google 和開發者都看不到內容；忘記就無法讀取雲端資料。');

  Future<void> _login() async {
    setState(() => _busy = true);
    try {
      await syncService.auth.signIn();
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        await _info(tr('登入失敗'), '$e');
      }
      return;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    await _refresh();
    if (!mounted) return;
    final pw = await _askPw(title: tr('設定同步密碼'), message: _pwHelp);
    if (pw == null) return;
    await syncService.setPassword(pw);
    await syncService.enable();
  }

  Future<void> _toggle(bool on) async {
    if (on) {
      if (!await syncService.hasPassword()) {
        final pw = await _askPw(title: tr('設定同步密碼'), message: _pwHelp);
        if (pw == null) return;
        await syncService.setPassword(pw);
      }
      await syncService.enable();
    } else {
      await syncService.disable();
    }
  }

  Future<void> _syncNow() async {
    if (vault.status != VaultStatus.unlocked) return;
    final ok = await syncService.syncNow();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(ok ? tr('同步完成') : tr('同步失敗'))));
  }

  Future<void> _reenterPw() async {
    final pw = await _askPw(
      title: tr('重新輸入同步密碼'),
      message: tr('輸入另一台裝置使用的同步密碼。'),
      confirm: false,
    );
    if (pw == null) return;
    await syncService.setPassword(pw);
    await _syncNow();
  }

  Future<void> _overwrite() async {
    final go = await confirmDialog(
      context,
      title: tr('用新密碼覆蓋雲端資料'),
      message: tr('會把這支裝置上的資料，用你接著輸入的新同步密碼整份覆蓋到雲端。其他裝置之後需要用「重新輸入同步密碼」改成相同的新密碼。\n\n雲端上原有、但這支裝置沒有的內容會被覆蓋。確定要繼續嗎？'),
      confirmText: tr('繼續'),
      danger: true,
    );
    if (!go || !mounted) return;
    final pw = await _askPw(title: tr('新的同步密碼'));
    if (pw == null) return;
    final ok = await syncService.overwriteRemote(pw);
    if (!mounted) return;
    await _info(
      ok ? tr('已覆蓋') : tr('失敗'),
      ok ? tr('雲端資料已用新同步密碼更新。') : (syncService.lastError ?? ''),
    );
  }

  Future<void> _deleteRemote() async {
    final go = await confirmDialog(
      context,
      title: tr('刪除雲端同步檔'),
      message: tr('只會刪除 Google 雲端硬碟裡的同步檔，不影響這支裝置上的筆記。之後再同步會重新上傳。'),
      confirmText: tr('刪除'),
      danger: true,
    );
    if (!go) return;
    try {
      await syncService.deleteRemote();
      if (mounted) await _info(tr('已刪除'), tr('雲端同步檔已刪除。'));
    } catch (e) {
      if (mounted) await _info(tr('失敗'), '$e');
    }
  }

  Future<void> _signOut() async {
    final go = await confirmDialog(
      context,
      title: tr('登出 Google'),
      message: tr('會停止自動同步並清除這支裝置上的登入資訊，雲端上的檔案不會被刪除。'),
      confirmText: tr('登出'),
    );
    if (!go) return;
    await syncService.signOut();
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([syncService, appSettings]),
      builder: (context, _) {
        final cs = Theme.of(context).colorScheme;
        final signed = _signedIn;
        final last = appSettings.lastSyncAt;
        return Scaffold(
          appBar: AppBar(title: Text(tr('雲端同步'))),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    tr('用你自己的 Google 雲端硬碟當周轉站，在多台裝置之間自動同步筆記。上傳前會先在本機加密，存進 App 專用的隱藏資料夾，App 看不到你雲端硬碟裡其他的檔案。預設關閉。'),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (signed == null)
                const Center(child: CircularProgressIndicator())
              else if (!signed)
                FilledButton.icon(
                  onPressed: _busy ? null : _login,
                  icon: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.login),
                  label: Text(_busy ? tr('請在瀏覽器完成登入…') : tr('登入 Google')),
                )
              else ...[
                SwitchListTile(
                  secondary: const Icon(Icons.cloud_sync_outlined),
                  title: Text(tr('自動同步')),
                  subtitle: Text(tr('開啟、解鎖、切回 App 時拉取；儲存後自動上傳')),
                  value: appSettings.syncEnabled,
                  onChanged: _toggle,
                ),
                ListTile(
                  leading: syncService.syncing
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync),
                  title: Text(tr('立即同步')),
                  subtitle: Text(
                    last == null
                        ? tr('尚未同步過')
                        : tr('上次同步：${fmtDate(last, full: true)}'),
                  ),
                  onTap: syncService.syncing ? null : _syncNow,
                ),
                if (syncService.lastError != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Text(
                      syncService.lastError!,
                      style: TextStyle(color: cs.error),
                    ),
                  ),
                if (syncService.lastWarning != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Text(syncService.lastWarning!),
                  ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.key_outlined),
                  title: Text(tr('重新輸入同步密碼')),
                  subtitle: Text(tr('另一台裝置換了密碼，或輸入錯誤時使用')),
                  onTap: _reenterPw,
                ),
                ListTile(
                  leading: const Icon(Icons.cloud_upload_outlined),
                  title: Text(tr('用新密碼覆蓋雲端資料')),
                  subtitle: Text(tr('更換同步密碼時使用')),
                  onTap: _overwrite,
                ),
                ListTile(
                  leading: const Icon(Icons.delete_outline),
                  title: Text(tr('刪除雲端同步檔')),
                  onTap: _deleteRemote,
                ),
                ListTile(
                  leading: const Icon(Icons.logout),
                  title: Text(tr('登出 Google')),
                  onTap: _signOut,
                ),
              ],
              const SizedBox(height: 16),
              Text(
                tr('注意：同一則筆記在兩台裝置同時被修改時，以修改時間較新的為準。圖片與錄音也會一起同步，檔案大時需要較多時間與流量。'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        );
      },
    );
  }
}
