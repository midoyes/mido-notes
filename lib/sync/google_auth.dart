import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../app_state.dart';
import '../i18n.dart';
import 'google_config.dart';

class GoogleAuthException implements Exception {
  GoogleAuthException(this.message, {this.needLogin = false});
  final String message;
  final bool needLogin; // true = 要重新登入
  @override
  String toString() => message;
}

/// Google 登入（OAuth 2.0 授權碼 + PKCE，用系統瀏覽器與本機迴路位址接回結果）。
/// refresh token 存在系統安全儲存區。
class GoogleAuth {
  static const FlutterSecureStorage _store = FlutterSecureStorage();
  static const String _rtKey = 'mido_google_refresh';
  static const Duration _net = Duration(seconds: 30);

  String? _access;
  DateTime _exp = DateTime.fromMillisecondsSinceEpoch(0);

  Future<bool> isSignedIn() async {
    try {
      return (await _store.read(key: _rtKey)) != null;
    } catch (_) {
      return false;
    }
  }

  static String _rand(int n) {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    final r = Random.secure();
    return String.fromCharCodes(
      List<int>.generate(n, (_) => chars.codeUnitAt(r.nextInt(chars.length))),
    );
  }

  Future<void> signIn() async {
    if (kGoogleClientSecret.isEmpty) {
      throw GoogleAuthException(tr('這個版本還沒有設定 Google 登入資訊。'));
    }
    final verifier = _rand(64);
    final hash = await Sha256().hash(utf8.encode(verifier));
    final challenge = base64UrlEncode(hash.bytes).replaceAll('=', '');
    final state = _rand(24);

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final redirect = 'http://127.0.0.1:${server.port}';
    try {
      final url = Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
        'client_id': kGoogleClientId,
        'redirect_uri': redirect,
        'response_type': 'code',
        'scope': kGoogleScope,
        'code_challenge': challenge,
        'code_challenge_method': 'S256',
        'access_type': 'offline',
        'prompt': 'consent',
        'state': state,
      });
      final code = await vault.withExternal(() async {
        final ok = await launchUrl(url, mode: LaunchMode.externalApplication);
        if (!ok) throw GoogleAuthException(tr('無法開啟瀏覽器。'));
        return _waitForCode(server, state);
      });
      await _exchange(code, verifier, redirect);
    } finally {
      await server.close(force: true);
    }
  }

  Future<String> _waitForCode(HttpServer server, String state) async {
    try {
      await for (final req in server.timeout(const Duration(minutes: 5))) {
        final q = req.uri.queryParameters;
        if (q.containsKey('code') || q.containsKey('error')) {
          final ok = q['code'] != null && q['state'] == state;
          req.response
            ..statusCode = 200
            ..headers.contentType = ContentType.html
            ..write(
              '<!doctype html><html><head><meta charset="utf-8">'
              '<meta name="viewport" content="width=device-width,initial-scale=1">'
              '<title>Mido</title></head>'
              '<body style="font-family:sans-serif;text-align:center;margin-top:20vh">'
              '<h2>${ok ? tr('登入完成') : tr('登入失敗')}</h2>'
              '<p>${ok ? tr('請回到 Mido筆記。這個分頁可以關閉。') : tr('請回到 Mido筆記重試。')}</p>'
              '</body></html>',
            );
          await req.response.close();
          if (!ok) {
            throw GoogleAuthException(
              tr('Google 登入沒有完成：') + (q['error'] ?? 'state'),
            );
          }
          return q['code']!;
        }
        req.response.statusCode = 404;
        await req.response.close();
      }
    } on TimeoutException {
      throw GoogleAuthException(tr('等待登入逾時，請再試一次。'));
    }
    throw GoogleAuthException(tr('登入被中斷。'));
  }

  Future<void> _exchange(String code, String verifier, String redirect) async {
    final r = await http.post(
      Uri.parse('https://oauth2.googleapis.com/token'),
      body: {
        'code': code,
        'client_id': kGoogleClientId,
        'client_secret': kGoogleClientSecret,
        'code_verifier': verifier,
        'grant_type': 'authorization_code',
        'redirect_uri': redirect,
      },
    ).timeout(_net);
    final j = _json(r.body);
    if (r.statusCode != 200) {
      throw GoogleAuthException(
        tr('取得授權失敗：') + '${j['error_description'] ?? j['error'] ?? r.statusCode}',
      );
    }
    final rt = j['refresh_token'] as String?;
    if (rt == null) {
      throw GoogleAuthException(tr('Google 沒有回傳長期授權，請再登入一次。'));
    }
    await _store.write(key: _rtKey, value: rt);
    _setAccess(j);
  }

  void _setAccess(Map<String, dynamic> j) {
    _access = j['access_token'] as String?;
    final secs = (j['expires_in'] as num?)?.toInt() ?? 3000;
    _exp = DateTime.now().add(Duration(seconds: secs - 60));
  }

  Map<String, dynamic> _json(String body) {
    try {
      final v = jsonDecode(body);
      if (v is Map<String, dynamic>) return v;
    } catch (_) {}
    return <String, dynamic>{};
  }

  void invalidate() {
    _access = null;
  }

  Future<String> accessToken() async {
    final a = _access;
    if (a != null && DateTime.now().isBefore(_exp)) return a;
    final rt = await _store.read(key: _rtKey);
    if (rt == null) {
      throw GoogleAuthException(tr('尚未登入 Google。'), needLogin: true);
    }
    final r = await http.post(
      Uri.parse('https://oauth2.googleapis.com/token'),
      body: {
        'client_id': kGoogleClientId,
        'client_secret': kGoogleClientSecret,
        'refresh_token': rt,
        'grant_type': 'refresh_token',
      },
    ).timeout(_net);
    final j = _json(r.body);
    if (r.statusCode != 200) {
      if (j['error'] == 'invalid_grant') {
        await _store.delete(key: _rtKey);
        _access = null;
        throw GoogleAuthException(
          tr('Google 登入已失效，請重新登入。'),
          needLogin: true,
        );
      }
      throw GoogleAuthException(
        tr('更新授權失敗：') + '${j['error_description'] ?? j['error'] ?? r.statusCode}',
      );
    }
    _setAccess(j);
    return _access!;
  }

  Future<void> signOut() async {
    try {
      final rt = await _store.read(key: _rtKey);
      if (rt != null) {
        await http
            .post(
              Uri.parse('https://oauth2.googleapis.com/revoke'),
              body: {'token': rt},
            )
            .timeout(_net);
      }
    } catch (_) {}
    try {
      await _store.delete(key: _rtKey);
    } catch (_) {}
    _access = null;
  }
}
