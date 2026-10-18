import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../i18n.dart';

/// 簡易 Markdown 預覽：標題、粗體、斜體、刪除線、行內程式碼、程式碼區塊、
/// 條列、數字清單、待辦清單、引用、分隔線與連結。全部離線繪製。
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

      // 程式碼區塊
      if (t.trimLeft().startsWith('```')) {
        final buf = <String>[];
        i++;
        while (i < lines.length && !lines[i].trimLeft().startsWith('```')) {
          buf.add(lines[i]);
          i++;
        }
        i++; // 結尾的 ```
        children.add(Container(
          width: double.infinity,
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Text(
              buf.join('\n'),
              style: body.copyWith(fontFamily: 'monospace', fontSize: 14),
            ),
          ),
        ));
        continue;
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
