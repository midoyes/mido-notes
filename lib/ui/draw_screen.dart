import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../i18n.dart';

class _Stroke {
  _Stroke(this.color, this.width, this.pts, {this.highlighter = false});

  final Color color;
  final double width;
  final List<Offset> pts;
  final bool highlighter;
}

Path _smoothPath(List<Offset> p) {
  final path = Path();
  if (p.isEmpty) return path;
  path.moveTo(p[0].dx, p[0].dy);
  if (p.length == 1) {
    path.lineTo(p[0].dx + 0.01, p[0].dy);
    return path;
  }
  for (var i = 1; i < p.length - 1; i++) {
    final mid = Offset((p[i].dx + p[i + 1].dx) / 2, (p[i].dy + p[i + 1].dy) / 2);
    path.quadraticBezierTo(p[i].dx, p[i].dy, mid.dx, mid.dy);
  }
  path.lineTo(p.last.dx, p.last.dy);
  return path;
}

void _paintStrokes(Canvas canvas, Size size, List<_Stroke> strokes) {
  canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
  for (final s in strokes) {
    final paint = Paint()
      ..color = s.highlighter ? s.color.withValues(alpha: 0.35) : s.color
      ..style = PaintingStyle.stroke
      ..strokeCap = s.highlighter ? StrokeCap.butt : StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = s.width
      ..isAntiAlias = true;
    canvas.drawPath(_smoothPath(s.pts), paint);
  }
}

class _Painter extends CustomPainter {
  _Painter(this.strokes, this.rev);

  final List<_Stroke> strokes;
  final int rev;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    _paintStrokes(canvas, size, strokes);
  }

  @override
  bool shouldRepaint(covariant _Painter old) => old.rev != rev;
}

/// 手寫／繪圖畫面：多種粗細、顏色，螢光筆、橡皮擦、復原／重做。
/// 按「完成」會回傳 PNG 圖片資料，由呼叫端以圖片附件加密儲存。
class DrawScreen extends StatefulWidget {
  const DrawScreen({super.key});

  @override
  State<DrawScreen> createState() => _DrawScreenState();
}

enum _Tool { pen, highlighter, eraser }

class _DrawScreenState extends State<DrawScreen> {
  static const List<Color> _colors = <Color>[
    Color(0xFF000000),
    Color(0xFF616161),
    Color(0xFFE53935),
    Color(0xFFFB8C00),
    Color(0xFFF9A825),
    Color(0xFF43A047),
    Color(0xFF1E88E5),
    Color(0xFF8E24AA),
    Color(0xFF6D4C41),
  ];
  static const List<double> _widths = <double>[2, 5, 10];

  final List<_Stroke> _strokes = <_Stroke>[];
  final List<_Stroke> _redo = <_Stroke>[];
  _Stroke? _current;
  int _rev = 0;
  Size _size = const Size(300, 400);

  Color _color = _colors[0];
  int _wIdx = 1;
  _Tool _tool = _Tool.pen;

  double get _penWidth {
    final w = _widths[_wIdx];
    switch (_tool) {
      case _Tool.highlighter:
        return w * 3;
      case _Tool.eraser:
        return w * 4;
      case _Tool.pen:
        return w;
    }
  }

  void _down(PointerDownEvent e) {
    final c = _tool == _Tool.eraser ? Colors.white : _color;
    _current = _Stroke(c, _penWidth, <Offset>[e.localPosition],
        highlighter: _tool == _Tool.highlighter);
    _redo.clear();
    setState(() {
      _strokes.add(_current!);
      _rev++;
    });
  }

  void _move(PointerMoveEvent e) {
    final c = _current;
    if (c == null) return;
    setState(() {
      c.pts.add(e.localPosition);
      _rev++;
    });
  }

  void _up(PointerEvent e) {
    _current = null;
  }

  void _undo() {
    if (_strokes.isEmpty) return;
    setState(() {
      _redo.add(_strokes.removeLast());
      _rev++;
    });
  }

  void _redoStroke() {
    if (_redo.isEmpty) return;
    setState(() {
      _strokes.add(_redo.removeLast());
      _rev++;
    });
  }

  Future<void> _clear() async {
    if (_strokes.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('清除全部？')),
        content: Text(tr('整張畫布會被清空。')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('取消'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('清除'))),
        ],
      ),
    );
    if (ok != true) return;
    setState(() {
      _strokes.clear();
      _redo.clear();
      _rev++;
    });
  }

  Future<void> _done() async {
    if (_strokes.isEmpty) {
      Navigator.pop(context);
      return;
    }
    final scale = _size.longestSide * 2 > 3000 ? 3000 / _size.longestSide : 2.0;
    final w = (_size.width * scale).round().clamp(1, 4096);
    final h = (_size.height * scale).round().clamp(1, 4096);
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    canvas.scale(scale);
    _paintStrokes(canvas, _size, _strokes);
    final img = await rec.endRecording().toImage(w, h);
    final bd = await img.toByteData(format: ui.ImageByteFormat.png);
    if (!mounted) return;
    if (bd == null) {
      Navigator.pop(context);
      return;
    }
    Navigator.pop<Uint8List>(context, bd.buffer.asUint8List());
  }

  Future<bool> _confirmLeave() async {
    if (_strokes.isEmpty) return true;
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('放棄這張手寫？')),
        content: Text(tr('尚未儲存的內容會消失。')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('繼續畫'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('放棄'))),
        ],
      ),
    );
    return r == true;
  }

  Widget _toolBtn(IconData icon, String tip, _Tool t) {
    final cs = Theme.of(context).colorScheme;
    final on = _tool == t;
    return IconButton(
      tooltip: tip,
      icon: Icon(icon, color: on ? cs.primary : null),
      style: on ? IconButton.styleFrom(backgroundColor: cs.primaryContainer) : null,
      onPressed: () => setState(() => _tool = t),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        if (await _confirmLeave()) nav.pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(tr('手寫')),
          actions: [
            IconButton(
              tooltip: tr('復原'),
              icon: const Icon(Icons.undo),
              onPressed: _strokes.isEmpty ? null : _undo,
            ),
            IconButton(
              tooltip: tr('重做'),
              icon: const Icon(Icons.redo),
              onPressed: _redo.isEmpty ? null : _redoStroke,
            ),
            IconButton(
              tooltip: tr('清除全部'),
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: _strokes.isEmpty ? null : _clear,
            ),
            TextButton.icon(
              onPressed: _done,
              icon: const Icon(Icons.check),
              label: Text(tr('完成')),
            ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: Container(
                margin: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: cs.outlineVariant),
                ),
                child: LayoutBuilder(
                  builder: (context, box) {
                    _size = Size(box.maxWidth, box.maxHeight);
                    return Listener(
                      behavior: HitTestBehavior.opaque,
                      onPointerDown: _down,
                      onPointerMove: _move,
                      onPointerUp: _up,
                      onPointerCancel: _up,
                      child: RepaintBoundary(
                        child: CustomPaint(
                          size: Size.infinite,
                          painter: _Painter(_strokes, _rev),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            Material(
              color: cs.surfaceContainer,
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      height: 52,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        children: [
                          _toolBtn(Icons.edit, tr('筆'), _Tool.pen),
                          _toolBtn(Icons.highlight, tr('螢光筆'), _Tool.highlighter),
                          _toolBtn(Icons.auto_fix_normal, tr('橡皮擦'), _Tool.eraser),
                          const SizedBox(width: 12),
                          for (var i = 0; i < _widths.length; i++)
                            InkResponse(
                              onTap: () => setState(() => _wIdx = i),
                              child: Container(
                                width: 44,
                                height: 44,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _wIdx == i ? cs.primaryContainer : null,
                                ),
                                child: Container(
                                  width: 6.0 + _widths[i] * 1.6,
                                  height: 6.0 + _widths[i] * 1.6,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: cs.onSurface,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    SizedBox(
                      height: 48,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        children: [
                          for (final col in _colors)
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 8),
                              child: GestureDetector(
                                onTap: () => setState(() {
                                  _color = col;
                                  if (_tool == _Tool.eraser) _tool = _Tool.pen;
                                }),
                                child: Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: col,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: _color == col && _tool != _Tool.eraser
                                          ? cs.primary
                                          : cs.outlineVariant,
                                      width: _color == col && _tool != _Tool.eraser ? 3 : 1,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
