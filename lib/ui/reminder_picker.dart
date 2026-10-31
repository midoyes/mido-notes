import 'package:flutter/material.dart';

import '../i18n.dart';
import 'common.dart';

/// 選擇提醒時間的結果：[clear] 為 true 代表清除提醒。
class ReminderResult {
  const ReminderResult.set(DateTime this.at) : clear = false;
  const ReminderResult.clear()
      : at = null,
        clear = true;

  final DateTime? at;
  final bool clear;
}

Future<ReminderResult?> pickReminder(
  BuildContext context, {
  DateTime? current,
}) async {
  final now = DateTime.now();
  DateTime at(DateTime d, int h, int m) => DateTime(d.year, d.month, d.day, h, m);

  Widget opt(BuildContext ctx, String v, IconData icon, String label) =>
      SimpleDialogOption(
        onPressed: () => Navigator.pop(ctx, v),
        child: Row(
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: 12),
            Expanded(child: Text(label)),
          ],
        ),
      );

  final choice = await showDialog<String>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: Text(tr('設定提醒')),
      children: [
        if (current != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(tr('目前：') + fmtDate(current, full: true)),
          ),
        opt(ctx, '1h', Icons.timer_outlined, tr('1 小時後')),
        if (now.isBefore(at(now, 20, 0)))
          opt(ctx, 'tonight', Icons.nights_stay_outlined, tr('今天 20:00')),
        opt(ctx, 'tomorrow', Icons.wb_sunny_outlined, tr('明天 09:00')),
        opt(ctx, 'custom', Icons.edit_calendar_outlined, tr('自訂日期與時間…')),
        if (current != null)
          opt(ctx, 'clear', Icons.alarm_off_outlined, tr('清除提醒')),
      ],
    ),
  );
  if (choice == null) return null;
  switch (choice) {
    case '1h':
      return ReminderResult.set(now.add(const Duration(hours: 1)));
    case 'tonight':
      return ReminderResult.set(at(now, 20, 0));
    case 'tomorrow':
      return ReminderResult.set(
        at(now.add(const Duration(days: 1)), 9, 0),
      );
    case 'clear':
      return const ReminderResult.clear();
  }
  if (!context.mounted) return null;
  final base = (current != null && current.isAfter(now)) ? current : now;
  final d = await showDatePicker(
    context: context,
    initialDate: base,
    firstDate: DateTime(now.year, now.month, now.day),
    lastDate: DateTime(now.year + 5, 12, 31),
  );
  if (d == null || !context.mounted) return null;
  final t = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(base),
  );
  if (t == null) return null;
  return ReminderResult.set(DateTime(d.year, d.month, d.day, t.hour, t.minute));
}
