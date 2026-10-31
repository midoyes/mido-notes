import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_state.dart';
import 'data/models.dart';
import 'data/vault_store.dart';
import 'i18n.dart';
import 'ui/common.dart';
import 'ui/editor_screen.dart';

/// 讓提醒對話框能在任何畫面上跳出來。
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// 記事提醒：App 開著而且已解鎖時，每隔一小段時間檢查有沒有到期的提醒，
/// 到了就響鈴並跳出對話框（只顯示標題，點「開啟」才看內容）。
/// 鎖定中的提醒會在下次解鎖時補上。
class ReminderService with WidgetsBindingObserver {
  static const MethodChannel _alert = MethodChannel('mido_notes/alert');

  Timer? _timer;
  bool _showing = false;
  DateTime _lastRing = DateTime.fromMillisecondsSinceEpoch(0);
  VaultStatus? _prev;

  void init() {
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => check());
    vault.addListener(_onVault);
    _prev = vault.status;
  }

  void _onVault() {
    final st = vault.status;
    final becameUnlocked = st == VaultStatus.unlocked && _prev != VaultStatus.unlocked;
    _prev = st;
    if (becameUnlocked) {
      Future<void>.delayed(const Duration(milliseconds: 800), check);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) check();
  }

  static bool isDue(Note n, DateTime now) =>
      !n.isTrashed && n.remindActive && !n.remindAt!.isAfter(now);

  Future<void> _ring() async {
    _lastRing = DateTime.now();
    try {
      if (Platform.isAndroid) {
        await _alert.invokeMethod<void>('ring');
      } else {
        for (var i = 0; i < 3; i++) {
          await SystemSound.play(SystemSoundType.alert);
          await Future<void>.delayed(const Duration(milliseconds: 600));
        }
      }
    } catch (_) {}
  }

  Future<void> check() async {
    if (vault.status != VaultStatus.unlocked) return;
    final now = DateTime.now();
    if (_showing) {
      // 還沒處理：每分鐘再響一次
      if (now.difference(_lastRing).inSeconds >= 60) unawaited(_ring());
      return;
    }
    final due = vault.notes.where((n) => isDue(n, now)).toList();
    if (due.isEmpty) return;
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return;
    due.sort((a, b) => a.remindAt!.compareTo(b.remindAt!));
    _showing = true;
    unawaited(_ring());
    try {
      await showDialog<void>(
        context: ctx,
        barrierDismissible: false,
        builder: (_) => const _ReminderDialog(),
      );
    } finally {
      _showing = false;
    }
  }

  /// 「開啟」：這次提醒視為已處理，並打開那則記事（鎖定的要先輸入鎖定密碼）。
  static Future<void> openNote(String id) async {
    final n = vault.byId(id);
    final ctx = navigatorKey.currentContext;
    if (n == null || ctx == null) return;
    vault.completeReminder(id);
    if (!await ensureNoteAccess(ctx, n)) return;
    navigatorKey.currentState?.push(
      MaterialPageRoute<void>(builder: (_) => EditorScreen(noteId: id)),
    );
  }
}

final ReminderService reminderService = ReminderService();

class _ReminderDialog extends StatefulWidget {
  const _ReminderDialog();

  @override
  State<_ReminderDialog> createState() => _ReminderDialogState();
}

class _ReminderDialogState extends State<_ReminderDialog> {
  static const Duration _snooze = Duration(minutes: 10);

  List<Note> _due() {
    final now = DateTime.now();
    final l = vault.notes.where((n) => ReminderService.isDue(n, now)).toList();
    l.sort((a, b) => a.remindAt!.compareTo(b.remindAt!));
    return l;
  }

  @override
  Widget build(BuildContext context) {
    final due = _due();
    if (due.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
    }
    final tt = Theme.of(context).textTheme;
    return AlertDialog(
      icon: const Icon(Icons.alarm),
      title: Text(tr('記事提醒')),
      content: SizedBox(
        width: 420,
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final n in due)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        n.displayTitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      Text(fmtDate(n.remindAt!, full: true), style: tt.labelSmall),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          TextButton(
                            onPressed: () {
                              Navigator.of(context).pop();
                              ReminderService.openNote(n.id);
                            },
                            child: Text(tr('開啟')),
                          ),
                          TextButton(
                            onPressed: () {
                              vault.snoozeReminder(n.id, _snooze);
                              setState(() {});
                            },
                            child: Text(tr('10 分鐘後再提醒')),
                          ),
                          FilledButton.tonal(
                            onPressed: () {
                              vault.completeReminder(n.id);
                              setState(() {});
                            },
                            child: Text(tr('完成')),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        if (due.length > 1)
          TextButton(
            onPressed: () {
              for (final n in due) {
                vault.completeReminder(n.id);
              }
              setState(() {});
            },
            child: Text(tr('全部完成')),
          ),
        TextButton(
          onPressed: () {
            for (final n in due) {
              vault.snoozeReminder(n.id, _snooze);
            }
            setState(() {});
          },
          child: Text(tr('全部稍後')),
        ),
      ],
    );
  }
}
