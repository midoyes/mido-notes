import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../data/models.dart';
import '../i18n.dart';

/// 筆記顏色調色盤（1~8），0 代表不上色。
const List<Color> kNoteColorBase = <Color>[
  Color(0xFFE53935), // 紅
  Color(0xFFFB8C00), // 橘
  Color(0xFFFDD835), // 黃
  Color(0xFF43A047), // 綠
  Color(0xFF00ACC1), // 青
  Color(0xFF1E88E5), // 藍
  Color(0xFF8E24AA), // 紫
  Color(0xFFEC407A), // 粉
];
List<String> get kNoteColorNames => <String>[
  tr('紅'), tr('橘'), tr('黃'), tr('綠'), tr('青'), tr('藍'), tr('紫'), tr('粉'),
];

Color? noteColorOf(int c) =>
    (c >= 1 && c <= kNoteColorBase.length) ? kNoteColorBase[c - 1] : null;

Future<int?> pickNoteColor(BuildContext context, int current) {
  return showDialog<int>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(tr('筆記顏色')),
      content: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (var i = 0; i <= kNoteColorBase.length; i++)
            Tooltip(
              message: i == 0 ? tr('無') : kNoteColorNames[i - 1],
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => Navigator.pop(ctx, i),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i == 0 ? null : kNoteColorBase[i - 1],
                    border: Border.all(
                      color: current == i
                          ? Theme.of(ctx).colorScheme.onSurface
                          : Theme.of(ctx).colorScheme.outlineVariant,
                      width: current == i ? 3 : 1,
                    ),
                  ),
                  child: i == 0
                      ? const Icon(Icons.format_color_reset, size: 20)
                      : (current == i
                          ? const Icon(Icons.check, color: Colors.white)
                          : null),
                ),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('取消'))),
      ],
    ),
  );
}

String fmtDate(DateTime d, {bool full = false}) {
  String two(int n) => n.toString().padLeft(2, '0');
  final now = DateTime.now();
  if (full) {
    return '${d.year}/${two(d.month)}/${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }
  if (d.year == now.year && d.month == now.month && d.day == now.day) {
    return '${two(d.hour)}:${two(d.minute)}';
  }
  if (d.year == now.year) return '${two(d.month)}/${two(d.day)}';
  return '${d.year}/${two(d.month)}/${two(d.day)}';
}

Timer? _clipTimer;

/// 複製文字，並在 30 秒後嘗試清除剪貼簿。
Future<void> copyWithClear(
  BuildContext context,
  String text,
  String label,
) async {
  if (text.isEmpty) return;
  await Clipboard.setData(ClipboardData(text: text));
  _clipTimer?.cancel();
  _clipTimer = Timer(const Duration(seconds: 30), () async {
    try {
      final cur = await Clipboard.getData(Clipboard.kTextPlain);
      if (cur == null || cur.text == text) {
        await Clipboard.setData(const ClipboardData(text: ''));
      }
    } catch (_) {}
  });
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(tr('已複製$label，30 秒後自動清除剪貼簿'))));
}

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String? confirmText,
  bool danger = false,
}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(tr('取消')),
        ),
        FilledButton(
          style: danger
              ? FilledButton.styleFrom(
                  backgroundColor: Theme.of(ctx).colorScheme.error,
                  foregroundColor: Theme.of(ctx).colorScheme.onError,
                )
              : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmText ?? tr('確定')),
        ),
      ],
    ),
  );
  return r ?? false;
}

/// 選擇資料夾。回傳：資料夾 id；'' 代表「不分類」；null 代表取消。
Future<String?> pickFolder(BuildContext context, {String? current}) {
  return showDialog<String>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: Text(tr('移到資料夾')),
      children: [
        ListTile(
          leading: Icon(
            current == null
                ? Icons.radio_button_checked
                : Icons.radio_button_unchecked,
          ),
          title: Text(tr('不分類')),
          onTap: () => Navigator.pop(ctx, ''),
        ),
        for (final f in vault.folders)
          ListTile(
            leading: Icon(
              current == f.id
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
            ),
            title: Text(f.name),
            onTap: () => Navigator.pop(ctx, f.id),
          ),
        if (vault.folders.isEmpty)
          Padding(
            padding: EdgeInsets.fromLTRB(24, 8, 24, 8),
            child: Text(tr('還沒有資料夾，可在首頁最上方的列新增。')),
          ),
      ],
    ),
  );
}

String generatePassword({
  int length = 16,
  bool upper = true,
  bool lower = true,
  bool digits = true,
  bool symbols = true,
}) {
  final rng = Random.secure();
  final sets = <String>[
    if (upper) 'ABCDEFGHJKLMNPQRSTUVWXYZ',
    if (lower) 'abcdefghijkmnopqrstuvwxyz',
    if (digits) '23456789',
    if (symbols) '!@#\$%^&*()-_=+[]{}?',
  ];
  if (sets.isEmpty) sets.add('abcdefghijkmnopqrstuvwxyz');
  final all = sets.join();
  final chars = <String>[for (final s in sets) s[rng.nextInt(s.length)]];
  while (chars.length < length) {
    chars.add(all[rng.nextInt(all.length)]);
  }
  chars.shuffle(rng);
  return chars.join();
}

/// 密碼產生器對話框，回傳使用者選用的密碼。
Future<String?> showPasswordGenerator(BuildContext context) {
  var length = 16;
  var upper = true;
  var lower = true;
  var digits = true;
  var symbols = true;
  var value = generatePassword();

  return showDialog<String>(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setState) {
          void regen() => setState(() {
                value = generatePassword(
                  length: length,
                  upper: upper,
                  lower: lower,
                  digits: digits,
                  symbols: symbols,
                );
              });

          return AlertDialog(
            title: Text(tr('產生密碼')),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SelectableText(
                      value,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 18,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(tr('長度：$length')),
                  Slider(
                    value: length.toDouble(),
                    min: 8,
                    max: 40,
                    divisions: 32,
                    label: '$length',
                    onChanged: (v) {
                      length = v.round();
                      regen();
                    },
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      FilterChip(
                        label: Text(tr('大寫')),
                        selected: upper,
                        onSelected: (v) {
                          upper = v;
                          regen();
                        },
                      ),
                      FilterChip(
                        label: Text(tr('小寫')),
                        selected: lower,
                        onSelected: (v) {
                          lower = v;
                          regen();
                        },
                      ),
                      FilterChip(
                        label: Text(tr('數字')),
                        selected: digits,
                        onSelected: (v) {
                          digits = v;
                          regen();
                        },
                      ),
                      FilterChip(
                        label: Text(tr('符號')),
                        selected: symbols,
                        onSelected: (v) {
                          symbols = v;
                          regen();
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: regen, child: Text(tr('重新產生'))),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(tr('取消')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, value),
                child: Text(tr('使用')),
              ),
            ],
          );
        },
      );
    },
  );
}


Future<String?> _askPw(
  BuildContext context, {
  required String title,
  String? message,
  bool confirm = false,
  String? label,
}) {
  final a = TextEditingController();
  final b = TextEditingController();
  String? error;
  return showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) {
        void submit() {
          if (confirm) {
            if (a.text.length < 4) {
              setS(() => error = tr('至少需要 4 個字元'));
              return;
            }
            if (a.text != b.text) {
              setS(() => error = tr('兩次輸入不一致'));
              return;
            }
          } else if (a.text.isEmpty) {
            return;
          }
          Navigator.pop(ctx, a.text);
        }

        Widget field(TextEditingController c, String l, {bool last = false}) =>
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: TextField(
                controller: c,
                obscureText: true,
                autofocus: c == a,
                enableSuggestions: false,
                autocorrect: false,
                enableIMEPersonalizedLearning: false,
                keyboardType: TextInputType.visiblePassword,
                textInputAction: last ? TextInputAction.done : TextInputAction.next,
                onSubmitted: (_) {
                  if (last) submit();
                },
                decoration: InputDecoration(
                  labelText: l,
                  border: const OutlineInputBorder(),
                ),
              ),
            );

        return AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (message != null) Text(message),
                field(a, label ?? tr('鎖定密碼'), last: !confirm),
                if (confirm) field(b, tr('再次輸入'), last: true),
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
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('取消'))),
            FilledButton(onPressed: submit, child: Text(tr('確定'))),
          ],
        );
      },
    ),
  );
}

/// 輸入並驗證「鎖定密碼」。通過回傳 true；取消回傳 false。
Future<bool> askLockPassword(
  BuildContext context, {
  String? title,
  String? message,
}) async {
  var tries = 0;
  while (true) {
    final pw = await _askPw(
      context,
      title: title ?? tr('輸入鎖定密碼'),
      message: tries == 0 ? message : tr('密碼不正確，請再試一次。'),
    );
    if (pw == null || !context.mounted) return false;
    if (await vault.verifyLockPassword(pw)) return true;
    tries++;
    if (tries >= 3) {
      await Future<void>.delayed(Duration(seconds: min(10, tries * 2)));
    }
    if (!context.mounted) return false;
  }
}

/// 如果還沒設定鎖定密碼，先請使用者設定。已經有就直接回傳 true。
Future<bool> ensureLockPassword(BuildContext context) async {
  if (vault.hasLockPassword) return true;
  final pw = await _askPw(
    context,
    title: tr('設定鎖定密碼'),
    message: tr('之後開啟被鎖定的筆記都要輸入這組密碼。它可以和登入主密碼不同。忘記就無法開啟被鎖定的筆記，請記好。'),
    confirm: true,
  );
  if (pw == null) return false;
  await vault.setLockPassword(pw);
  return true;
}

/// 開啟或操作鎖定筆記前的檢查：沒鎖定直接通過，有鎖定就要輸入鎖定密碼。
Future<bool> ensureNoteAccess(BuildContext context, Note n) async {
  if (!n.locked) return true;
  if (!vault.hasLockPassword) return true; // 防呆：沒有密碼就不擋
  return askLockPassword(context);
}

/// 設定鎖定密碼的完整流程（設定／更改／移除），用在設定頁。
Future<void> manageLockPassword(BuildContext context) async {
  if (!vault.hasLockPassword) {
    await ensureLockPassword(context);
    return;
  }
  final r = await showDialog<String>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: Text(tr('筆記鎖定密碼')),
      children: [
        ListTile(
          leading: const Icon(Icons.edit_outlined),
          title: Text(tr('更改鎖定密碼')),
          onTap: () => Navigator.pop(ctx, 'change'),
        ),
        ListTile(
          leading: const Icon(Icons.lock_open),
          title: Text(tr('移除鎖定密碼（同時解除所有筆記的鎖定）')),
          onTap: () => Navigator.pop(ctx, 'remove'),
        ),
      ],
    ),
  );
  if (r == null || !context.mounted) return;
  if (r == 'change') {
    final old = await _askPw(context, title: tr('輸入目前的鎖定密碼'));
    if (old == null || !context.mounted) return;
    if (!await vault.verifyLockPassword(old)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr('目前的鎖定密碼不正確'))),
        );
      }
      return;
    }
    if (!context.mounted) return;
    final nw = await _askPw(context, title: tr('設定新的鎖定密碼'), confirm: true);
    if (nw == null) return;
    await vault.changeLockPassword(old, nw);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('鎖定密碼已更新（如果有多台裝置同步，其他裝置也要改成一樣的）'))),
      );
    }
  } else {
    final pw = await _askPw(
      context,
      title: tr('輸入鎖定密碼以移除'),
      message: tr('移除後，所有被鎖定的筆記都會解除鎖定。'),
    );
    if (pw == null || !context.mounted) return;
    final done = await vault.removeLockPassword(pw);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(done ? tr('已移除鎖定密碼，所有筆記都解除鎖定') : tr('密碼不正確'))),
      );
    }
  }
}

/// 切換單一筆記的鎖定狀態（首頁選單用）。
Future<void> toggleNoteLock(BuildContext context, Note n) async {
  if (!n.locked) {
    if (!await ensureLockPassword(context)) return;
    vault.setNoteLocked(n.id, true);
  } else {
    if (!await askLockPassword(context, title: tr('輸入鎖定密碼以解除鎖定'))) return;
    vault.setNoteLocked(n.id, false);
  }
}
