import 'csv_io.dart';

/// 從 Chrome／Google 密碼管理員、Edge、Firefox、Bitwarden、1Password 匯出的 CSV 讀到的一筆帳密。
class ImportedLogin {
  const ImportedLogin({
    required this.name,
    required this.url,
    required this.username,
    required this.password,
    required this.note,
  });

  final String name;
  final String url;
  final String username;
  final String password;
  final String note;
}

class LoginCsvResult {
  const LoginCsvResult(this.items);

  final List<ImportedLogin> items;
}

/// 解析帳密 CSV。看不出是帳密檔（沒有 password 欄位）時回傳 null。
LoginCsvResult? parseLoginCsv(String text) {
  final rows = parseCsv(text);
  if (rows.length < 2) return null;

  final header = rows.first.map((h) => h.trim().toLowerCase()).toList();
  int idx(List<String> names) {
    for (final n in names) {
      final i = header.indexOf(n);
      if (i >= 0) return i;
    }
    return -1;
  }

  final iName = idx(['name', 'title']);
  final iUrl = idx(['url', 'login_uri', 'website', 'web site', 'origin']);
  final iUser = idx(['username', 'login_username', 'user', 'login', 'email']);
  final iPass = idx(['password', 'login_password']);
  final iNote = idx(['note', 'notes', 'comment']);
  if (iPass < 0 || (iUser < 0 && iUrl < 0)) return null;

  String cell(List<String> r, int i, {bool trim = true}) {
    if (i < 0 || i >= r.length) return '';
    return trim ? r[i].trim() : r[i];
  }

  final items = <ImportedLogin>[];
  for (final r in rows.skip(1)) {
    final user = cell(r, iUser);
    final pass = cell(r, iPass, trim: false);
    if (user.isEmpty && pass.isEmpty) continue;
    items.add(
      ImportedLogin(
        name: cell(r, iName),
        url: cell(r, iUrl),
        username: user,
        password: pass,
        note: cell(r, iNote),
      ),
    );
  }
  if (items.isEmpty) return null;
  return LoginCsvResult(items);
}

/// 用來判斷「是不是同一個網站」的代號：優先用網址的網域（去掉 www.），沒有網址就用名稱。
String siteKey(String url, String name) {
  final u = url.trim().toLowerCase();
  if (u.isNotEmpty) {
    final uri = Uri.tryParse(u.contains('://') ? u : 'https://$u');
    var host = uri?.host ?? '';
    if (host.startsWith('www.')) host = host.substring(4);
    if (host.isNotEmpty) return host;
  }
  final nm = name.trim().toLowerCase();
  return nm.isNotEmpty ? 'name:$nm' : '';
}

/// 依網站合併後，大約會產生幾則筆記（給匯入前的預覽用）。
int countSiteGroups(List<ImportedLogin> items) {
  final keys = <String>{};
  var n = 0;
  for (final it in items) {
    final k = siteKey(it.url, it.name);
    keys.add(k.isEmpty ? '#${n++}' : k);
  }
  return keys.length;
}
