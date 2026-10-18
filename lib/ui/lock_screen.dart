import 'dart:async';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../data/vault_store.dart';
import 'common.dart';
import '../i18n.dart';

/// 首次使用：設定主密碼。之後：輸入主密碼或使用指紋解鎖。
class LockScreen extends StatefulWidget {
  const LockScreen({super.key});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> with WidgetsBindingObserver {
  final TextEditingController _pw = TextEditingController();
  final TextEditingController _pw2 = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  bool _bioRunning = false;
  bool _wasPaused = false;
  String? _error;
  int _fails = 0;
  DateTime? _blockedUntil;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    vault.addListener(_onVault);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final s = WidgetsBinding.instance.lifecycleState;
      if (s == null || s == AppLifecycleState.resumed) _autoBio();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    vault.removeListener(_onVault);
    _ticker?.cancel();
    _pw.dispose();
    _pw2.dispose();
    super.dispose();
  }

  void _onVault() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _wasPaused = true;
    } else if (state == AppLifecycleState.resumed && _wasPaused) {
      _wasPaused = false;
      _autoBio();
    }
  }

  Future<void> _autoBio() async {
    if (!mounted ||
        _bioRunning ||
        vault.status != VaultStatus.locked ||
        !vault.biometricEnabled) {
      return;
    }
    _bioRunning = true;
    await vault.unlockWithBiometric();
    _bioRunning = false;
  }

  int _blockedLeft() {
    final b = _blockedUntil;
    if (b == null) return 0;
    final left = b.difference(DateTime.now()).inSeconds + 1;
    return left > 0 ? left : 0;
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_blockedLeft() == 0) t.cancel();
      setState(() {});
    });
  }

  Future<void> _submit() async {
    if (_busy || _blockedLeft() > 0) return;
    final setup = vault.status == VaultStatus.needsSetup;

    if (setup) {
      if (_pw.text.length < 8) {
        setState(() => _error = tr('主密碼至少需要 8 個字元'));
        return;
      }
      if (_pw.text != _pw2.text) {
        setState(() => _error = tr('兩次輸入的密碼不一致'));
        return;
      }
      setState(() {
        _busy = true;
        _error = null;
      });
      try {
        await vault.createVault(_pw.text);
      } catch (e) {
        if (mounted) {
          setState(() {
            _busy = false;
            _error = tr('建立失敗：$e');
          });
        }
      }
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await vault.unlockWithPassword(_pw.text);
    if (!mounted || ok) return; // 成功後這個畫面會被移除
    _fails++;
    setState(() {
      _busy = false;
      _error = tr('密碼錯誤');
      if (_fails >= 3) {
        final wait = min(120, 5 * (1 << min(_fails - 3, 5)));
        _blockedUntil = DateTime.now().add(Duration(seconds: wait));
        _startTicker();
      }
    });
    _pw.clear();
  }

  Future<void> _startNoPassword() async {
    final ok = await confirmDialog(
      context,
      title: tr('不設定密碼'),
      message: tr('之後開啟 App 不需要輸入密碼，任何拿到你裝置的人都能看到沒有鎖定的筆記。'
          '你可以隨時在設定裡加上主密碼，重要筆記也可以用「鎖定」另外保護。'),
      confirmText: tr('直接使用'),
    );
    if (!ok || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await vault.createVaultNoPassword();
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = tr('建立失敗：$e');
        });
      }
    }
  }

  Future<String?> _askBackupPassword() {
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(tr('輸入備份密碼')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr('就是你匯出備份檔時設定的「備份密碼」。還原後，這組密碼也會成為這台的主密碼。'),
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: c,
              obscureText: true,
              autofocus: true,
              enableSuggestions: false,
              autocorrect: false,
              enableIMEPersonalizedLearning: false,
              keyboardType: TextInputType.visiblePassword,
              onSubmitted: (_) => Navigator.pop(ctx, c.text),
              decoration: InputDecoration(
                labelText: tr('備份密碼'),
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr('取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, c.text),
            child: Text(tr('確定')),
          ),
        ],
      ),
    );
  }

  /// 新裝置：選擇備份檔，用備份密碼當主密碼建立資料庫。
  Future<void> _restoreFromFile() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await vault.withExternal(
        () => FilePicker.platform.pickFiles(type: FileType.any, withData: true),
      );
      if (res == null || res.files.isEmpty) {
        if (mounted) setState(() => _busy = false);
        return;
      }
      final bytes = res.files.single.bytes;
      if (bytes == null) {
        if (mounted) {
          setState(() {
            _busy = false;
            _error = tr('沒辦法讀取這個檔案，請換一個位置再試一次');
          });
        }
        return;
      }
      if (!VaultStore.looksLikeBackup(bytes)) {
        if (mounted) {
          setState(() {
            _busy = false;
            _error = tr('這個檔案不是 Mido筆記 的加密備份檔');
          });
        }
        return;
      }
      if (!mounted) return;
      setState(() => _busy = false);
      final pw = await _askBackupPassword();
      if (pw == null || pw.isEmpty || !mounted) return;
      setState(() => _busy = true);
      try {
        await vault.createVaultFromBackup(bytes, pw);
      } on FormatException catch (e) {
        if (mounted) {
          setState(() {
            _busy = false;
            _error = e.message;
          });
        }
      } catch (_) {
        if (mounted) {
          setState(() {
            _busy = false;
            _error = tr('備份密碼錯誤，或備份檔已損毀');
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loading = vault.status == VaultStatus.loading;
    final setup = vault.status == VaultStatus.needsSetup;
    final left = _blockedLeft();

    Widget content;
    if (loading) {
      content = const CircularProgressIndicator();
    } else {
      content = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.lock_outline, size: 64, color: theme.colorScheme.primary),
          const SizedBox(height: 12),
          Text(
            tr('Mido筆記'),
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          Text(
            setup ? tr('第一次使用，請設定主密碼') : tr('請輸入主密碼解鎖'),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
          if (setup) ...[
            const SizedBox(height: 12),
            Text(
              tr('主密碼用來加密所有資料，忘記後無法復原，也無法還原備份。建議 12 字元以上，並混合大小寫與數字。'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
          const SizedBox(height: 20),
          TextField(
            controller: _pw,
            obscureText: _obscure,
            autofocus: !setup,
            enableSuggestions: false,
            autocorrect: false,
            enableIMEPersonalizedLearning: false,
            keyboardType: TextInputType.visiblePassword,
            textInputAction: setup ? TextInputAction.next : TextInputAction.done,
            onSubmitted: (_) {
              if (!setup) _submit();
            },
            decoration: InputDecoration(
              labelText: tr('主密碼'),
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          if (setup) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _pw2,
              obscureText: _obscure,
              enableSuggestions: false,
              autocorrect: false,
              enableIMEPersonalizedLearning: false,
              keyboardType: TextInputType.visiblePassword,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: tr('再次輸入主密碼'),
                border: OutlineInputBorder(),
              ),
            ),
          ],
          if (_error != null || left > 0) ...[
            const SizedBox(height: 12),
            Text(
              left > 0 ? tr('錯誤次數過多，請 $left 秒後再試') : _error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: (_busy || left > 0) ? null : _submit,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(setup ? tr('建立並進入') : tr('解鎖')),
            ),
          ),
          if (setup) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: _busy ? null : _startNoPassword,
              child: Text(tr('不設定密碼，直接使用')),
            ),
            const SizedBox(height: 4),
            TextButton.icon(
              onPressed: _busy ? null : _restoreFromFile,
              icon: const Icon(Icons.upload_file),
              label: Text(tr('已經有備份檔？從備份檔還原')),
            ),
          ],
          if (!setup && vault.biometricEnabled) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _busy ? null : _autoBio,
              icon: const Icon(Icons.fingerprint),
              label: Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Text(tr('使用指紋 / 生物辨識')),
              ),
            ),
          ],
        ],
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: content,
            ),
          ),
        ),
      ),
    );
  }
}
