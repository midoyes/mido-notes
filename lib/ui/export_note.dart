import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../i18n.dart';
import 'media_utils.dart';
import 'zip_writer.dart';

/// 用系統的儲存視窗把 [bytes] 存成檔案（手機、電腦皆可）。成功回傳 true，取消回傳 false。
Future<bool> saveBytesAs(BuildContext context, String fileName, Uint8List bytes) async {
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
    return false;
  }
  if (savedPath == null || !context.mounted) return false; // 使用者取消
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(tr('已另存：$fileName'))),
  );
  return true;
}

/// 依檔案開頭的特徵判斷圖片副檔名。
String imageExt(Uint8List b) {
  if (b.length > 8 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) return 'png';
  if (b.length > 3 && b[0] == 0xFF && b[1] == 0xD8) return 'jpg';
  if (b.length > 4 && b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46) return 'gif';
  if (b.length > 12 && b[0] == 0x52 && b[1] == 0x49 && b[8] == 0x57 && b[9] == 0x45) return 'webp';
  return 'png';
}

String _safe(String s) {
  final t = s.replaceAll(RegExp(r'[\\/:*?"<>|\r\n\t]'), '_').trim();
  return t.isEmpty ? tr('筆記') : t;
}

/// 單一附件另存成原本的格式（圖片 png/jpg、影片、錄音）。
Future<void> saveAttachmentAs(BuildContext context, String id, {String? baseName}) async {
  final bytes = await vault.loadImage(id);
  if (bytes == null) {
    if (context.mounted) await _msg(context, tr('儲存失敗'), tr('讀取失敗'));
    return;
  }
  final ext = isMediaId(id) ? mediaExt(id) : imageExt(bytes);
  final base = _safe(baseName ?? (isVideoId(id) ? tr('影片') : isAudioId(id) ? tr('錄音') : tr('圖片')));
  if (!context.mounted) return;
  await saveBytesAs(context, '$base.$ext', bytes);
}

/// 把一則筆記「另存新檔」：自訂檔名與副檔名存成文字檔，或連同附件打包成 .zip，
/// 再用系統的儲存視窗選擇存放位置。
Future<void> exportNoteToFile(
  BuildContext context, {
  required String title,
  required String content,
  required bool hasSecrets,
  List<String> attachmentIds = const <String>[],
}) async {
  final r = await showDialog<_ExportChoice>(
    context: context,
    builder: (_) => _ExportDialog(
      initialName: title,
      hasSecrets: hasSecrets,
      attachmentCount: attachmentIds.length,
    ),
  );
  if (r == null || !context.mounted) return;

  if (!r.zip) {
    await saveBytesAs(
      context,
      '${r.name}.${r.ext}',
      Uint8List.fromList(utf8.encode(content)),
    );
    return;
  }

  // 打包成 zip：文字檔 + attachments 資料夾
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3)),
            const SizedBox(width: 16),
            Expanded(child: Text(tr('正在打包…'))),
          ],
        ),
      ),
    ),
  );
  Uint8List? zip;
  String? err;
  try {
    final w = ZipWriter();
    w.add('${r.name}.md', Uint8List.fromList(utf8.encode(content)));
    var img = 0, vid = 0, aud = 0;
    for (final id in attachmentIds) {
      final b = await vault.loadImage(id);
      if (b == null) continue;
      if (isVideoId(id)) {
        vid++;
        w.add('attachments/${tr('影片')}-$vid.${mediaExt(id)}', b);
      } else if (isAudioId(id)) {
        aud++;
        w.add('attachments/${tr('錄音')}-$aud.${mediaExt(id)}', b);
      } else {
        img++;
        w.add('attachments/${tr('圖片')}-$img.${imageExt(b)}', b);
      }
    }
    zip = w.build();
  } catch (e) {
    err = '$e';
  }
  if (context.mounted) Navigator.of(context, rootNavigator: true).pop(); // 關掉「正在打包」
  if (!context.mounted) return;
  if (zip == null) {
    await _msg(context, tr('打包失敗'), err ?? '');
    return;
  }
  await saveBytesAs(context, '${r.name}.zip', zip);
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
  const _ExportChoice(this.name, this.ext, {this.zip = false});
  final String name;
  final String ext;
  final bool zip;
}

class _ExportDialog extends StatefulWidget {
  const _ExportDialog({
    required this.initialName,
    required this.hasSecrets,
    required this.attachmentCount,
  });

  final String initialName;
  final bool hasSecrets;
  final int attachmentCount;

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

  void _submit({bool zip = false}) {
    var n = _cleanName(_name.text);
    if (n.isEmpty) n = tr('筆記');
    var e = _cleanExt(_ext.text);
    if (e.isEmpty) e = 'txt';
    Navigator.pop(context, _ExportChoice(n, e, zip: zip));
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
              tr('副檔名可以自己輸入。內容會以純文字（UTF-8）存出，按「存文字檔」後可挑選存放的資料夾。'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            const Divider(),
            Text(tr('或：整則筆記打包'), style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              widget.attachmentCount == 0
                  ? tr('把筆記存成 .zip（這則筆記沒有附件）。')
                  : tr('把筆記文字（.md）與 ${widget.attachmentCount} 個附件一起打包成 .zip，附件放在 attachments 資料夾。'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => _submit(zip: true),
              icon: const Icon(Icons.folder_zip_outlined),
              label: Text(tr('存成 .zip')),
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
        FilledButton(onPressed: () => _submit(), child: Text(tr('存文字檔'))),
      ],
    );
  }
}
