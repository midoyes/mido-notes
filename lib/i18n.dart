import 'dart:ui' as ui;

import 'i18n_en.dart';

/// 目前實際使用的語言：'zh'（繁體中文）或 'en'。由 AppSettings 設定。
String uiLang = 'zh';

/// 把「自動 / zh / en」偏好換算成實際語言。自動 = 跟隨手機／電腦的系統語言。
String resolveLang(String pref) {
  if (pref == 'zh' || pref == 'en') return pref;
  final code = ui.PlatformDispatcher.instance.locale.languageCode;
  return code == 'zh' ? 'zh' : 'en';
}

class _Pattern {
  _Pattern(this.re, this.en);

  final RegExp re;
  final String en;
}

List<_Pattern>? _patterns;

List<_Pattern> _build() {
  final keys = kEn.keys.where((k) => k.contains('{}')).toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  return [
    for (final k in keys)
      _Pattern(
        RegExp(
          '^${k.split('{}').map(RegExp.escape).join('(.+?)')}\$',
          dotAll: true,
        ),
        kEn[k]!,
      ),
  ];
}

/// 介面文字翻譯。程式裡的原始字串是繁體中文；語言為英文時查 [kEn]。
/// 含變數的句子（例如「已還原 3 則筆記」）用樣板比對，樣板中的 {} 代表變數。
String tr(String zh) {
  if (uiLang != 'en') return zh;
  final hit = kEn[zh];
  if (hit != null) return hit;
  for (final p in _patterns ??= _build()) {
    final m = p.re.firstMatch(zh);
    if (m == null) continue;
    var i = 1;
    return p.en.replaceAllMapped(RegExp(r'\{\}'), (_) {
      final v = i <= m.groupCount ? (m.group(i) ?? '') : '';
      i++;
      return v;
    });
  }
  return zh;
}
