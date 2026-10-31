import '../i18n.dart';
enum NoteType { note, login }

class Folder {
  Folder({required this.id, required this.name, DateTime? updatedAt})
      : updatedAt = updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);

  final String id;
  String name;
  DateTime updatedAt; // 建立／改名的時間，同步時用來判斷哪一邊的名稱較新

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'updatedAt': updatedAt.toIso8601String()};

  factory Folder.fromJson(Map<String, dynamic> j) => Folder(
        id: j['id'] as String,
        name: (j['name'] as String?) ?? '',
        updatedAt: DateTime.tryParse((j['updatedAt'] as String?) ?? ''),
      );
}

/// 一組帳號＋密碼。同一則「帳號密碼」筆記可以有很多組（例如多個 Google 帳號）。
class Credential {
  Credential({this.username = '', this.password = ''});

  String username;
  String password;

  bool get isEmpty => username.trim().isEmpty && password.isEmpty;

  Map<String, dynamic> toJson() => {'username': username, 'password': password};

  factory Credential.fromJson(Map<String, dynamic> j) => Credential(
        username: (j['username'] as String?) ?? '',
        password: (j['password'] as String?) ?? '',
      );
}

/// 自訂欄位，例如「安全提問」「PIN 碼」「備用驗證碼」。
/// [secret] 為 true 時內容預設隱藏，也不會被首頁搜尋比對。
class CustomField {
  CustomField({this.label = '', this.value = '', this.secret = false});

  String label;
  String value;
  bool secret;

  bool get isEmpty => label.trim().isEmpty && value.trim().isEmpty;

  Map<String, dynamic> toJson() => {
        'label': label,
        'value': value,
        'secret': secret,
      };

  factory CustomField.fromJson(Map<String, dynamic> j) => CustomField(
        label: (j['label'] as String?) ?? '',
        value: (j['value'] as String?) ?? '',
        secret: (j['secret'] as bool?) ?? false,
      );
}

class Note {
  Note({
    required this.id,
    required this.type,
    this.title = '',
    this.body = '',
    this.site = '',
    List<Credential>? credentials,
    List<CustomField>? fields,
    List<String>? tags,
    this.folderId,
    this.pinned = false,
    this.color = 0,
    this.locked = false,
    this.deletedAt,
    this.remindAt,
    this.remindDone = false,
    List<String>? imageIds,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : credentials = credentials ?? <Credential>[],
        fields = fields ?? <CustomField>[],
        tags = tags ?? <String>[],
        imageIds = imageIds ?? <String>[],
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  final String id;
  final NoteType type;
  String title;
  String body; // 筆記內文；帳密類型則是「備註」
  String site;
  List<Credential> credentials;
  List<CustomField> fields;
  List<String> tags;
  String? folderId;
  bool pinned;
  int color; // 0 = 無，1~8 = 調色盤顏色
  bool locked; // 需要「鎖定密碼」才能開啟
  DateTime? deletedAt;
  DateTime? remindAt; // 提醒時間（null = 沒有提醒）
  bool remindDone; // 這次提醒已處理（按了「完成」）
  List<String> imageIds;
  final DateTime createdAt;
  DateTime updatedAt;

  bool get isTrashed => deletedAt != null;

  /// 有設定提醒、而且還沒處理。
  bool get remindActive => remindAt != null && !remindDone;

  bool get isBlank =>
      title.trim().isEmpty &&
      body.trim().isEmpty &&
      site.trim().isEmpty &&
      credentials.every((c) => c.isEmpty) &&
      fields.every((f) => f.isEmpty) &&
      imageIds.isEmpty;

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'title': title,
        'body': body,
        'site': site,
        'credentials': credentials.map((c) => c.toJson()).toList(),
        'fields': fields.map((f) => f.toJson()).toList(),
        'tags': tags,
        'folderId': folderId,
        'pinned': pinned,
        'color': color,
        'locked': locked,
        'deletedAt': deletedAt?.toIso8601String(),
        'remindAt': remindAt?.toIso8601String(),
        'remindDone': remindDone,
        'imageIds': imageIds,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory Note.fromJson(Map<String, dynamic> j) {
    // 相容 1.0.0 的舊資料：當時只有單一 username / password 欄位。
    final creds = <Credential>[];
    final raw = j['credentials'];
    if (raw is List) {
      for (final e in raw) {
        creds.add(Credential.fromJson(e as Map<String, dynamic>));
      }
    } else {
      final u = (j['username'] as String?) ?? '';
      final p = (j['password'] as String?) ?? '';
      if (u.isNotEmpty || p.isNotEmpty) {
        creds.add(Credential(username: u, password: p));
      }
    }

    final fieldList = <CustomField>[];
    final rawFields = j['fields'];
    if (rawFields is List) {
      for (final e in rawFields) {
        fieldList.add(CustomField.fromJson(e as Map<String, dynamic>));
      }
    }

    return Note(
      id: j['id'] as String,
      type: NoteType.values.firstWhere(
        (t) => t.name == j['type'],
        orElse: () => NoteType.note,
      ),
      title: (j['title'] as String?) ?? '',
      body: (j['body'] as String?) ?? '',
      site: (j['site'] as String?) ?? '',
      credentials: creds,
      fields: fieldList,
      tags: ((j['tags'] as List?) ?? const <dynamic>[])
          .map((e) => e as String)
          .toList(),
      folderId: j['folderId'] as String?,
      pinned: (j['pinned'] as bool?) ?? false,
      color: (j['color'] as int?) ?? 0,
      locked: (j['locked'] as bool?) ?? false,
      deletedAt: DateTime.tryParse((j['deletedAt'] as String?) ?? ''),
      remindAt: DateTime.tryParse((j['remindAt'] as String?) ?? ''),
      remindDone: (j['remindDone'] as bool?) ?? false,
      imageIds: ((j['imageIds'] as List?) ?? const <dynamic>[])
          .map((e) => e as String)
          .toList(),
      createdAt: DateTime.tryParse((j['createdAt'] as String?) ?? ''),
      updatedAt: DateTime.tryParse((j['updatedAt'] as String?) ?? ''),
    );
  }
}

extension NoteDisplay on Note {
  /// 顯示用的標題：沒有標題時退回網站名稱或預設文字。
  String get displayTitle {
    final t = title.trim();
    if (t.isNotEmpty) return t;
    if (type == NoteType.login) {
      return site.trim().isNotEmpty ? site.trim() : tr('未命名帳號');
    }
    return tr('無標題');
  }
}
