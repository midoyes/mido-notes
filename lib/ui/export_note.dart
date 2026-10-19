import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../i18n.dart';

/// 把一則筆記「另存新檔」：自訂檔名與副檔名，再用系統的儲存視窗選擇存放位置
/// （手機／電腦皆可）。內容以 UTF-8 純文字寫出，副檔名只決定檔案類型。
Future<void> exportNoteToFile(
  BuildContext context, {
  required String title,
  required String content,
  required bool hasSecrets,
}) async {
  final r = await showDialog<_ExportChoice>(
    context: context,
    builder: (_) => _ExportDialog(initialName: title, hasSecrets: hasSecrets),
  );
  if (r == null || !context.mounted) return;

  final bytes = Uint8List.fromList(utf8.encode(content));
  final fileName = '${r.name}.${r.ext}';
  String? savedPath;
  try {
    // 開檔案選擇視窗時不要因為「離開 App」而被自動鎖定。
    savedPath = await vault.withExternal(() async {
      final p = await FilePicker.platform.saveFile(
        dialogTitle: tr('另存新檔'),
        fileName: fileName,
        type: FileType.any,
        bytes: bytes, // Android / iOS 由系統直接寫入
      );
      if (p != null && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
        await File(p).writeAsBytes(bytes, flush: true); // 桌面版要自己寫檔
      }
      return p;
    });
  } catch (e) {
    if (context.mounted) await _msg(context, tr('儲存失敗'), '$e');
    return;
  }
  if (savedPath == null || !context.mounted) return; // 使用者取消
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(tr('已另存：$fileName'))),
  );
}

Future<void> _msg(BuildContext context, String title, String body) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('確定'))),
      ],
    ),
  );
}

class _ExportChoice {
  const _ExportChoice(this.name, this.ext);
  final String name;
  final String ext;
}

class _ExportDialog extends StatefulWidget {
  const _ExportDialog({required this.initialName, required this.hasSecrets});

  final String initialName;
  final bool hasSecrets;

  @override
  State<_ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends State<_ExportDialog> {
  static const List<String> _quick = <String>[
    'md', 'txt', 'html', 'json', 'csv', 'sh', 'py', 'log',
  ];

  late final TextEditingController _name = TextEditingController(
    text: _cleanName(widget.initialName),
  );
  final TextEditingController _ext = TextEditingController(text: 'md');

  static String _cleanName(String s) =>
      s.replaceAll(RegExp(r'[\\/:*?"<>|\r\n\t]'), '_').trim();

  static String _cleanExt(String s) =>
      s.replaceAll(RegExp(r'[^A-Za-z0-9_+-]'), '');

  @override
  void dispose() {
    _name.dispose();
    _ext.dispose();
    super.dispose();
  }

  void _submit() {
    var n = _cleanName(_name.text);
    if (n.isEmpty) n = tr('筆記');
    var e = _cleanExt(_ext.text);
    if (e.isEmpty) e = 'txt';
    Navigator.pop(context, _ExportChoice(n, e));
  }

  @override
  Widget build(BuildContext context) {
    final cur = _cleanExt(_ext.text).toLowerCase();
    return AlertDialog(
      title: Text(tr('另存新檔')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('名稱'), style: Theme.of(context).textTheme.labelLarge),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _name,
                    autofocus: true,
                    decoration: InputDecoration(hintText: tr('標題')),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 96,
                  child: TextField(
                    controller: _ext,
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _submit(),
                    decoration: const InputDecoration(prefixText: '.'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 0,
              children: [
                for (final q in _quick)
                  ChoiceChip(
                    label: Text('.$q'),
                    selected: cur == q,
                    onSelected: (_) => setState(() => _ext.text = q),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              tr('副檔名可以自己輸入。內容會以純文字（UTF-8）存出，按「選擇位置」後可挑選存放的資料夾。'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (widget.hasSecrets) ...[
              const SizedBox(height: 8),
              Text(
                tr('注意：這則筆記含有帳號密碼，存出的檔案是「未加密」的明文，請妥善保管。'),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 13,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('取消'))),
        FilledButton(onPressed: _submit, child: Text(tr('選擇位置'))),
      ],
    );
  }
}
