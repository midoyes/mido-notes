import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'google_auth.dart';
import 'google_config.dart';

class DriveFile {
  DriveFile(this.id, this.md5, this.modified);
  final String id;
  final String? md5;
  final String? modified;
}

class DriveException implements Exception {
  DriveException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Google 雲端硬碟 appDataFolder（App 專用隱藏資料夾）裡的單一同步檔。
class DriveSync {
  DriveSync(this.auth);
  final GoogleAuth auth;

  static const Duration _net = Duration(seconds: 60);
  static const String _fields = 'id,md5Checksum,modifiedTime';

  Future<Map<String, String>> _headers() async =>
      {'Authorization': 'Bearer ${await auth.accessToken()}'};

  void _check(http.Response r) {
    if (r.statusCode >= 200 && r.statusCode < 300) return;
    if (r.statusCode == 401) auth.invalidate();
    var msg = r.body;
    try {
      final j = jsonDecode(r.body);
      msg = (j['error']?['message'] ?? r.body).toString();
    } catch (_) {}
    if (msg.length > 200) msg = msg.substring(0, 200);
    throw DriveException('Google Drive ${r.statusCode}: $msg');
  }

  DriveFile _file(Map<String, dynamic> j) => DriveFile(
        j['id'] as String,
        j['md5Checksum'] as String?,
        j['modifiedTime'] as String?,
      );

  Future<DriveFile?> find() async {
    final r = await http
        .get(
          Uri.https('www.googleapis.com', '/drive/v3/files', {
            'spaces': 'appDataFolder',
            'q': "name = '$kSyncFileName' and trashed = false",
            'fields': 'files($_fields)',
            'orderBy': 'modifiedTime desc',
            'pageSize': '1',
          }),
          headers: await _headers(),
        )
        .timeout(_net);
    _check(r);
    final list = (jsonDecode(r.body)['files'] as List?) ?? const <dynamic>[];
    if (list.isEmpty) return null;
    return _file(list.first as Map<String, dynamic>);
  }

  Future<Uint8List> download(String id) async {
    final r = await http
        .get(
          Uri.https('www.googleapis.com', '/drive/v3/files/$id', {'alt': 'media'}),
          headers: await _headers(),
        )
        .timeout(const Duration(minutes: 5));
    _check(r);
    return r.bodyBytes;
  }

  /// [id] 有值就更新那個檔，否則在 appDataFolder 建立新檔。
  Future<DriveFile> upload(Uint8List data, {String? id}) async {
    final h = await _headers();
    http.Response r;
    if (id != null) {
      r = await http
          .patch(
            Uri.https('www.googleapis.com', '/upload/drive/v3/files/$id', {
              'uploadType': 'media',
              'fields': _fields,
            }),
            headers: {...h, 'Content-Type': 'application/octet-stream'},
            body: data,
          )
          .timeout(const Duration(minutes: 5));
    } else {
      const boundary = 'mido_sync_boundary_7f3a';
      final meta = jsonEncode({
        'name': kSyncFileName,
        'parents': ['appDataFolder'],
      });
      final body = BytesBuilder()
        ..add(utf8.encode('--$boundary\r\n'
            'Content-Type: application/json; charset=UTF-8\r\n\r\n'
            '$meta\r\n'
            '--$boundary\r\n'
            'Content-Type: application/octet-stream\r\n\r\n'))
        ..add(data)
        ..add(utf8.encode('\r\n--$boundary--'));
      r = await http
          .post(
            Uri.https('www.googleapis.com', '/upload/drive/v3/files', {
              'uploadType': 'multipart',
              'fields': _fields,
            }),
            headers: {...h, 'Content-Type': 'multipart/related; boundary=$boundary'},
            body: body.toBytes(),
          )
          .timeout(const Duration(minutes: 5));
    }
    _check(r);
    return _file(jsonDecode(r.body) as Map<String, dynamic>);
  }

  Future<void> delete(String id) async {
    final r = await http
        .delete(
          Uri.https('www.googleapis.com', '/drive/v3/files/$id'),
          headers: await _headers(),
        )
        .timeout(_net);
    if (r.statusCode == 404) return;
    _check(r);
  }
}
