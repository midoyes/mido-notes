import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../i18n.dart';

/// 對文字欄位套用 Markdown 格式的小工具（粗體、斜體、底線、標題、清單、顏色…）。
/// 格式一律以 Markdown／簡單 HTML 標記存在文字裡，所以舊筆記、備份、另存新檔都相容。
class MdFormat {
  const MdFormat._();

  static const List<Color> palette = <Color>[
    Color(0xFFE53935), // 紅
    Color(0xFFFB8C00), // 橙
    Color(0xFFF9A825), // 黃
    Color(0xFF43A047), // 綠
    Color(0xFF1E88E5), // 藍
    Color(0xFF8E24AA), // 紫
    Color(0xFF757575), // 灰
  ];

  static String hex(Color c) =>
      // ignore: deprecated_member_use
      c.value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase();

  static final RegExp _colorSpan =
      RegExp(r'^<span style="color:#[0-9A-Fa-f]{6}">([\s\S]*)</span>$');

  static TextSelection _sel(TextEditingController c) {
    final s = c.selection;
    if (!s.isValid) {
      return TextSelection.collapsed(offset: c.text.length);
    }
    return s;
  }

  static void _set(TextEditingController c, String text, TextSelection sel) {
    c.value = TextEditingValue(text: text, selection: sel);
  }

  /// 以 [open]／[close] 包住選取文字；已包住就拿掉（切換）。沒有選取就插入一對標記。
  static void wrap(TextEditingController c, String open, String close) {
    final s = _sel(c);
    final t = c.text;
    final a = s.start, b = s.end;
    final sel = t.substring(a, b);
    if (a == b) {
      _set(c, t.replaceRange(a, b, '$open$close'),
          TextSelection.collapsed(offset: a + open.length));
      return;
    }
    // 選取內容本身帶著標記 → 拿掉
    if (sel.length >= open.length + close.length &&
        sel.startsWith(open) &&
        sel.endsWith(close)) {
      final inner = sel.substring(open.length, sel.length - close.length);
      _set(c, t.replaceRange(a, b, inner),
          TextSelection(baseOffset: a, extentOffset: a + inner.length));
      return;
    }
    // 標記在選取範圍外側 → 拿掉
    if (a >= open.length &&
        t.length - b >= close.length &&
        t.substring(a - open.length, a) == open &&
        t.substring(b, b + close.length) == close) {
      final nt = t.replaceRange(b, b + close.length, '').replaceRange(a - open.length, a, '');
      _set(c, nt,
          TextSelection(baseOffset: a - open.length, extentOffset: b - open.length));
      return;
    }
    _set(c, t.replaceRange(a, b, '$open$sel$close'),
        TextSelection(baseOffset: a + open.length, extentOffset: b + open.length));
  }

  /// 套用文字顏色；[color] 為 null 代表清除顏色。
  static void color(TextEditingController c, Color? color) {
    final s = _sel(c);
    final t = c.text;
    final a = s.start, b = s.end;
    final sel = t.substring(a, b);
    final m = _colorSpan.firstMatch(sel);
    final inner = m != null ? m.group(1)! : sel;
    if (color == null) {
      if (m == null) return;
      _set(c, t.replaceRange(a, b, inner),
          TextSelection(baseOffset: a, extentOffset: a + inner.length));
      return;
    }
    final open = '<span style="color:#${hex(color)}">';
    const close = '</span>';
    if (a == b) {
      _set(c, t.replaceRange(a, b, '$open$close'),
          TextSelection.collapsed(offset: a + open.length));
      return;
    }
    final nt = t.replaceRange(a, b, '$open$inner$close');
    _set(c, nt,
        TextSelection(baseOffset: a + open.length, extentOffset: a + open.length + inner.length));
  }

  static final RegExp _linePrefix =
      RegExp(r'^(#{1,6} |[-*+] \[[ xX]\] |[-*+] |\d+\. |> )');

  /// 對選取到的每一行設定行首格式。[kind]：h1 h2 h3 body bullet number todo quote。
  static void lines(TextEditingController c, String kind) {
    final s = _sel(c);
    final t = c.text;
    var start = s.start == 0 ? 0 : t.lastIndexOf('\n', s.start - 1) + 1;
    var endSearch = s.end;
    // 選取剛好停在下一行行首時，不算那一行
    if (s.end > s.start && s.end > 0 && t[s.end - 1] == '\n') endSearch = s.end - 1;
    var end = t.indexOf('\n', endSearch);
    if (end < 0) end = t.length;
    final block = t.substring(start, end);
    final ls = block.split('\n');

    String prefixFor(int i) {
      switch (kind) {
        case 'h1':
          return '# ';
        case 'h2':
          return '## ';
        case 'h3':
          return '### ';
        case 'bullet':
          return '- ';
        case 'number':
          return '${i + 1}. ';
        case 'todo':
          return '- [ ] ';
        case 'quote':
          return '> ';
        default:
          return '';
      }
    }

    // 每一行本來就是這個格式 → 切換成一般文字
    bool already(String l, int i) {
      final p = prefixFor(i);
      if (p.isEmpty) return false;
      if (kind == 'number') return RegExp(r'^\d+\. ').hasMatch(l);
      if (kind == 'todo') return RegExp(r'^[-*+] \[[ xX]\] ').hasMatch(l);
      if (kind == 'bullet') {
        return RegExp(r'^[-*+] ').hasMatch(l) &&
            !RegExp(r'^[-*+] \[[ xX]\] ').hasMatch(l);
      }
      return l.startsWith(p);
    }

    var allHave = true;
    for (var i = 0; i < ls.length; i++) {
      if (ls[i].trim().isEmpty) continue;
      if (!already(ls[i], i)) {
        allHave = false;
        break;
      }
    }
    final out = <String>[];
    for (var i = 0; i < ls.length; i++) {
      final l = ls[i];
      final bare = l.replaceFirst(_linePrefix, '');
      if (allHave) {
        out.add(bare);
      } else if (l.trim().isEmpty && ls.length > 1) {
        out.add(l);
      } else {
        out.add('${prefixFor(i)}$bare');
      }
    }
    final nb = out.join('\n');
    _set(c, t.replaceRange(start, end, nb),
        TextSelection.collapsed(offset: start + nb.length));
  }

  /// 在游標處插入文字（例如分隔線、程式碼區塊、連結）。
  static void insert(TextEditingController c, String text, {int? cursorBack}) {
    final s = _sel(c);
    final t = c.text;
    final nt = t.replaceRange(s.start, s.end, text);
    final pos = s.start + text.length - (cursorBack ?? 0);
    _set(c, nt, TextSelection.collapsed(offset: pos));
  }

  static final RegExp _contLine =
      RegExp(r'^(\s*)([-*+] \[[ xX]\] |[-*+] |(\d+)\. |> )(.*)$');

  /// 在清單行按 Enter 時自動接下一項；空項目再按 Enter 就結束清單。
  /// 在 onChanged 中呼叫，[before] 是變更前的文字。回傳是否有改動文字。
  static bool continueList(TextEditingController c, String before) {
    final t = c.text;
    final s = c.selection;
    if (!s.isValid || !s.isCollapsed) return false;
    if (t.length != before.length + 1) return false;
    final pos = s.baseOffset;
    if (pos < 1 || t[pos - 1] != '\n') return false;
    if (t.replaceRange(pos - 1, pos, '') != before) return false;
    final ls = pos - 1 == 0 ? 0 : t.lastIndexOf('\n', pos - 2) + 1;
    final prev = t.substring(ls, pos - 1);
    final m = _contLine.firstMatch(prev);
    if (m == null) return false;
    final indent = m.group(1)!;
    final marker = m.group(2)!;
    final rest = m.group(4)!;
    if (rest.trim().isEmpty) {
      // 空項目 → 結束清單：把這一行清空
      _set(c, t.replaceRange(ls, pos, ''), TextSelection.collapsed(offset: ls));
      return true;
    }
    String next;
    final numStr = m.group(3);
    if (numStr != null) {
      next = '$indent${int.parse(numStr) + 1}. ';
    } else if (marker.contains('[')) {
      next = '$indent${marker.substring(0, 2)}[ ] ';
    } else {
      next = '$indent$marker';
    }
    _set(c, t.replaceRange(pos, pos, next),
        TextSelection.collapsed(offset: pos + next.length));
    return true;
  }

  /// 切換第 [lineIndex] 行的待辦勾選狀態，回傳新文字；該行不是待辦就回傳 null。
  static String? toggleTodoLine(String text, int lineIndex) {
    final ls = text.replaceAll('\r\n', '\n').split('\n');
    if (lineIndex < 0 || lineIndex >= ls.length) return null;
    final m = RegExp(r'^(\s*[-*+]\s+)\[([ xX])\](\s+.*)?$').firstMatch(ls[lineIndex]);
    if (m == null) return null;
    final done = m.group(2) != ' ';
    ls[lineIndex] = '${m.group(1)}[${done ? ' ' : 'x'}]${m.group(3) ?? ''}';
    return ls.join('\n');
  }
}

/// 編輯時顯示在鍵盤上方的一排格式按鈕（像 iPhone 備忘錄）。
class FormatBar extends StatefulWidget {
  const FormatBar({super.key, required this.controller, required this.onChanged, this.focus});

  final TextEditingController controller;
  final VoidCallback onChanged;
  final FocusNode? focus;

  @override
  State<FormatBar> createState() => _FormatBarState();
}

enum _Panel { none, heading, color }

class _FormatBarState extends State<FormatBar> {
  _Panel _panel = _Panel.none;

  // 輸入框一失去焦點，選取範圍就會被清掉，所以隨時記住最後一次有效的選取範圍，
  // 按按鈕時用它，這樣即使焦點跑掉也能對正確的文字套用格式。
  TextSelection _saved = const TextSelection.collapsed(offset: 0);

  void _remember() {
    final s = widget.controller.selection;
    if (s.isValid) _saved = s;
  }

  @override
  void initState() {
    super.initState();
    _remember();
    widget.controller.addListener(_remember);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_remember);
    super.dispose();
  }

  void _do(VoidCallback f) {
    final c = widget.controller;
    if (!c.selection.isValid) {
      final max = c.text.length;
      c.selection = TextSelection(
        baseOffset: _saved.baseOffset.clamp(0, max),
        extentOffset: _saved.extentOffset.clamp(0, max),
      );
    }
    f();
    widget.focus?.requestFocus();
    widget.onChanged();
    setState(() {});
  }

  void _toggle(_Panel p) {
    setState(() => _panel = _panel == p ? _Panel.none : p);
  }

  Widget _btn(IconData icon, String tip, VoidCallback onTap, {bool on = false}) {
    final cs = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: tip,
      visualDensity: VisualDensity.compact,
      icon: Icon(icon, size: 22, color: on ? cs.primary : null),
      onPressed: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = widget.controller;
    // TextFieldTapRegion：點這一排按鈕不算「點在輸入框外面」，輸入框才不會失去焦點、
    // 鍵盤和這一排才不會在按下去的瞬間消失。
    return TextFieldTapRegion(
      child: ExcludeFocus(
      child: Material(
        color: cs.surfaceContainer,
        elevation: 3,
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_panel == _Panel.heading)
                SizedBox(
                  height: 44,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    children: [
                      for (final h in <List<String>>[
                        ['h1', tr('大標題')],
                        ['h2', tr('標題')],
                        ['h3', tr('小標題')],
                        ['body', tr('內文')],
                      ])
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                          child: ActionChip(
                            label: Text(h[1]),
                            onPressed: () => _do(() {
                              MdFormat.lines(c, h[0]);
                              _panel = _Panel.none;
                            }),
                          ),
                        ),
                    ],
                  ),
                ),
              if (_panel == _Panel.color)
                SizedBox(
                  height: 48,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    children: [
                      for (final col in MdFormat.palette)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                          child: GestureDetector(
                            onTap: () => _do(() {
                              MdFormat.color(c, col);
                              _panel = _Panel.none;
                            }),
                            child: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: col,
                                shape: BoxShape.circle,
                                border: Border.all(color: cs.outlineVariant),
                              ),
                            ),
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                        child: ActionChip(
                          label: Text(tr('清除顏色')),
                          onPressed: () => _do(() {
                            MdFormat.color(c, null);
                            _panel = _Panel.none;
                          }),
                        ),
                      ),
                    ],
                  ),
                ),
              SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  children: [
                    _btn(Icons.title, tr('標題'), () => _toggle(_Panel.heading),
                        on: _panel == _Panel.heading),
                    _btn(Icons.format_bold, tr('粗體'), () => _do(() => MdFormat.wrap(c, '**', '**'))),
                    _btn(Icons.format_italic, tr('斜體'), () => _do(() => MdFormat.wrap(c, '*', '*'))),
                    _btn(Icons.format_underlined, tr('底線'), () => _do(() => MdFormat.wrap(c, '<u>', '</u>'))),
                    _btn(Icons.strikethrough_s, tr('刪除線'), () => _do(() => MdFormat.wrap(c, '~~', '~~'))),
                    _btn(Icons.format_color_text, tr('文字顏色'), () => _toggle(_Panel.color),
                        on: _panel == _Panel.color),
                    _btn(Icons.format_list_bulleted, tr('項目符號'), () => _do(() => MdFormat.lines(c, 'bullet'))),
                    _btn(Icons.format_list_numbered, tr('數字清單'), () => _do(() => MdFormat.lines(c, 'number'))),
                    _btn(Icons.radio_button_unchecked, tr('待辦清單'), () => _do(() => MdFormat.lines(c, 'todo'))),
                    _btn(Icons.format_quote, tr('引用'), () => _do(() => MdFormat.lines(c, 'quote'))),
                    _btn(Icons.code, tr('行內程式碼'), () => _do(() => MdFormat.wrap(c, '`', '`'))),
                    _btn(Icons.data_object, tr('程式碼區塊'),
                        () => _do(() => MdFormat.insert(c, '\n```\n\n```\n', cursorBack: 5))),
                    _btn(Icons.link, tr('連結'),
                        () => _do(() => MdFormat.insert(c, '[](https://)', cursorBack: 11))),
                    _btn(Icons.horizontal_rule, tr('分隔線'), () => _do(() => MdFormat.insert(c, '\n---\n'))),
                    _btn(Icons.keyboard_hide_outlined, tr('收起鍵盤'), () {
                      FocusManager.instance.primaryFocus?.unfocus();
                      SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
                    }),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}
