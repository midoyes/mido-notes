import 'dart:math' show max;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../i18n.dart';

/// 簡易 Markdown 預覽：標題、粗體、斜體、刪除線、行內程式碼、程式碼區塊、
/// 條列、數字清單、待辦清單、引用、分隔線、連結與表格。全部離線繪製。
/// 程式碼區塊保留原本的縮排與換行，可一鍵複製；以 Tab 分隔的多行文字（從網頁複製表格
/// 常見的格式）也會顯示成表格。
class MarkdownView extends StatefulWidget {
  const MarkdownView({super.key, required this.text});

  final String text;

  @override
  State<MarkdownView> createState() => _MarkdownViewState();
}

class _MarkdownViewState extends State<MarkdownView> {
  final List<TapGestureRecognizer> _recs = <TapGestureRecognizer>[];

  static final RegExp _inline = RegExp(
    r'(\*\*(.+?)\*\*)|(~~(.+?)~~)|(`([^`]+)`)|(\[([^\]]+)\]\(([^)\s]+)\))|(\*([^*\s][^*]*?)\*)',
  );

  void _disposeRecs() {
    for (final r in _recs) {
      r.dispose();
    }
    _recs.clear();
  }

  @override
  void dispose() {
    _disposeRecs();
    super.dispose();
  }

  Future<void> _open(String url) async {
    final u = Uri.tryParse(url);
    if (u == null || (u.scheme != 'http' && u.scheme != 'https')) return;
    try {
      await launchUrl(u, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }


  // ───────── 表格 ─────────

  static final RegExp _sepCell = RegExp(r'^:?-+:?$');

  List<String> _splitRow(String line) {
    var s = line.trim();
    if (s.startsWith('|')) s = s.substring(1);
    if (s.endsWith('|') && !s.endsWith(r'\|')) s = s.substring(0, s.length - 1);
    final cells = <String>[];
    final buf = StringBuffer();
    var inCode = false;
    for (var k = 0; k < s.length; k++) {
      final c = s[k];
      if (c == r'\' && k + 1 < s.length && s[k + 1] == '|') {
        buf.write('|');
        k++;
        continue;
      }
      if (c == '`') inCode = !inCode;
      if (c == '|' && !inCode) {
        cells.add(buf.toString().trim());
        buf.clear();
        continue;
      }
      buf.write(c);
    }
    cells.add(buf.toString().trim());
    return cells;
  }

  bool _isSeparator(String line) {
    if (!line.contains('-')) return false;
    if (!line.contains('|')) return false;
    final cells = _splitRow(line);
    if (cells.isEmpty) return false;
    return cells.every(_sepCell.hasMatch);
  }

  TextAlign _alignOf(String sep) {
    final l = sep.startsWith(':');
    final r = sep.endsWith(':');
    if (l && r) return TextAlign.center;
    if (r) return TextAlign.right;
    return TextAlign.left;
  }

  Widget _tableWidget(
    List<List<String>> rows,
    List<TextAlign> aligns,
    TextStyle body,
    ColorScheme cs,
  ) {
    var cols = 0;
    for (final r in rows) {
      cols = max(cols, r.length);
    }
    final small = body.copyWith(fontSize: (body.fontSize ?? 16) - 1);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Table(
          defaultColumnWidth: const IntrinsicColumnWidth(),
          border: TableBorder.all(color: cs.outlineVariant),
          children: [
            for (var r = 0; r < rows.length; r++)
              TableRow(
                decoration: r == 0
                    ? BoxDecoration(color: cs.surfaceContainerHighest)
                    : null,
                children: [
                  for (var c = 0; c < cols; c++)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 280),
                        child: Text.rich(
                          TextSpan(
                            children: _spans(
                              c < rows[r].length
                                  ? rows[r][c].replaceAll(
                                      RegExp(r'<br\s*/?>', caseSensitive: false),
                                      '\n',
                                    )
                                  : '',
                              small,
                              cs,
                            ),
                            style: r == 0
                                ? small.copyWith(fontWeight: FontWeight.bold)
                                : small,
                          ),
                          textAlign: c < aligns.length ? aligns[c] : TextAlign.left,
                        ),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  // ───────── 程式碼區塊 ─────────

  Widget _codeBlock(String code, String lang, TextStyle body) {
    const bg = Color(0xFF1E1E1E);
    const fg = Color(0xFFD4D4D4);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 2, 4, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    lang,
                    style: const TextStyle(
                      color: Color(0xFF9E9E9E),
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                IconButton(
                  tooltip: tr('複製'),
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.copy, size: 18, color: Color(0xFF9E9E9E)),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: code));
                    if (!mounted) return;
                    ScaffoldMessenger.of(context)
                      ..hideCurrentSnackBar()
                      ..showSnackBar(
                        SnackBar(
                          duration: const Duration(seconds: 2),
                          content: Text(tr('已複製程式碼')),
                        ),
                      );
                  },
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Text(
                code,
                style: body.copyWith(
                  fontFamily: 'monospace',
                  fontSize: 13.5,
                  height: 1.4,
                  color: fg,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<InlineSpan> _spans(String s, TextStyle base, ColorScheme cs) {
    final out = <InlineSpan>[];
    var pos = 0;
    for (final m in _inline.allMatches(s)) {
      if (m.start > pos) out.add(TextSpan(text: s.substring(pos, m.start)));
      if (m.group(1) != null) {
        out.add(TextSpan(
          children: _spans(m.group(2)!, base, cs),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ));
      } else if (m.group(3) != null) {
        out.add(TextSpan(
          text: m.group(4),
          style: const TextStyle(decoration: TextDecoration.lineThrough),
        ));
      } else if (m.group(5) != null) {
        out.add(TextSpan(
          text: m.group(6),
          style: TextStyle(
            fontFamily: 'monospace',
            backgroundColor: cs.surfaceContainerHighest,
          ),
        ));
      } else if (m.group(7) != null) {
        final url = m.group(9)!;
        final rec = TapGestureRecognizer()..onTap = () => _open(url);
        _recs.add(rec);
        out.add(TextSpan(
          text: m.group(8),
          recognizer: rec,
          style: TextStyle(
            color: cs.primary,
            decoration: TextDecoration.underline,
          ),
        ));
      } else if (m.group(10) != null) {
        out.add(TextSpan(
          text: m.group(11),
          style: const TextStyle(fontStyle: FontStyle.italic),
        ));
      }
      pos = m.end;
    }
    if (pos < s.length) out.add(TextSpan(text: s.substring(pos)));
    return out;
  }

  Widget _rich(String s, TextStyle base, ColorScheme cs) =>
      Text.rich(TextSpan(children: _spans(s, base, cs), style: base));

  @override
  Widget build(BuildContext context) {
    _disposeRecs();
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final body = tt.bodyLarge ?? const TextStyle(fontSize: 16);
    final lines = widget.text.replaceAll('\r\n', '\n').split('\n');
    final children = <Widget>[];

    var i = 0;
    while (i < lines.length) {
      final line = lines[i];
      final t = line.trimRight();

      // 程式碼區塊（保留縮排與空行；結尾沒關閉就一路到最後）
      if (t.trimLeft().startsWith('```')) {
        final indent = line.length - line.trimLeft().length;
        final lang = t.trim().substring(3).trim();
        final buf = <String>[];
        i++;
        while (i < lines.length && !lines[i].trimLeft().startsWith('```')) {
          final l = lines[i];
          var cut = 0;
          while (cut < indent && cut < l.length && l[cut] == ' ') {
            cut++;
          }
          buf.add(l.substring(cut).trimRight());
          i++;
        }
        i++; // 結尾的 ```
        children.add(_codeBlock(buf.join('\n'), lang, body));
        continue;
      }

      // Markdown 表格：標題列 + 分隔列（|---|---|）+ 資料列
      if (t.contains('|') && i + 1 < lines.length && _isSeparator(lines[i + 1])) {
        final header = _splitRow(t);
        final sep = _splitRow(lines[i + 1]);
        final rows = <List<String>>[header];
        var j = i + 2;
        while (j < lines.length &&
            lines[j].trim().isNotEmpty &&
            lines[j].contains('|')) {
          rows.add(_splitRow(lines[j]));
          j++;
        }
        children.add(_tableWidget(rows, sep.map(_alignOf).toList(), body, cs));
        i = j;
        continue;
      }

      // 以 Tab 分隔的表格（從網頁複製表格通常是這種格式）
      if (t.contains('\t')) {
        final tabs = '\t'.allMatches(t).length;
        var j = i;
        final rows = <List<String>>[];
        while (j < lines.length &&
            lines[j].contains('\t') &&
            '\t'.allMatches(lines[j]).length == tabs) {
          rows.add(lines[j].split('\t').map((e) => e.trim()).toList());
          j++;
        }
        if (rows.length >= 2) {
          children.add(_tableWidget(rows, const <TextAlign>[], body, cs));
          i = j;
          continue;
        }
      }

      final h = RegExp(r'^(#{1,6})\s+(.*)$').firstMatch(t);
      if (h != null) {
        final level = h.group(1)!.length;
        final style = switch (level) {
          1 => tt.headlineMedium,
          2 => tt.headlineSmall,
          3 => tt.titleLarge,
          _ => tt.titleMedium,
        };
        children.add(Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 4),
          child: _rich(
            h.group(2)!,
            (style ?? body).copyWith(fontWeight: FontWeight.bold),
            cs,
          ),
        ));
        i++;
        continue;
      }

      if (RegExp(r'^\s*([-*_])(\s*\1){2,}\s*$').hasMatch(t)) {
        children.add(const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Divider(height: 1),
        ));
        i++;
        continue;
      }

      final q = RegExp(r'^\s*>\s?(.*)$').firstMatch(t);
      if (q != null) {
        children.add(Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.only(left: 12),
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: cs.primary, width: 3)),
          ),
          child: _rich(q.group(1)!, body.copyWith(color: cs.onSurfaceVariant), cs),
        ));
        i++;
        continue;
      }

      final todo = RegExp(r'^(\s*)[-*+]\s+\[([ xX])\]\s+(.*)$').firstMatch(t);
      if (todo != null) {
        final done = todo.group(2) != ' ';
        children.add(Padding(
          padding: EdgeInsets.only(
            left: 4.0 + todo.group(1)!.length * 8,
            top: 2,
            bottom: 2,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                done ? Icons.check_box : Icons.check_box_outline_blank,
                size: 20,
                color: done ? cs.primary : cs.outline,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _rich(
                  todo.group(3)!,
                  done
                      ? body.copyWith(
                          color: cs.outline,
                          decoration: TextDecoration.lineThrough,
                        )
                      : body,
                  cs,
                ),
              ),
            ],
          ),
        ));
        i++;
        continue;
      }

      final ul = RegExp(r'^(\s*)[-*+]\s+(.*)$').firstMatch(t);
      if (ul != null) {
        children.add(Padding(
          padding: EdgeInsets.only(
            left: 4.0 + ul.group(1)!.length * 8,
            top: 2,
            bottom: 2,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('•  ', style: body),
              Expanded(child: _rich(ul.group(2)!, body, cs)),
            ],
          ),
        ));
        i++;
        continue;
      }

      final ol = RegExp(r'^(\s*)(\d+)[.)]\s+(.*)$').firstMatch(t);
      if (ol != null) {
        children.add(Padding(
          padding: EdgeInsets.only(
            left: 4.0 + ol.group(1)!.length * 8,
            top: 2,
            bottom: 2,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${ol.group(2)}.  ', style: body),
              Expanded(child: _rich(ol.group(3)!, body, cs)),
            ],
          ),
        ));
        i++;
        continue;
      }

      if (t.trim().isEmpty) {
        children.add(const SizedBox(height: 8));
        i++;
        continue;
      }

      children.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: _rich(t, body, cs),
      ));
      i++;
    }

    if (children.isEmpty) {
      children.add(Text(tr('（沒有內容）'), style: body.copyWith(color: cs.outline)));
    }

    return SelectionArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}
