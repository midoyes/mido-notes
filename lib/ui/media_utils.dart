import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../app_state.dart';
import '../data/vault_store.dart';
import '../i18n.dart';

/// 影片、錄音單一檔案的大小上限（加密備份會把所有附件一起打包，太大會讓備份失敗）。
const int kMaxMediaBytes = 30 * 1024 * 1024;

bool isVideoId(String id) => id.startsWith('vid-');
bool isAudioId(String id) => id.startsWith('aud-');
bool isMediaId(String id) => VaultStore.isMediaId(id);

String mediaExt(String id) {
  final p = id.split('-');
  return p.length >= 3 ? p[1] : (isVideoId(id) ? 'mp4' : 'm4a');
}

/// 取檔案副檔名（小寫、只留英數字），失敗時回傳 [fallback]。
String extOfPath(String path, String fallback) {
  final i = path.lastIndexOf('.');
  if (i < 0 || i >= path.length - 1) return fallback;
  final e = path.substring(i + 1).toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  return (e.isEmpty || e.length > 5) ? fallback : e;
}

String fmtBytes(int b) {
  if (b >= 1024 * 1024) return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
  return '${(b / 1024).toStringAsFixed(0)} KB';
}

Future<Directory> _tempDir() async {
  final t = await getTemporaryDirectory();
  final d = Directory('${t.path}/mido_media');
  if (!await d.exists()) await d.create(recursive: true);
  return d;
}

/// 清掉解密後留下的暫存檔（啟動時、每次開啟前都會呼叫）。
Future<void> cleanMediaTemp() async {
  try {
    final t = await getTemporaryDirectory();
    final d = Directory('${t.path}/mido_media');
    if (await d.exists()) await d.delete(recursive: true);
  } catch (_) {}
}

/// 解密成暫存檔後交給系統的播放器開啟。
Future<void> openMedia(BuildContext context, String id) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final bytes = await vault.loadImage(id);
    if (bytes == null) {
      messenger.showSnackBar(SnackBar(content: Text(tr('讀取失敗'))));
      return;
    }
    await cleanMediaTemp();
    final dir = await _tempDir();
    final f = File('${dir.path}/${id.substring(id.length - 12)}.${mediaExt(id)}');
    await f.writeAsBytes(bytes, flush: true);
    final r = await vault.withExternal(() => OpenFilex.open(f.path));
    if (r.type != ResultType.done) {
      messenger.showSnackBar(SnackBar(content: Text(tr('找不到可以開啟的播放程式：${r.message}'))));
    }
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(tr('開啟失敗：$e'))));
  }
}
