import 'dart:io';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_state.dart';
import '../main.dart' show MidoApp;
import '../update.dart';
import 'backup_screen.dart';
import 'changelog_screen.dart';
import 'common.dart';
import 'security_check_screen.dart';
import 'sync_screen.dart';
import '../i18n.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  static final bool _mobile = Platform.isAndroid || Platform.isIOS;

  static Map<int, String> get _lockOptions => <int, String>{
    0: tr('立即（離開 App 就鎖定）'),
    30: tr('30 秒'),
    60: tr('1 分鐘'),
    300: tr('5 分鐘'),
    900: tr('15 分鐘'),
  };


  static String _langName(String pref) {
    switch (pref) {
      case 'zh':
        return '繁體中文';
      case 'en':
        return 'English';
      default:
        return tr('跟隨系統');
    }
  }

  Future<void> _pickLang(BuildContext context) async {
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(tr('語言')),
        children: [
          for (final e in <String, String>{
            'auto': tr('跟隨系統'),
            'zh': '繁體中文',
            'en': 'English',
          }.entries)
            ListTile(
              leading: Icon(
                appSettings.langPref == e.key
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
              ),
              title: Text(e.value),
              onTap: () => Navigator.pop(ctx, e.key),
            ),
        ],
      ),
    );
    if (r != null) await appSettings.setLang(r);
  }

  static Future<void> _openUrl(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  /// 手動檢查更新：按下才連線 GitHub，不會自動檢查。
  Future<void> _checkUpdate(BuildContext context) async {
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
              Expanded(child: Text(tr('正在檢查…'))),
            ],
          ),
        ),
      ),
    );
    ReleaseInfo? rel;
    String? err;
    String current = '0';
    try {
      current = (await PackageInfo.fromPlatform()).version;
      rel = await fetchLatestRelease();
    } catch (e) {
      err = e.toString();
    }
    if (!context.mounted) return;
    Navigator.of(context).pop(); // 關掉「正在檢查」
    if (err != null || rel == null) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(tr('檢查失敗')),
          content: Text(err ?? ''),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(tr('確定')),
            ),
          ],
        ),
      );
      return;
    }
    final r = rel;
    final newer = compareVersion(r.version, current) > 0;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(newer ? tr('有新版本 ${r.version}') : tr('已經是最新版本')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                newer
                    ? tr('目前版本 $current，發布日期 ${r.publishedAt}')
                    : tr('目前版本 $current；GitHub 上最新版是 ${r.version}'),
              ),
              if (newer && r.body.trim().isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(r.body.trim()),
              ],
              if (newer) ...[
                const SizedBox(height: 12),
                Text(
                  tr('下載後直接安裝即可覆蓋舊版，你的筆記與設定不會消失。手機需允許瀏覽器安裝未知來源的 App；電腦版請解壓縮後覆蓋舊資料夾。'),
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr('關閉')),
          ),
          if (newer)
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                _openUrl(r.assetUrl ?? r.pageUrl);
              },
              child: Text(r.assetUrl != null ? tr('下載更新') : tr('開啟發布頁面')),
            ),
        ],
      ),
    );
  }

  Future<void> _toggleBio(BuildContext context, bool on) async {
    if (on) {
      final ok = await vault.enableBiometric();
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr('無法啟用：請確認手機已設定指紋或臉部辨識'))),
        );
      }
    } else {
      await vault.disableBiometric();
    }
  }

  Future<void> _pickLock(BuildContext context) async {
    final r = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(tr('自動鎖定')),
        children: [
          for (final e in _lockOptions.entries)
            ListTile(
              leading: Icon(
                appSettings.lockSeconds == e.key
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
              ),
              title: Text(e.value),
              onTap: () => Navigator.pop(ctx, e.key),
            ),
        ],
      ),
    );
    if (r != null) await appSettings.setLockSeconds(r);
  }

  Future<void> _setMaster(BuildContext context) async {
    final a = TextEditingController();
    final b = TextEditingController();
    String? error;
    var busy = false;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          Future<void> submit() async {
            if (a.text.length < 8) {
              setState(() => error = tr('主密碼至少需要 8 個字元'));
              return;
            }
            if (a.text != b.text) {
              setState(() => error = tr('兩次輸入的密碼不一致'));
              return;
            }
            setState(() {
              busy = true;
              error = null;
            });
            final ok = await vault.setMasterPassword(a.text);
            if (ctx.mounted) Navigator.pop(ctx);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(ok ? tr('已設定主密碼，下次開啟 App 需要輸入') : tr('設定失敗'))),
              );
            }
          }

          Widget f(TextEditingController c, String l) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextField(
                  controller: c,
                  obscureText: true,
                  enableSuggestions: false,
                  autocorrect: false,
                  enableIMEPersonalizedLearning: false,
                  keyboardType: TextInputType.visiblePassword,
                  decoration: InputDecoration(
                    labelText: l,
                    border: const OutlineInputBorder(),
                  ),
                ),
              );
          return AlertDialog(
            title: Text(tr('設定主密碼')),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  f(a, tr('新的主密碼')),
                  f(b, tr('再次輸入')),
                  if (error != null)
                    Text(error!, style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: busy ? null : () => Navigator.pop(ctx),
                child: Text(tr('取消')),
              ),
              FilledButton(
                onPressed: busy ? null : submit,
                child: busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(tr('設定')),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _removeMaster(BuildContext context) async {
    final c = TextEditingController();
    final pw = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('移除主密碼')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr('移除後，開啟 App 不需要輸入密碼，任何拿到你手機（或電腦）的人都能直接看到沒有鎖定的筆記。'
              '重要的筆記請用「鎖定」功能另外保護。'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: c,
              obscureText: true,
              autofocus: true,
              enableSuggestions: false,
              autocorrect: false,
              keyboardType: TextInputType.visiblePassword,
              decoration: InputDecoration(
                labelText: tr('輸入目前的主密碼'),
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('取消'))),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, c.text),
            child: Text(tr('移除')),
          ),
        ],
      ),
    );
    if (pw == null || !context.mounted) return;
    final ok = await vault.removeMasterPassword(pw);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? tr('已移除主密碼，之後開啟 App 不需要密碼') : tr('主密碼不正確'))),
    );
  }

  Future<void> _changePassword(BuildContext context) async {
    final oldC = TextEditingController();
    final newC = TextEditingController();
    final new2C = TextEditingController();
    String? error;
    var busy = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          Future<void> submit() async {
            if (newC.text.length < 8) {
              setState(() => error = tr('新密碼至少需要 8 個字元'));
              return;
            }
            if (newC.text != new2C.text) {
              setState(() => error = tr('兩次輸入的新密碼不一致'));
              return;
            }
            setState(() {
              busy = true;
              error = null;
            });
            final ok = await vault.changePassword(oldC.text, newC.text);
            if (ok) {
              if (ctx.mounted) Navigator.pop(ctx);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    duration: const Duration(seconds: 8),
                    content: Text(tr('主密碼已更新')),
                  ),
                );
              }
            } else {
              setState(() {
                busy = false;
                error = tr('目前的主密碼不正確');
              });
            }
          }

          Widget pwField(TextEditingController c, String label) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextField(
                  controller: c,
                  obscureText: true,
                  enableSuggestions: false,
                  autocorrect: false,
                  enableIMEPersonalizedLearning: false,
                  keyboardType: TextInputType.visiblePassword,
                  decoration: InputDecoration(
                    labelText: label,
                    border: const OutlineInputBorder(),
                  ),
                ),
              );

          return AlertDialog(
            title: Text(tr('修改主密碼')),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  pwField(oldC, tr('目前的主密碼')),
                  pwField(newC, tr('新的主密碼')),
                  pwField(new2C, tr('再次輸入新的主密碼')),
                  if (error != null)
                    Text(
                      error!,
                      style: TextStyle(color: Theme.of(ctx).colorScheme.error),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: busy ? null : () => Navigator.pop(ctx),
                child: Text(tr('取消')),
              ),
              FilledButton(
                onPressed: busy ? null : submit,
                child: busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(tr('更新')),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([vault, appSettings]),
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(title: Text(tr('設定'))),
          body: ListView(
            children: [
              _Section(tr('外觀')),
              ListTile(
                leading: const Icon(Icons.language),
                title: Text(tr('語言')),
                subtitle: Text(_langName(appSettings.langPref)),
                onTap: () => _pickLang(context),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: SegmentedButton<ThemeMode>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(value: ThemeMode.light, label: Text(tr('淺色'))),
                    ButtonSegment(value: ThemeMode.dark, label: Text(tr('深色'))),
                    ButtonSegment(value: ThemeMode.system, label: Text(tr('跟隨系統'))),
                  ],
                  selected: {appSettings.themeMode},
                  onSelectionChanged: (s) => appSettings.setThemeMode(s.first),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text(tr('主題色'), style: Theme.of(context).textTheme.bodyMedium),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    for (var i = 0; i < MidoApp.seeds.length; i++)
                      InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => appSettings.setThemeSeed(i),
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: MidoApp.seeds[i],
                            border: Border.all(
                              color: appSettings.themeSeed == i
                                  ? Theme.of(context).colorScheme.onSurface
                                  : Colors.transparent,
                              width: 3,
                            ),
                          ),
                          child: appSettings.themeSeed == i
                              ? const Icon(Icons.check, color: Colors.white)
                              : null,
                        ),
                      ),
                  ],
                ),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.dark_mode_outlined),
                title: Text(tr('深色模式使用純黑背景')),
                subtitle: Text(tr('OLED 螢幕更省電')),
                value: appSettings.pureBlack,
                onChanged: (v) => appSettings.setPureBlack(v),
              ),
              _Section(tr('安全')),
              if (_mobile && !vault.noPassword)
                SwitchListTile(
                  secondary: const Icon(Icons.fingerprint),
                  title: Text(tr('指紋 / 生物辨識解鎖')),
                  subtitle: Text(tr('主密碼仍可隨時使用')),
                  value: vault.biometricEnabled,
                  onChanged: (v) => _toggleBio(context, v),
                ),
              if (!vault.noPassword)
                ListTile(
                  leading: const Icon(Icons.timer_outlined),
                  title: Text(tr('自動鎖定')),
                  subtitle: Text(
                    _lockOptions[appSettings.lockSeconds] ??
                        tr('${appSettings.lockSeconds} 秒'),
                  ),
                  onTap: () => _pickLock(context),
                ),
              if (_mobile)
                SwitchListTile(
                  secondary: const Icon(Icons.screenshot_monitor),
                  title: Text(tr('禁止截圖與錄影')),
                  subtitle: Text(tr('同時隱藏多工畫面中的預覽')),
                  value: appSettings.secureScreen,
                  onChanged: (v) => appSettings.setSecureScreen(v),
                ),
              if (vault.noPassword) ...[
                ListTile(
                  leading: const Icon(Icons.lock_outline),
                  title: Text(tr('設定主密碼')),
                  subtitle: Text(tr('目前開啟 App 不需要密碼')),
                  onTap: () => _setMaster(context),
                ),
              ] else ...[
                ListTile(
                  leading: const Icon(Icons.password),
                  title: Text(tr('修改主密碼')),
                  onTap: () => _changePassword(context),
                ),
                ListTile(
                  leading: const Icon(Icons.lock_open_outlined),
                  title: Text(tr('移除主密碼')),
                  subtitle: Text(tr('開啟 App 不再需要輸入密碼')),
                  onTap: () => _removeMaster(context),
                ),
              ],
              ListTile(
                leading: const Icon(Icons.enhanced_encryption_outlined),
                title: Text(tr('筆記鎖定密碼')),
                subtitle: Text(
                  vault.hasLockPassword
                      ? tr('已設定（可更改或移除）。在筆記的選單裡選「鎖定」即可使用')
                      : tr('尚未設定。在筆記的選單裡選「鎖定」時會要求設定'),
                ),
                onTap: () => manageLockPassword(context),
              ),
              _Section(tr('備份與檢查')),
              ListTile(
                leading: const Icon(Icons.backup_outlined),
                title: Text(tr('備份與還原')),
                subtitle: Text(
                  appSettings.lastBackupAt == null
                      ? tr('尚未備份過；也可以在這裡匯入 Chrome / Google 密碼')
                      : tr('上次備份：${fmtDate(appSettings.lastBackupAt!, full: true)}'),
                ),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const BackupScreen()),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.cloud_sync_outlined),
                title: Text(tr('雲端同步（Google 雲端硬碟）')),
                subtitle: Text(
                  !appSettings.syncEnabled
                      ? tr('尚未開啟；可在多台裝置間自動同步')
                      : (appSettings.lastSyncAt == null
                          ? tr('已開啟')
                          : tr('上次同步：${fmtDate(appSettings.lastSyncAt!, full: true)}')),
                ),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const SyncScreen()),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.health_and_safety_outlined),
                title: Text(tr('密碼檢查')),
                subtitle: Text(tr('找出重複使用與強度偏弱的密碼')),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const SecurityCheckScreen(),
                  ),
                ),
              ),
              _Section(tr('關於')),
              FutureBuilder<PackageInfo>(
                future: PackageInfo.fromPlatform(),
                builder: (context, snap) {
                  final p = snap.data;
                  return ListTile(
                    leading: const Icon(Icons.info_outline),
                    title: Text(tr('Mido筆記')),
                    subtitle: Text(
                      p == null
                          ? tr('資料以 AES-256-GCM 加密儲存在本機，主密碼忘記就無法復原。')
                          : '${tr('目前版本 ')}${p.version} (${p.buildNumber})\n${tr('資料以 AES-256-GCM 加密儲存在本機，主密碼忘記就無法復原。')}',
                    ),
                    isThreeLine: p != null,
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.system_update),
                title: Text(tr('檢查更新')),
                subtitle: Text(tr('手動檢查 GitHub 上有沒有新版本')),
                onTap: () => _checkUpdate(context),
              ),
              ListTile(
                leading: const Icon(Icons.history),
                title: Text(tr('版本歷程')),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const ChangelogScreen()),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.open_in_new),
                title: Text(tr('GitHub 專案頁')),
                subtitle: const Text(kRepoUrl),
                onTap: () => _openUrl(kRepoUrl),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }
}
