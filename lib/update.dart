import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'i18n.dart';

/// 公開的 GitHub 專案。
const String kRepo = 'midoyes/mido-notes';
const String kRepoUrl = 'https://github.com/$kRepo';

class ReleaseInfo {
  ReleaseInfo({
    required this.tag,
    required this.body,
    required this.pageUrl,
    required this.assetUrl,
    required this.publishedAt,
  });

  final String tag;
  final String body;
  final String pageUrl;
  final String? assetUrl; // 這個平台適用的安裝檔（apk 或 zip）
  final String publishedAt;

  String get version => tag.startsWith('v') ? tag.substring(1) : tag;
}

class UpdateException implements Exception {
  UpdateException(this.message);

  final String message;

  @override
  String toString() => message;
}

List<int> _parts(String v) =>
    RegExp(r'\d+').allMatches(v).map((m) => int.parse(m.group(0)!)).toList();

/// a 比 b 新回傳正數，相同為 0，較舊為負數。
int compareVersion(String a, String b) {
  final x = _parts(a);
  final y = _parts(b);
  for (var i = 0; i < 4; i++) {
    final p = i < x.length ? x[i] : 0;
    final q = i < y.length ? y[i] : 0;
    if (p != q) return p.compareTo(q);
  }
  return 0;
}

/// 到 GitHub 查最新的 Release。只在使用者按下「檢查更新」時執行，不會自動連線。
Future<ReleaseInfo> fetchLatestRelease() async {
  final uri = Uri.parse('https://api.github.com/repos/$kRepo/releases/latest');
  http.Response r;
  try {
    r = await http.get(uri, headers: <String, String>{
      'Accept': 'application/vnd.github+json',
      'User-Agent': 'mido-notes-app',
    }).timeout(const Duration(seconds: 15));
  } on TimeoutException {
    throw UpdateException(tr('連線逾時，請確認網路後再試'));
  } on SocketException {
    throw UpdateException(tr('無法連線到 GitHub，請確認網路'));
  } catch (e) {
    throw UpdateException('$e');
  }
  if (r.statusCode == 404) {
    throw UpdateException(tr('找不到已發布的版本'));
  }
  if (r.statusCode == 403) {
    throw UpdateException(tr('GitHub 暫時拒絕請求（可能次數太多），請稍後再試'));
  }
  if (r.statusCode != 200) {
    throw UpdateException('GitHub ${r.statusCode}');
  }
  final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  String? asset;
  for (final a in (j['assets'] as List?) ?? const <dynamic>[]) {
    final m = a as Map<String, dynamic>;
    final name = ((m['name'] as String?) ?? '').toLowerCase();
    final url = m['browser_download_url'] as String?;
    if (url == null) continue;
    if (Platform.isAndroid && name.endsWith('.apk')) asset = url;
    if (Platform.isWindows && name.endsWith('.zip')) asset = url;
  }
  return ReleaseInfo(
    tag: (j['tag_name'] as String?) ?? '',
    body: (j['body'] as String?) ?? '',
    pageUrl: (j['html_url'] as String?) ?? '$kRepoUrl/releases',
    assetUrl: asset,
    publishedAt: ((j['published_at'] as String?) ?? '').split('T').first,
  );
}
