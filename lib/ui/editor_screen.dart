import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

import '../app_state.dart';
import '../data/models.dart';
import '../data/password_tools.dart';
import 'common.dart';
import 'encrypted_image.dart';
import 'draw_screen.dart';
import 'export_note.dart';
import 'format_bar.dart';
import 'markdown_view.dart';
import 'media_utils.dart';
import 'ocr_dialog.dart';
import '../ocr.dart';
import 'record_dialog.dart';
import '../i18n.dart';

/// 可以把「搜尋到的關鍵字」標上底色的輸入控制器。
class _HighlightController extends TextEditingController {
  _HighlightController({super.text});

  List<TextRange> matches = const <TextRange>[];
  int current = -1; // 目前選取的那一個，用比較深的顏色標示

  void setMatches(List<TextRange> m, int cur) {
    matches = m;
    current = cur;
    notifyListeners();
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    if (matches.isEmpty) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }
    final cs = Theme.of(context).colorScheme;
    final spans = <TextSpan>[];
    var pos = 0;
    for (var i = 0; i < matches.length; i++) {
      final m = matches[i];
      if (m.start < pos || m.end > text.length) continue; // 文字剛被修改，略過過期的標示
      if (m.start > pos) spans.add(TextSpan(text: text.substring(pos, m.start)));
      final isCurrent = i == current;
      spans.add(
        TextSpan(
          text: text.substring(m.start, m.end),
          style: TextStyle(
            backgroundColor: isCurrent ? cs.primary : cs.tertiaryContainer,
            color: isCurrent ? cs.onPrimary : cs.onTertiaryContainer,
          ),
        ),
      );
      pos = m.end;
    }
    if (pos < text.length) spans.add(TextSpan(text: text.substring(pos)));
    return TextSpan(style: style, children: spans);
  }
}

List<TextRange> _findAll(String text, String q) {
  if (q.isEmpty) return const <TextRange>[];
  final re = RegExp(RegExp.escape(q), caseSensitive: false, unicode: true);
  return [
    for (final m in re.allMatches(text)) TextRange(start: m.start, end: m.end),
  ];
}

/// 編輯畫面裡「一組帳號密碼」用到的輸入控制器。
class _CredCtl {
  _CredCtl([String u = '', String p = ''])
      : user = _HighlightController(text: u),
        pass = TextEditingController(text: p);

  final _HighlightController user;
  final TextEditingController pass;
  final GlobalKey cardKey = GlobalKey();
  bool show = false;

  bool get hasContent => user.text.trim().isNotEmpty || pass.text.isNotEmpty;

  void dispose() {
    user.dispose();
    pass.dispose();
  }
}

/// 編輯畫面裡「一個自訂欄位」用到的輸入控制器。
class _FieldCtl {
  _FieldCtl([String l = '', String v = '', this.secret = false])
      : label = TextEditingController(text: l),
        value = _HighlightController(text: v);

  final TextEditingController label;
  final _HighlightController value;
  final GlobalKey cardKey = GlobalKey();
  bool secret;
  bool show = false;

  bool get hasContent => label.text.trim().isNotEmpty || value.text.trim().isNotEmpty;

  void dispose() {
    label.dispose();
    value.dispose();
  }
}

/// 筆記 / 帳密 編輯畫面。
/// 內容會自動儲存（停止輸入、離開畫面、App 進背景、鎖定前），
/// 也可以按右上角「儲存」立刻存檔並回到列表。
///
/// [initialQuery]：從首頁搜尋點進來時帶入的關鍵字，會自動標示並捲到該位置。
class EditorScreen extends StatefulWidget {
  const EditorScreen({
    super.key,
    this.noteId,
    this.newType,
    this.folderId,
    this.initialQuery,
  });

  final String? noteId;
  final NoteType? newType;
  final String? folderId;
  final String? initialQuery;

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> with WidgetsBindingObserver {
  late Note _note;
  late bool _inStore;
  bool _dirty = false;
  bool _deleted = false;
  Timer? _debounce;
  final List<String> _removedImages = <String>[];

  final TextEditingController _title = TextEditingController();
  final _HighlightController _body = _HighlightController();
  final TextEditingController _site = TextEditingController();
  final List<_CredCtl> _creds = <_CredCtl>[];
  final List<_FieldCtl> _fields = <_FieldCtl>[];
  final List<String> _tags = <String>[];

  final ScrollController _scroll = ScrollController();
  final GlobalKey _bodyKey = GlobalKey();
  final FocusNode _bodyFocus = FocusNode();
  String _lastBody = '';

  // 筆記內搜尋
  bool _finding = false;
  bool _preview = false; // Markdown 預覽模式（只用於一般筆記）
  bool _findAutofocus = true;
  final TextEditingController _findCtl = TextEditingController();
  List<TextRange> _matches = const <TextRange>[];
  int _current = 0;

  // 從首頁搜尋點進來時，要強調的那一組帳號／欄位
  int? _focusCred;
  int? _focusField;

  bool get _isLogin => _note.type == NoteType.login;

  @override
  void initState() {
    super.initState();
    final existing = widget.noteId == null ? null : vault.byId(widget.noteId!);
    if (existing != null) {
      _note = existing;
      _inStore = true;
    } else {
      _note = vault.newNote(widget.newType ?? NoteType.note, folderId: widget.folderId);
      _inStore = false;
    }
    _title.text = _note.title;
    _body.text = _note.body;
    _lastBody = _body.text;
    _bodyFocus.addListener(() {
      if (mounted) setState(() {});
    });
    _site.text = _note.site;
    _tags.addAll(_note.tags);
    for (final c in _note.credentials) {
      _creds.add(_CredCtl(c.username, c.password));
    }
    if (_isLogin && _creds.isEmpty) _creds.add(_CredCtl());
    for (final f in _note.fields) {
      _fields.add(_FieldCtl(f.label, f.value, f.secret));
    }
    WidgetsBinding.instance.addObserver(this);
    vault.addBeforeLock(_lockHook);

    final q = widget.initialQuery?.trim() ?? '';
    if (existing != null && q.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _applyInitialQuery(q);
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    vault.removeBeforeLock(_lockHook);
    _debounce?.cancel();
    _title.dispose();
    _body.dispose();
    _bodyFocus.dispose();
    _site.dispose();
    _findCtl.dispose();
    _scroll.dispose();
    for (final c in _creds) {
      c.dispose();
    }
    for (final f in _fields) {
      f.dispose();
    }
    super.dispose();
  }

  Future<void> _lockHook() async => _save();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) _save();
  }

  void _touched() {
    _dirty = true;
    vault.bump();
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 800), _save);
  }

  void _onBodyChanged() {
    // 清單行按 Enter 自動接下一項
    if (!_isLogin) MdFormat.continueList(_body, _lastBody);
    _lastBody = _body.text;
    if (_finding) {
      _runFind(keepIndex: true, scroll: false);
    } else if (_body.matches.isNotEmpty) {
      _body.setMatches(const <TextRange>[], -1);
    }
    _touched();
  }

  Future<void> _toggleLock() async {
    if (!_note.locked) {
      if (!await ensureLockPassword(context)) return;
      if (!mounted) return;
      setState(() => _note.locked = true);
    } else {
      if (!await askLockPassword(context, title: tr('輸入鎖定密碼以解除鎖定'))) return;
      if (!mounted) return;
      setState(() => _note.locked = false);
    }
    _touched();
  }

  Future<void> _chooseColor() async {
    final c = await pickNoteColor(context, _note.color);
    if (c == null) return;
    setState(() => _note.color = c);
    _touched();
  }

  /// 另存新檔：用目前畫面上的內容（含還沒自動儲存的部分）。
  Future<void> _export() async {
    final b = StringBuffer();
    if (_isLogin) {
      b.writeln('# ${_title.text}');
      if (_site.text.trim().isNotEmpty) b.writeln('${tr('網站')}: ${_site.text}');
      var i = 1;
      for (final c in _creds) {
        if (!c.hasContent) continue;
        b.writeln('');
        b.writeln('[${tr('帳號')} $i]');
        b.writeln('${tr('帳號')}: ${c.user.text}');
        b.writeln('${tr('密碼')}: ${c.pass.text}');
        i++;
      }
      for (final f in _fields) {
        if (f.hasContent) b.writeln('${f.label.text}: ${f.value.text}');
      }
      if (_body.text.trim().isNotEmpty) {
        b.writeln('');
        b.writeln(_body.text);
      }
    } else {
      b.write(_body.text);
    }
    await exportNoteToFile(
      context,
      title: _title.text.trim().isEmpty ? tr('筆記') : _title.text.trim(),
      content: b.toString(),
      hasSecrets: _isLogin,
      attachmentIds: List<String>.of(_note.imageIds),
    );
  }

  void _save() {
    if (_deleted || !_dirty) return;
    _note
      ..title = _title.text
      ..body = _body.text
      ..site = _site.text
      ..tags = List<String>.of(_tags);
    if (_isLogin) {
      _note.credentials = [
        for (final c in _creds)
          if (c.hasContent) Credential(username: c.user.text, password: c.pass.text),
      ];
      _note.fields = [
        for (final f in _fields)
          if (f.hasContent)
            CustomField(label: f.label.text, value: f.value.text, secret: f.secret),
      ];
    }
    if (!_inStore && _note.isBlank) return;
    vault.upsertNote(_note);
    _inStore = true;
    _dirty = false;
    for (final id in _removedImages) {
      vault.deleteImageFile(id);
    }
    _removedImages.clear();
  }

  /// 右上角「儲存」：立刻存檔並回到列表。
  Future<void> _saveAndClose() async {
    _debounce?.cancel();
    _dirty = true;
    _save();
    final saved = _inStore;
    await vault.flush(); // 等加密寫入真的完成
    if (!mounted) return;
    if (vault.lastSaveError != null) {
      _dirty = true; // 失敗：留在編輯畫面，之後仍可重試
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(tr('儲存失敗')),
          content: Text(tr('資料沒有寫入成功（可能是儲存空間不足）。請先清出空間，再按一次「儲存」。\n\n${vault.lastSaveError}')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('確定'))),
          ],
        ),
      );
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(saved ? tr('已儲存') : tr('沒有內容，未建立')),
          duration: const Duration(seconds: 2),
        ),
      );
    Navigator.pop(context);
  }

  Future<void> _delete() async {
    if (!_inStore) {
      _deleted = true;
      Navigator.pop(context);
      return;
    }
    final ok = await confirmDialog(
      context,
      title: tr('移到回收桶'),
      message: tr('這則內容會移到回收桶，30 天內都可以還原。'),
      confirmText: tr('移到回收桶'),
      danger: true,
    );
    if (!ok || !mounted) return;
    _deleted = true;
    _debounce?.cancel();
    vault.moveToTrash(_note.id);
    Navigator.pop(context);
  }

  Future<void> _chooseFolder() async {
    final r = await pickFolder(context, current: _note.folderId);
    if (r == null) return;
    setState(() => _note.folderId = r.isEmpty ? null : r);
    _touched();
  }

  // ───────────────────────── 標籤 ─────────────────────────

  Future<void> _addTag() async {
    final existing = vault.sortedTags.where((t) => !_tags.contains(t)).toList();
    final c = TextEditingController();
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('新增標籤')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: c,
                autofocus: true,
                maxLength: 20,
                decoration: InputDecoration(hintText: tr('標籤名稱，例如：工作')),
                onSubmitted: (v) => Navigator.pop(ctx, v),
              ),
              if (existing.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(tr('已有的標籤'), style: Theme.of(ctx).textTheme.labelMedium),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final t in existing)
                      ActionChip(
                        label: Text('#$t'),
                        onPressed: () => Navigator.pop(ctx, t),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr('取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, c.text),
            child: Text(tr('加入')),
          ),
        ],
      ),
    );
    var t = (r ?? '').trim();
    if (t.startsWith('#')) t = t.substring(1).trim();
    if (t.isEmpty) return;
    if (_tags.any((x) => x.toLowerCase() == t.toLowerCase())) return;
    setState(() => _tags.add(t));
    _touched();
  }

  Widget _tagsSection() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Wrap(
        spacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final t in _tags)
            InputChip(
              label: Text('#$t'),
              visualDensity: VisualDensity.compact,
              onDeleted: () {
                setState(() => _tags.remove(t));
                _touched();
              },
            ),
          ActionChip(
            avatar: const Icon(Icons.sell_outlined, size: 16),
            label: Text(tr('標籤')),
            visualDensity: VisualDensity.compact,
            onPressed: _addTag,
          ),
        ],
      ),
    );
  }

  // ───────────────────────── 筆記內搜尋 ─────────────────────────

  void _openFind() {
    setState(() {
      _finding = true;
      _findAutofocus = true;
    });
  }

  void _closeFind() {
    _findCtl.clear();
    _body.setMatches(const <TextRange>[], -1);
    setState(() {
      _finding = false;
      _matches = const <TextRange>[];
      _current = 0;
    });
  }

  void _runFind({bool keepIndex = false, bool scroll = true}) {
    final list = _findAll(_body.text, _findCtl.text);
    var cur = 0;
    if (list.isNotEmpty && keepIndex) {
      cur = math.min(math.max(_current, 0), list.length - 1);
    }
    _body.setMatches(list, list.isEmpty ? -1 : cur);
    setState(() {
      _matches = list;
      _current = cur;
    });
    if (scroll && list.isNotEmpty) {
      final start = list[cur].start;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scrollToTextOffset(start);
      });
    }
  }

  void _goto(int delta) {
    final n = _matches.length;
    if (n == 0) return;
    final cur = (_current + delta + n) % n;
    _body.setMatches(_matches, cur);
    setState(() => _current = cur);
    final start = _matches[cur].start;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scrollToTextOffset(start);
    });
  }

  RenderEditable? _findEditable(RenderObject root) {
    RenderEditable? found;
    void visit(RenderObject o) {
      if (found != null) return;
      if (o is RenderEditable) {
        found = o;
        return;
      }
      o.visitChildren(visit);
    }

    visit(root);
    return found;
  }

  /// 把內文裡第 [textOffset] 個字元所在的那一行捲到可視區域的正中央。
  /// 直接向輸入框「真正排好版的文字」問游標的位置（不自己估算），所以不受字型、寬度、縮放影響。
  void _scrollToTextOffset(int textOffset) {
    final ctx = _bodyKey.currentContext;
    if (ctx == null || !_scroll.hasClients) return;
    final box = ctx.findRenderObject();
    if (box == null) return;
    final re = _findEditable(box);
    if (re == null || !re.hasSize) return;
    final vpObj = _scroll.position.context.storageContext.findRenderObject();
    if (vpObj is! RenderBox || !vpObj.hasSize) return;
    final off = math.min(textOffset, _body.text.length);
    final caret = re.getLocalRectForCaret(TextPosition(offset: off));
    final lineCenterY = re.localToGlobal(caret.center).dy;
    final viewCenterY = vpObj.localToGlobal(vpObj.size.center(Offset.zero)).dy;
    final pos = _scroll.position;
    final target = (pos.pixels + lineCenterY - viewCenterY)
        .clamp(pos.minScrollExtent, pos.maxScrollExtent);
    _scroll.animateTo(
      target.toDouble(),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  /// 從首頁搜尋點進來：標示關鍵字並捲到該處。
  void _applyInitialQuery(String q) {
    if (_isLogin) {
      int? firstCred;
      int? firstField;
      for (var i = 0; i < _creds.length; i++) {
        final ms = _findAll(_creds[i].user.text, q);
        if (ms.isNotEmpty) {
          _creds[i].user.setMatches(ms, 0);
          firstCred ??= i;
        }
      }
      for (var i = 0; i < _fields.length; i++) {
        final f = _fields[i];
        if (f.secret) continue; // 隱藏的欄位內容不標示
        final ms = _findAll(f.value.text, q);
        if (ms.isNotEmpty) {
          f.value.setMatches(ms, 0);
          firstField ??= i;
        }
      }
      final bm = _findAll(_body.text, q);
      _body.setMatches(bm, bm.isEmpty ? -1 : 0);

      final fc = firstCred;
      final ff = fc == null ? firstField : null;
      setState(() {
        _focusCred = fc;
        _focusField = ff;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        BuildContext? target;
        if (fc != null) {
          target = _creds[fc].cardKey.currentContext;
        } else if (ff != null) {
          target = _fields[ff].cardKey.currentContext;
        }
        if (target != null) {
          Scrollable.ensureVisible(
            target,
            alignment: 0.5,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        } else if (bm.isNotEmpty) {
          _scrollToTextOffset(bm.first.start);
        }
      });
    } else {
      setState(() {
        _finding = true;
        _findAutofocus = false; // 不要自動跳出鍵盤，方便直接看內容
      });
      _findCtl.text = q;
      _runFind();
    }
  }

  // ───────────────────────── 多組帳號 ─────────────────────────

  void _addCred() {
    setState(() => _creds.add(_CredCtl()));
    vault.bump();
  }

  Future<void> _removeCred(int i) async {
    final c = _creds[i];
    if (c.hasContent) {
      final ok = await confirmDialog(
        context,
        title: tr('移除這組帳號'),
        message: tr('這組帳號與密碼會從這則筆記移除。'),
        confirmText: tr('移除'),
        danger: true,
      );
      if (!ok || !mounted) return;
    }
    setState(() {
      _focusCred = null;
      if (_creds.length == 1) {
        // 至少保留一組空白欄位
        c.user.clear();
        c.pass.clear();
      } else {
        _creds.removeAt(i);
        // 這一幀還在畫面上，等畫完再釋放，避免「已釋放的控制器」錯誤
        WidgetsBinding.instance.addPostFrameCallback((_) => c.dispose());
      }
    });
    _touched();
  }

  Future<void> _generate(_CredCtl c) async {
    final pw = await showPasswordGenerator(context);
    if (pw == null) return;
    setState(() {
      c.pass.text = pw;
      c.show = true;
    });
    _touched();
  }

  // ───────────────────────── 自訂欄位 ─────────────────────────

  void _addField(String label, bool secret) {
    final f = _FieldCtl(label, '', secret);
    setState(() => _fields.add(f));
    vault.bump();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = f.cardKey.currentContext;
      if (ctx != null && mounted) {
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.5,
          duration: const Duration(milliseconds: 250),
        );
      }
    });
  }

  Future<void> _removeField(int i) async {
    final f = _fields[i];
    if (f.hasContent) {
      final ok = await confirmDialog(
        context,
        title: tr('移除欄位'),
        message: tr('這個欄位的內容會從這則筆記移除。'),
        confirmText: tr('移除'),
        danger: true,
      );
      if (!ok || !mounted) return;
    }
    setState(() {
      _focusField = null;
      _fields.removeAt(i);
      WidgetsBinding.instance.addPostFrameCallback((_) => f.dispose());
    });
    _touched();
  }

  void _addFieldSheet() {
    Widget tile(
      BuildContext ctx,
      IconData icon,
      String title,
      String label,
      bool secret,
    ) {
      return ListTile(
        leading: Icon(icon),
        title: Text(title),
        onTap: () {
          Navigator.pop(ctx);
          _addField(label, secret);
        },
      );
    }

    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              tile(ctx, Icons.edit_outlined, tr('自訂欄位'), '', false),
              tile(ctx, Icons.help_outline, tr('安全提問（內容隱藏）'), tr('安全提問'), true),
              tile(ctx, Icons.pin_outlined, tr('PIN 碼（內容隱藏）'), tr('PIN 碼'), true),
              tile(ctx, Icons.vpn_key_outlined, tr('備用驗證碼（內容隱藏）'), tr('備用驗證碼'), true),
              tile(ctx, Icons.mail_outline, tr('復原信箱'), tr('復原信箱'), false),
              tile(ctx, Icons.phone_outlined, tr('電話 / 客服'), tr('電話'), false),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fieldCard(int i) {
    final f = _fields[i];
    final cs = Theme.of(context).colorScheme;
    final focused = _focusField == i;
    return Container(
      key: f.cardKey,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(12, 0, 4, 4),
      decoration: BoxDecoration(
        border: Border.all(
          color: focused ? cs.primary : cs.outlineVariant,
          width: focused ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: f.label,
                  enableIMEPersonalizedLearning: false,
                  onChanged: (_) => _touched(),
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: cs.primary,
                      ),
                  decoration: InputDecoration(
                    hintText: tr('欄位名稱（例如：安全提問）'),
                    border: InputBorder.none,
                    isDense: true,
                  ),
                ),
              ),
              IconButton(
                tooltip: tr('移除欄位'),
                icon: const Icon(Icons.close),
                onPressed: () => _removeField(i),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextField(
              controller: f.value,
              obscureText: f.secret && !f.show,
              enableSuggestions: !f.secret,
              autocorrect: false,
              enableIMEPersonalizedLearning: false,
              minLines: 1,
              maxLines: (f.secret && !f.show) ? 1 : null,
              keyboardType:
                  f.secret ? TextInputType.visiblePassword : TextInputType.multiline,
              onChanged: (_) {
                if (f.value.matches.isNotEmpty) {
                  f.value.setMatches(const <TextRange>[], -1);
                }
                _touched();
              },
              decoration: InputDecoration(
                labelText: tr('內容'),
                border: const OutlineInputBorder(),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (f.secret)
                      IconButton(
                        tooltip: f.show ? tr('隱藏') : tr('顯示'),
                        icon: Icon(f.show ? Icons.visibility_off : Icons.visibility),
                        onPressed: () => setState(() => f.show = !f.show),
                      ),
                    IconButton(
                      tooltip: tr('複製'),
                      icon: const Icon(Icons.copy),
                      onPressed: () => copyWithClear(
                        context,
                        f.value.text,
                        f.label.text.trim().isEmpty ? tr('內容') : f.label.text.trim(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(tr('隱藏內容')),
              value: f.secret,
              onChanged: (v) {
                setState(() {
                  f.secret = v;
                  f.show = false;
                });
                _touched();
              },
            ),
          ),
        ],
      ),
    );
  }

  // ───────────────────────── 圖片 ─────────────────────────

  Future<void> _addImages(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final List<XFile> files;
      if (source == ImageSource.gallery) {
        files = await vault.withExternal(
          () => picker.pickMultiImage(
            maxWidth: 1920,
            maxHeight: 1920,
            imageQuality: 85,
          ),
        );
      } else {
        final x = await vault.withExternal(
          () => picker.pickImage(
            source: source,
            maxWidth: 1920,
            maxHeight: 1920,
            imageQuality: 85,
          ),
        );
        files = x == null ? <XFile>[] : <XFile>[x];
      }
      for (final x in files) {
        final bytes = await x.readAsBytes();
        // 選圖時系統會留下未加密的暫存檔，讀完立刻刪除。
        try {
          await File(x.path).delete();
        } catch (_) {}
        final id = await vault.addImage(bytes);
        if (!mounted) return;
        setState(() => _note.imageIds.add(id));
        _touched();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr('加入圖片失敗：$e'))),
        );
      }
    }
  }

  void _imageSheet() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(tr('相片（從相簿選擇）')),
              onTap: () {
                Navigator.pop(ctx);
                _addImages(ImageSource.gallery);
              },
            ),
            if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS)
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(tr('拍照（即時拍攝）')),
              onTap: () {
                Navigator.pop(ctx);
                _addImages(ImageSource.camera);
              },
            ),
            if (ocrSupported && _isMobile)
              ListTile(
                leading: const Icon(Icons.document_scanner_outlined),
                title: Text(tr('掃描文字（拍照轉文字）')),
                onTap: () {
                  Navigator.pop(ctx);
                  _scanText(camera: true);
                },
              ),
            if (ocrSupported)
              ListTile(
                leading: const Icon(Icons.text_snippet_outlined),
                title: Text(tr('圖片轉文字（選擇圖片）')),
                onTap: () {
                  Navigator.pop(ctx);
                  _scanText(camera: false);
                },
              ),
            if (ocrIsWindows)
              ListTile(
                leading: const Icon(Icons.screenshot_monitor_outlined),
                title: Text(tr('剪貼簿截圖轉文字（Win+Shift+S）')),
                onTap: () {
                  Navigator.pop(ctx);
                  _scanClipboard();
                },
              ),
            ListTile(
              leading: const Icon(Icons.draw_outlined),
              title: Text(tr('手寫繪圖')),
              onTap: () {
                Navigator.pop(ctx);
                _addDrawing();
              },
            ),
            ListTile(
              leading: const Icon(Icons.video_library_outlined),
              title: Text(tr('影片（從相簿／檔案選擇）')),
              onTap: () {
                Navigator.pop(ctx);
                _addVideo(camera: false);
              },
            ),
            if (_isMobile)
              ListTile(
                leading: const Icon(Icons.videocam_outlined),
                title: Text(tr('錄影（即時拍攝）')),
                onTap: () {
                  Navigator.pop(ctx);
                  _addVideo(camera: true);
                },
              ),
            ListTile(
              leading: const Icon(Icons.mic_none),
              title: Text(tr('即時錄音')),
              onTap: () {
                Navigator.pop(ctx);
                _addRecording();
              },
            ),
            ListTile(
              leading: const Icon(Icons.audio_file_outlined),
              title: Text(tr('錄音檔（從檔案選擇）')),
              onTap: () {
                Navigator.pop(ctx);
                _addAudioFile();
              },
            ),
          ],
        ),
      ),
    );
  }

  bool get _isMobile => Platform.isAndroid || Platform.isIOS;

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _attach(String id) async {
    if (!mounted) return;
    setState(() => _note.imageIds.add(id));
    _touched();
  }

  /// 把辨識出來的文字加到筆記內文最後面。
  void _appendText(String t) {
    final v = _body.text;
    final sep = v.isEmpty ? '' : (v.endsWith('\n\n') ? '' : (v.endsWith('\n') ? '\n' : '\n\n'));
    final nt = '$v$sep$t\n';
    setState(() {
      _body.text = nt;
      _body.selection = TextSelection.collapsed(offset: nt.length);
      _lastBody = nt;
    });
    _touched();
    _toast(tr('已插入辨識的文字'));
  }

  /// Windows：把剪貼簿裡的截圖轉成文字（截圖比拍螢幕照片準確很多）。
  Future<void> _scanClipboard() async {
    final bytes = await readClipboardImage();
    if (!mounted) return;
    if (bytes == null) {
      _toast(tr('剪貼簿裡沒有圖片。請先按 Win+Shift+S 框選截圖，再回來按這個。'));
      return;
    }
    final out = await showOcrDialog(context, bytes, offerKeepImage: true);
    if (out == null || !mounted) return;
    _appendText(out.text);
    if (out.keepImage) {
      await _attach(await vault.addImage(bytes));
    }
  }

  /// 拍照／選圖 → 轉文字 → 確認後插入筆記。
  Future<void> _scanText({required bool camera}) async {
    try {
      Uint8List? bytes;
      if (_isMobile) {
        final x = await vault.withExternal(
          () => ImagePicker().pickImage(
            source: camera ? ImageSource.camera : ImageSource.gallery,
            maxWidth: 3000,
            maxHeight: 3000,
            imageQuality: 92,
          ),
        );
        if (x == null) return;
        bytes = await x.readAsBytes();
        try {
          await File(x.path).delete(); // 系統留下的未加密暫存檔
        } catch (_) {}
      } else {
        final r = await vault.withExternal(
          () => FilePicker.platform.pickFiles(type: FileType.image, withData: true),
        );
        bytes = r?.files.single.bytes;
        if (bytes == null && r?.files.single.path != null) {
          bytes = await File(r!.files.single.path!).readAsBytes();
        }
      }
      if (bytes == null || !mounted) return;
      final out = await showOcrDialog(context, bytes, offerKeepImage: true);
      if (out == null || !mounted) return;
      _appendText(out.text);
      if (out.keepImage) {
        await _attach(await vault.addImage(bytes));
      }
    } catch (e) {
      _toast(tr('辨識失敗：$e'));
    }
  }

  /// 手寫／繪圖：結果存成圖片附件。
  Future<void> _addDrawing() async {
    final bytes = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute<Uint8List>(builder: (_) => const DrawScreen()),
    );
    if (bytes == null || !mounted) return;
    try {
      await _attach(await vault.addImage(bytes));
    } catch (e) {
      _toast(tr('加入圖片失敗：$e'));
    }
  }

  /// 把檔案（路徑）讀進來、檢查大小、加密後加入附件，並刪除未加密的暫存檔。
  Future<void> _storeMediaFile(String path, {required bool video, required bool deleteSource}) async {
    final f = File(path);
    try {
      final len = await f.length();
      if (len > kMaxMediaBytes) {
        _toast(tr('檔案太大（${fmtBytes(len)}），單一檔案上限 30 MB。'));
        return;
      }
      final bytes = await f.readAsBytes();
      final id = await vault.addMedia(
        bytes,
        video: video,
        ext: extOfPath(path, video ? 'mp4' : 'm4a'),
      );
      await _attach(id);
    } catch (e) {
      _toast(tr('加入失敗：$e'));
    } finally {
      if (deleteSource) {
        try {
          await f.delete();
        } catch (_) {}
      }
    }
  }

  Future<void> _addVideo({required bool camera}) async {
    try {
      String? path;
      var temp = false;
      if (_isMobile) {
        final x = await vault.withExternal(
          () => ImagePicker().pickVideo(
            source: camera ? ImageSource.camera : ImageSource.gallery,
            maxDuration: const Duration(minutes: 2),
          ),
        );
        path = x?.path;
        temp = true; // 選取時系統會留下未加密的暫存檔
      } else {
        final r = await vault.withExternal(
          () => FilePicker.platform.pickFiles(type: FileType.video),
        );
        path = r?.files.single.path;
      }
      if (path == null) return;
      await _storeMediaFile(path, video: true, deleteSource: temp);
    } catch (e) {
      _toast(tr('加入失敗：$e'));
    }
  }

  Future<void> _addAudioFile() async {
    try {
      final r = await vault.withExternal(
        () => FilePicker.platform.pickFiles(type: FileType.audio),
      );
      final path = r?.files.single.path;
      if (path == null) return;
      await _storeMediaFile(path, video: false, deleteSource: false);
    } catch (e) {
      _toast(tr('加入失敗：$e'));
    }
  }

  Future<void> _addRecording() async {
    final r = await vault.withExternal(
      () => showDialog<RecordResult>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const RecordDialog(),
      ),
    );
    if (r == null || !mounted) return;
    try {
      await _attach(await vault.addMedia(r.bytes, video: false, ext: r.ext));
    } catch (e) {
      _toast(tr('加入失敗：$e'));
    }
  }

  void _mediaSheet(String id) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(isVideoId(id) ? Icons.play_circle_outline : Icons.play_arrow),
              title: Text(isVideoId(id) ? tr('播放影片') : tr('播放錄音')),
              onTap: () {
                Navigator.pop(ctx);
                openMedia(context, id);
              },
            ),
            ListTile(
              leading: const Icon(Icons.save_alt),
              title: Text(tr('另存附件')),
              onTap: () {
                Navigator.pop(ctx);
                saveAttachmentAs(context, id, baseName: _title.text.trim().isEmpty ? null : _title.text.trim());
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: Text(tr('刪除')),
              onTap: () async {
                Navigator.pop(ctx);
                final ok = await confirmDialog(
                  context,
                  title: tr('刪除這個附件？'),
                  message: tr('刪除後無法復原。'),
                  confirmText: tr('刪除'),
                );
                if (ok != true || !mounted) return;
                setState(() => _note.imageIds.remove(id));
                _removedImages.add(id);
                _touched();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _mediaTile(String id) {
    final cs = Theme.of(context).colorScheme;
    final video = isVideoId(id);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _mediaSheet(id),
        child: Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: cs.secondaryContainer,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(video ? Icons.videocam : Icons.mic, size: 32, color: cs.onSecondaryContainer),
              const SizedBox(height: 4),
              Text(
                '${video ? tr('影片') : tr('錄音')} .${mediaExt(id)}',
                style: TextStyle(fontSize: 12, color: cs.onSecondaryContainer),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _viewImage(String id) async {
    final res = await Navigator.of(context).push<Object>(
      MaterialPageRoute<Object>(builder: (_) => ImageViewerScreen(id: id)),
    );
    if (res is String && mounted) {
      _appendText(res); // 從圖片辨識出來的文字
      return;
    }
    final remove = res == true;
    if (remove && mounted) {
      setState(() => _note.imageIds.remove(id));
      _removedImages.add(id);
      _touched();
    }
  }

  Widget _imageStrip() {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: 96,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final id in _note.imageIds)
            if (isMediaId(id))
              _mediaTile(id)
            else
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => _viewImage(id),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 96,
                    height: 96,
                    child: EncryptedImage(id: id, cacheWidth: 300),
                  ),
                ),
              ),
            ),
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: _imageSheet,
            child: Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: cs.outlineVariant),
              ),
              child: Icon(Icons.add_photo_alternate_outlined, color: cs.primary),
            ),
          ),
        ],
      ),
    );
  }

  // ───────────────────────── 欄位 ─────────────────────────

  Widget _field({
    required TextEditingController controller,
    required String label,
    IconData? icon,
    bool copy = false,
    TextInputType? keyboard,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        keyboardType: keyboard,
        enableIMEPersonalizedLearning: false,
        autocorrect: false,
        onChanged: (_) {
          final ctl = controller;
          if (ctl is _HighlightController && ctl.matches.isNotEmpty) {
            ctl.setMatches(const <TextRange>[], -1);
          }
          _touched();
        },
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: icon == null ? null : Icon(icon),
          border: const OutlineInputBorder(),
          suffixIcon: copy
              ? IconButton(
                  tooltip: tr('複製$label'),
                  icon: const Icon(Icons.copy),
                  onPressed: () => copyWithClear(context, controller.text, label),
                )
              : null,
        ),
      ),
    );
  }

  Widget _passwordField(_CredCtl c) {
    return TextField(
      controller: c.pass,
      obscureText: !c.show,
      enableSuggestions: false,
      autocorrect: false,
      enableIMEPersonalizedLearning: false,
      keyboardType: TextInputType.visiblePassword,
      onChanged: (_) {
        setState(() {}); // 更新強度提示
        _touched();
      },
      decoration: InputDecoration(
        labelText: tr('密碼'),
        helperText: c.pass.text.isEmpty
            ? null
            : tr('強度：${pwLabel(passwordStrength(c.pass.text))}'),
        prefixIcon: const Icon(Icons.password),
        border: const OutlineInputBorder(),
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: c.show ? tr('隱藏') : tr('顯示'),
              icon: Icon(c.show ? Icons.visibility_off : Icons.visibility),
              onPressed: () => setState(() => c.show = !c.show),
            ),
            IconButton(
              tooltip: tr('複製密碼'),
              icon: const Icon(Icons.copy),
              onPressed: () => copyWithClear(context, c.pass.text, tr('密碼')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _credentialCard(int i) {
    final c = _creds[i];
    final cs = Theme.of(context).colorScheme;
    final focused = _focusCred == i;
    return Container(
      key: c.cardKey,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 8),
      decoration: BoxDecoration(
        border: Border.all(
          color: focused ? cs.primary : cs.outlineVariant,
          width: focused ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                tr('帳號 ${i + 1}'),
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: cs.primary,
                    ),
              ),
              const Spacer(),
              IconButton(
                tooltip: tr('移除這組帳號'),
                icon: const Icon(Icons.close),
                onPressed: () => _removeCred(i),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _field(
                  controller: c.user,
                  label: tr('帳號 / Email'),
                  icon: Icons.person_outline,
                  copy: true,
                  keyboard: TextInputType.emailAddress,
                ),
                _passwordField(c),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => _generate(c),
                    icon: const Icon(Icons.auto_awesome, size: 18),
                    label: Text(tr('產生密碼')),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _findBar() {
    final cs = Theme.of(context).colorScheme;
    final total = _matches.length;
    final hasQuery = _findCtl.text.isNotEmpty;
    return Material(
      color: cs.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 2, 4, 2),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _findCtl,
                autofocus: _findAutofocus,
                enableIMEPersonalizedLearning: false,
                textInputAction: TextInputAction.search,
                onChanged: (_) => _runFind(),
                onSubmitted: (_) => _goto(1),
                decoration: InputDecoration(
                  hintText: tr('在這則筆記中搜尋'),
                  border: InputBorder.none,
                  isDense: true,
                ),
              ),
            ),
            if (hasQuery)
              Text(
                total == 0 ? tr('無結果') : '${_current + 1}/$total',
                style: Theme.of(context).textTheme.labelMedium,
              ),
            IconButton(
              tooltip: tr('上一個'),
              icon: const Icon(Icons.keyboard_arrow_up),
              onPressed: total > 0 ? () => _goto(-1) : null,
            ),
            IconButton(
              tooltip: tr('下一個'),
              icon: const Icon(Icons.keyboard_arrow_down),
              onPressed: total > 0 ? () => _goto(1) : null,
            ),
            IconButton(
              tooltip: tr('關閉搜尋'),
              icon: const Icon(Icons.close),
              onPressed: _closeFind,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final folderName = vault.folders
        .where((f) => f.id == _note.folderId)
        .map((f) => f.name)
        .firstOrNull;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        _debounce?.cancel();
        final messenger = ScaffoldMessenger.maybeOf(context);
        _save();
        vault.flush().then((_) {
          if (vault.lastSaveError != null) {
            messenger?.showSnackBar(SnackBar(
              content: Text(tr('儲存失敗（可能空間不足），內容尚未寫入。')),
              duration: const Duration(seconds: 8),
              action: SnackBarAction(
                label: tr('重試'),
                onPressed: () => vault.retrySave(),
              ),
            ));
          }
        });
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_isLogin ? tr('帳號密碼') : tr('筆記')),
          actions: [
            TextButton.icon(
              onPressed: _saveAndClose,
              icon: const Icon(Icons.check),
              label: Text(tr('儲存')),
            ),
            if (!_isLogin)
              IconButton(
                tooltip: _preview ? tr('回到編輯') : tr('Markdown 預覽'),
                icon: Icon(_preview ? Icons.edit_outlined : Icons.visibility_outlined),
                onPressed: () {
                  if (!_preview && _finding) _closeFind();
                  FocusScope.of(context).unfocus();
                  setState(() => _preview = !_preview);
                },
              ),
            if (!_isLogin && !_preview)
              IconButton(
                tooltip: tr('在筆記內搜尋'),
                icon: const Icon(Icons.search),
                onPressed: _finding ? _closeFind : _openFind,
              ),
            IconButton(
              tooltip: _note.pinned ? tr('取消釘選') : tr('釘選'),
              icon: Icon(_note.pinned ? Icons.push_pin : Icons.push_pin_outlined),
              onPressed: () {
                setState(() => _note.pinned = !_note.pinned);
                _touched();
              },
            ),
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'folder') {
                  _chooseFolder();
                } else if (v == 'color') {
                  _chooseColor();
                } else if (v == 'lock') {
                  _toggleLock();
                } else if (v == 'export') {
                  _export();
                } else if (v == 'delete') {
                  _delete();
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(value: 'folder', child: Text(tr('移到資料夾'))),
                PopupMenuItem(value: 'color', child: Text(tr('筆記顏色'))),
                PopupMenuItem(
                  value: 'lock',
                  child: Text(_note.locked ? tr('解除鎖定') : tr('鎖定（需輸入鎖定密碼）')),
                ),
                PopupMenuItem(value: 'export', child: Text(tr('另存新檔…'))),
                PopupMenuItem(value: 'delete', child: Text(tr('移到回收桶'))),
              ],
            ),
          ],
        ),
        body: Column(
          children: [
            if (_finding && !_isLogin) _findBar(),
            Expanded(
              child: SingleChildScrollView(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _title,
                      enableIMEPersonalizedLearning: false,
                      textInputAction: TextInputAction.next,
                      onChanged: (_) => _touched(),
                      style: Theme.of(context).textTheme.headlineSmall,
                      decoration: InputDecoration(
                        hintText: tr('標題'),
                        border: InputBorder.none,
                      ),
                    ),
                    if (folderName != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Chip(
                            avatar: const Icon(Icons.folder_outlined, size: 16),
                            label: Text(folderName),
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      ),
                    _tagsSection(),
                    if (_isLogin) ...[
                      _field(
                        controller: _site,
                        label: tr('網站 / 應用程式'),
                        icon: Icons.language,
                        copy: true,
                        keyboard: TextInputType.url,
                      ),
                      for (var i = 0; i < _creds.length; i++) _credentialCard(i),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          onPressed: _addCred,
                          icon: const Icon(Icons.add),
                          label: Text(tr('新增另一組帳號')),
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (_fields.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            tr('其他欄位'),
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ),
                      for (var i = 0; i < _fields.length; i++) _fieldCard(i),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          onPressed: _addFieldSheet,
                          icon: const Icon(Icons.add),
                          label: Text(tr('新增欄位（安全提問、PIN 碼…）')),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        key: _bodyKey,
                        controller: _body,
                        minLines: 3,
                        maxLines: null,
                        enableIMEPersonalizedLearning: false,
                        keyboardType: TextInputType.multiline,
                        onChanged: (_) => _onBodyChanged(),
                        decoration: InputDecoration(
                          labelText: tr('備註'),
                          alignLabelWithHint: true,
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.all(16),
                        ),
                      ),
                    ] else if (_preview)
                      ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 200),
                        child: MarkdownView(
                          text: _body.text,
                          onToggleTodo: (line) {
                            final nt = MdFormat.toggleTodoLine(_body.text, line);
                            if (nt == null) return;
                            setState(() {
                              _body.text = nt;
                              _lastBody = nt;
                            });
                            _touched();
                          },
                        ),
                      )
                    else
                      TextField(
                        key: _bodyKey,
                        controller: _body,
                        focusNode: _bodyFocus,
                        // 點到輸入框外面（例如格式列）不要自動收起鍵盤／失去焦點
                        onTapOutside: (_) {},
                        contextMenuBuilder: (ctx, state) =>
                            AdaptiveTextSelectionToolbar.editableText(
                          editableTextState: state,
                        ),
                        minLines: 10,
                        maxLines: null,
                        enableIMEPersonalizedLearning: false,
                        keyboardType: TextInputType.multiline,
                        onChanged: (_) => _onBodyChanged(),
                        decoration: InputDecoration(
                          hintText: tr('在這裡輸入內容…'),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(vertical: 8),
                        ),
                      ),
                    const SizedBox(height: 16),
                    Text(tr('附件'), style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 8),
                    _imageStrip(),
                    if (_inStore) ...[
                      const SizedBox(height: 24),
                      Text(
                        tr('建立：${fmtDate(_note.createdAt, full: true)}　　修改：${fmtDate(_note.updatedAt, full: true)}'),
                        style: Theme.of(context)
                            .textTheme
                            .labelSmall
                            ?.copyWith(color: cs.outline),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (!_isLogin && !_preview)
              FormatBar(
                controller: _body,
                focus: _bodyFocus,
                onChanged: _onBodyChanged,
              ),
          ],
        ),
      ),
    );
  }
}
