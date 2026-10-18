import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../i18n.dart';

/// 非敏感的 App 設定（明文存放）：主題、檢視方式、排序、鎖定時間、防截圖、備份提醒。
class AppSettings extends ChangeNotifier {
  static const MethodChannel _secureChannel = MethodChannel('mido_notes/secure');

  String langPref = 'auto'; // auto | zh | en
  ThemeMode themeMode = ThemeMode.system;
  List<String> manualOrder = <String>[]; // 自訂排序（只存在本機，不同步）
  int themeSeed = 0; // 主題色索引
  bool pureBlack = false; // 深色模式使用純黑背景
  bool gridView = true;
  int gridColumns = 2; // 格狀顯示時每列幾欄（2 或 3）
  String sortKey = 'updated'; // updated | created | title
  bool sortAsc = false; // false = 新→舊（標題則是 Z→A）
  bool pinTop = true; // 釘選的項目固定在最上面
  int lockSeconds = 60; // 0 = 離開 App 立即鎖定
  bool secureScreen = true;

  DateTime? lastBackupAt;
  int backupRemindDays = 14; // 0 = 不提醒
  DateTime? remindSnoozedUntil;


  File? _file;

  Future<void> load() async {
    try {
      final dir = await getApplicationSupportDirectory();
      _file = File('${dir.path}/settings.json');
      if (await _file!.exists()) {
        final j = jsonDecode(await _file!.readAsString()) as Map<String, dynamic>;
        final tm = j['themeMode'] as String?;
        themeMode = ThemeMode.values.firstWhere(
          (m) => m.name == tm,
          orElse: () => ThemeMode.system,
        );
        final lp = j['langPref'] as String?;
        langPref = (lp == 'zh' || lp == 'en') ? lp! : 'auto';
        themeSeed = (j['themeSeed'] as int?) ?? 0;
        pureBlack = (j['pureBlack'] as bool?) ?? false;
        gridView = (j['gridView'] as bool?) ?? true;
        gridColumns = (j['gridColumns'] as int?) ?? 2;
        final sk = (j['sortKey'] as String?) ?? 'updated';
        sortKey = (sk == 'created' || sk == 'title' || sk == 'manual') ? sk : 'updated';
        manualOrder = ((j['manualOrder'] as List?) ?? const <dynamic>[])
            .whereType<String>()
            .toList();
        sortAsc = (j['sortAsc'] as bool?) ?? false;
        pinTop = (j['pinTop'] as bool?) ?? true;
        lockSeconds = (j['lockSeconds'] as int?) ?? 60;
        secureScreen = (j['secureScreen'] as bool?) ?? true;
        lastBackupAt = DateTime.tryParse((j['lastBackupAt'] as String?) ?? '');
        backupRemindDays = (j['backupRemindDays'] as int?) ?? 14;
        remindSnoozedUntil =
            DateTime.tryParse((j['remindSnoozedUntil'] as String?) ?? '');
      }
    } catch (e) {
      debugPrint('load settings failed: $e');
    }
    uiLang = resolveLang(langPref);
    await applySecure();
  }

  Future<void> applySecure() async {
    try {
      await _secureChannel.invokeMethod<void>('setSecure', {'on': secureScreen});
    } catch (_) {}
  }

  Future<void> _save() async {
    try {
      final f = _file;
      if (f == null) return;
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(jsonEncode({
        'themeMode': themeMode.name,
        'langPref': langPref,
        'themeSeed': themeSeed,
        'manualOrder': manualOrder,
        'pureBlack': pureBlack,
        'gridView': gridView,
        'gridColumns': gridColumns,
        'sortKey': sortKey,
        'sortAsc': sortAsc,
        'pinTop': pinTop,
        'lockSeconds': lockSeconds,
        'secureScreen': secureScreen,
        'lastBackupAt': lastBackupAt?.toIso8601String(),
        'backupRemindDays': backupRemindDays,
        'remindSnoozedUntil': remindSnoozedUntil?.toIso8601String(),
      }));
      await tmp.rename(f.path);
    } catch (e) {
      debugPrint('save settings failed: $e');
    }
  }

  Future<void> setLang(String pref) async {
    langPref = pref;
    uiLang = resolveLang(pref);
    notifyListeners();
    await _save();
  }

  Future<void> setManualOrder(List<String> order) async {
    manualOrder = order;
    sortKey = 'manual';
    notifyListeners();
    await _save();
  }

  Future<void> setThemeSeed(int i) async {
    themeSeed = i;
    notifyListeners();
    await _save();
  }

  Future<void> setPureBlack(bool v) async {
    pureBlack = v;
    notifyListeners();
    await _save();
  }

  Future<void> setThemeMode(ThemeMode m) async {
    themeMode = m;
    notifyListeners();
    await _save();
  }

  Future<void> setGridView(bool v) async {
    gridView = v;
    notifyListeners();
    await _save();
  }

  Future<void> setGridColumns(int c) async {
    gridColumns = c;
    notifyListeners();
    await _save();
  }

  Future<void> setSort(String key, bool asc) async {
    sortKey = key;
    sortAsc = asc;
    notifyListeners();
    await _save();
  }

  Future<void> setPinTop(bool v) async {
    pinTop = v;
    notifyListeners();
    await _save();
  }

  Future<void> setLockSeconds(int s) async {
    lockSeconds = s;
    notifyListeners();
    await _save();
  }

  Future<void> setSecureScreen(bool v) async {
    secureScreen = v;
    notifyListeners();
    await applySecure();
    await _save();
  }

  Future<void> setBackupRemindDays(int d) async {
    backupRemindDays = d;
    remindSnoozedUntil = null;
    notifyListeners();
    await _save();
  }

  Future<void> markBackupDone() async {
    lastBackupAt = DateTime.now();
    remindSnoozedUntil = null;
    notifyListeners();
    await _save();
  }

  Future<void> snoozeBackupReminder({int days = 3}) async {
    remindSnoozedUntil = DateTime.now().add(Duration(days: days));
    notifyListeners();
    await _save();
  }
}
