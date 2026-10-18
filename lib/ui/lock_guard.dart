import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../data/vault_store.dart';
import 'lock_screen.dart';

/// 包在整個 App 外層：
/// - 未解鎖時，用鎖定畫面蓋住所有內容（含已開啟的編輯畫面）。
/// - 離開 App 超過設定時間、或前景閒置太久，就自動鎖定。
class LockGuard extends StatefulWidget {
  const LockGuard({super.key, required this.child});

  final Widget child;

  @override
  State<LockGuard> createState() => _LockGuardState();
}

class _LockGuardState extends State<LockGuard> with WidgetsBindingObserver {
  Timer? _idle;
  DateTime? _pausedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    vault.addListener(_onVault);
    vault.activity.addListener(_resetIdle);
    appSettings.addListener(_resetIdle);
    _resetIdle();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    vault.removeListener(_onVault);
    vault.activity.removeListener(_resetIdle);
    appSettings.removeListener(_resetIdle);
    _idle?.cancel();
    super.dispose();
  }

  void _onVault() {
    if (vault.status != VaultStatus.unlocked) {
      FocusManager.instance.primaryFocus?.unfocus();
    }
    _resetIdle();
    if (mounted) setState(() {});
  }

  void _resetIdle() {
    _idle?.cancel();
    if (vault.status != VaultStatus.unlocked) return;
    final seconds = max(appSettings.lockSeconds, 60);
    _idle = Timer(Duration(seconds: seconds), () {
      if (!vault.externalBusy) vault.lock();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
        _pausedAt = DateTime.now();
        if (appSettings.lockSeconds == 0 && !vault.externalBusy) {
          vault.lock();
        }
        break;
      case AppLifecycleState.resumed:
        final p = _pausedAt;
        _pausedAt = null;
        if (p != null &&
            vault.status == VaultStatus.unlocked &&
            !vault.externalBusy) {
          final away = DateTime.now().difference(p).inSeconds;
          if (away >= appSettings.lockSeconds) vault.lock();
        }
        _resetIdle();
        break;
      default:
        break;
    }
  }

  /// 鎖定時按返回鍵：不要退回上一頁，直接把 App 放到背景。
  @override
  Future<bool> didPopRoute() async {
    if (vault.status != VaultStatus.unlocked) {
      SystemNavigator.pop();
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final locked = vault.status != VaultStatus.unlocked;
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _resetIdle(),
      child: Stack(
        children: [
          ExcludeSemantics(
            excluding: locked,
            child: ExcludeFocus(
              excluding: locked,
              child: IgnorePointer(ignoring: locked, child: widget.child),
            ),
          ),
          if (locked)
            Positioned.fill(
              // 這一層在 MaterialApp 的 Navigator 外面，所以鎖定畫面要自己帶一個
              // Navigator，否則 showDialog 找不到 Navigator 而什麼都不會發生
              // （例如按「不設定密碼」沒有反應）。
              // 一定要用 HeroControllerScope.none：不然這個 Navigator 會搶走
              // MaterialApp 共用的 HeroController，解鎖後主 Navigator 再開啟
              // 任何頁面（筆記、設定）都會出錯。
              child: HeroControllerScope.none(
                child: Navigator(
                  onGenerateRoute: (_) => MaterialPageRoute<void>(
                    builder: (_) => const LockScreen(),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
