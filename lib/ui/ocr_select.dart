import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../i18n.dart';
import '../ocr.dart';

/// 在圖片上選取要複製的文字：點單字切換選取，或拖曳框選一塊範圍
/// （從已選取的字開始拖曳＝取消選取）。回傳選到的文字（照原本位置排列）；「複製」則留在本畫面。
class OcrSelectScreen extends StatefulWidget {
  const OcrSelectScreen({super.key, required this.image, required this.data});
  final Uint8List image;
  final OcrData data;

  @override
  State<OcrSelectScreen> createState() => _OcrSelectScreenState();
}

class _OcrSelectScreenState extends State<OcrSelectScreen> {
  final Set<int> _sel = <int>{};
  Offset? _a;
  Offset? _b;
  bool _erase = false;
  Size _size = Size.zero;

  List<OcrWord> get _words => widget.data.words;

  /// 單字在畫面上的矩形（辨識座標 → 畫面座標）。
  Rect _rect(OcrWord w) {
    final dw = widget.data.w <= 0 ? 1.0 : widget.data.w;
    final dh = widget.data.h <= 0 ? 1.0 : widget.data.h;
    return Rect.fromLTWH(
      w.x / dw * _size.width,
      w.y / dh * _size.height,
      w.w / dw * _size.width,
      w.h / dh * _size.height,
    );
  }

  int? _hit(Offset p) {
    int? best;
    for (var i = 0; i < _words.length; i++) {
      if (_rect(_words[i]).inflate(3).contains(p)) best = i;
    }
    return best;
  }

  void _dragEnd() {
    final a = _a, b = _b;
    if (a != null && b != null) {
      final r = Rect.fromPoints(a, b);
      if (r.width < 6 && r.height < 6) {
        final h = _hit(b);
        if (h != null) {
          _sel.contains(h) ? _sel.remove(h) : _sel.add(h);
        }
      } else {
        for (var i = 0; i < _words.length; i++) {
          final wr = _rect(_words[i]);
          final core = wr.deflate(wr.shortestSide * 0.15);
          if (r.overlaps(core)) {
            _erase ? _sel.remove(i) : _sel.add(i);
          }
        }
      }
    }
    setState(() {
      _a = null;
      _b = null;
    });
  }

  String _selectedText() {
    final list = <OcrWord>[for (final i in _sel) _words[i]];
    return list.isEmpty ? '' : layoutText(list);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dw = widget.data.w, dh = widget.data.h;
    final aspect = (dw > 0 && dh > 0) ? dw / dh : 1.0;
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('在圖上選取文字')),
        actions: [
          TextButton(
            onPressed: () => setState(() => _sel.addAll(List<int>.generate(_words.length, (i) => i))),
            child: Text(tr('全選')),
          ),
          TextButton(onPressed: () => setState(_sel.clear), child: Text(tr('清除'))),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              tr('點單字選取，或拖曳框選一塊範圍（從已選的字開始拖曳＝取消選取）'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: aspect,
                child: LayoutBuilder(
                  builder: (ctx, box) {
                    _size = Size(box.maxWidth, box.maxHeight);
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanStart: (d) {
                        final h = _hit(d.localPosition);
                        setState(() {
                          _erase = h != null && _sel.contains(h);
                          _a = d.localPosition;
                          _b = d.localPosition;
                        });
                      },
                      onPanUpdate: (d) => setState(() => _b = d.localPosition),
                      onPanEnd: (_) => _dragEnd(),
                      onPanCancel: () => setState(() {
                        _a = null;
                        _b = null;
                      }),
                      onTapUp: (d) {
                        final h = _hit(d.localPosition);
                        if (h == null) return;
                        setState(() => _sel.contains(h) ? _sel.remove(h) : _sel.add(h));
                      },
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.memory(widget.image, fit: BoxFit.fill, gaplessPlayback: true),
                          CustomPaint(
                            painter: _BoxPainter(
                              rects: [for (final w in _words) _rect(w)],
                              selected: _sel,
                              drag: (_a != null && _b != null) ? Rect.fromPoints(_a!, _b!) : null,
                              erase: _erase,
                              accent: cs.primary,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(child: Text('${tr('已選取')} ${_sel.length} / ${_words.length}')),
              OutlinedButton(
                onPressed: _sel.isEmpty
                    ? null
                    : () async {
                        await Clipboard.setData(ClipboardData(text: _selectedText()));
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(tr('已複製')), duration: const Duration(seconds: 1)),
                        );
                      },
                child: Text(tr('複製')),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _sel.isEmpty ? null : () => Navigator.pop(context, _selectedText()),
                child: Text(tr('帶回結果')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BoxPainter extends CustomPainter {
  _BoxPainter({
    required this.rects,
    required this.selected,
    required this.drag,
    required this.erase,
    required this.accent,
  });
  final List<Rect> rects;
  final Set<int> selected;
  final Rect? drag;
  final bool erase;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.orange.withOpacity(0.55);
    final fill = Paint()..color = accent.withOpacity(0.38);
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = accent;
    for (var i = 0; i < rects.length; i++) {
      if (selected.contains(i)) {
        canvas.drawRect(rects[i], fill);
        canvas.drawRect(rects[i], edge);
      } else {
        canvas.drawRect(rects[i], line);
      }
    }
    final d = drag;
    if (d != null) {
      final c = erase ? Colors.red : Colors.blue;
      canvas.drawRect(d, Paint()..color = c.withOpacity(0.15));
      canvas.drawRect(
        d,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = c,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BoxPainter old) => true;
}
