import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../i18n.dart';
import '../ocr.dart';
import 'ocr_select.dart';

class OcrOutcome {
  const OcrOutcome(this.text, this.keepImage);
  final String text;
  final bool keepImage;
}

/// 圖片轉文字視窗：辨識後顯示可編輯的文字，確認後回傳要插入筆記的內容。
/// [offerKeepImage]：拍照／選圖辨識時，詢問是否同時把圖片存成附件。
Future<OcrOutcome?> showOcrDialog(
  BuildContext context,
  Uint8List image, {
  bool offerKeepImage = false,
}) {
  return showDialog<OcrOutcome>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _OcrDialog(image: image, offerKeepImage: offerKeepImage),
  );
}

class _OcrDialog extends StatefulWidget {
  const _OcrDialog({required this.image, required this.offerKeepImage});

  final Uint8List image;
  final bool offerKeepImage;

  @override
  State<_OcrDialog> createState() => _OcrDialogState();
}

class _OcrDialogState extends State<_OcrDialog> {
  final TextEditingController _text = TextEditingController();
  bool _busy = true;
  String? _error;
  bool _keep = false;
  String _lang = 'auto';
  bool _auto = true; // Windows：自動試多種處理並挑最好的
  bool _enhance = false; // Windows：放大並提高對比
  bool _invert = false; // Windows：淺色字深色底時反相
  int _run = 0;
  late Uint8List _img = widget.image; // 目前要辨識的圖（可能是裁切後的）
  bool _cropped = false;
  bool _layout = true; // 依位置還原排列（欄位對齊）
  OcrData? _data;

  @override
  void initState() {
    super.initState();
    _text.addListener(() {
      if (mounted) setState(() {});
    });
    _recognize();
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _recognize() async {
    final my = ++_run;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final d = (ocrIsWindows && _auto)
          ? await recognizeBestWindows(_img, _lang)
          : await recognizeData(
              _img,
              winLang: _lang,
              enhance: _enhance,
              invert: _invert,
            );
      if (!mounted || my != _run) return;
      _data = d;
      final t = _layout ? d.layout : d.plain;
      setState(() {
        _text.text = t;
        _busy = false;
        if (t.isEmpty) _error = tr('沒有辨識到文字。可以換一張更清楚、光線充足的照片再試。');
      });
    } on OcrException catch (e) {
      if (!mounted || my != _run) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted || my != _run) return;
      setState(() {
        _busy = false;
        _error = '$e';
      });
    }
  }

  /// 有欄位對齊的內容用程式碼區塊包起來，筆記檢視時才會維持等寬排列。
  String _outText() {
    final t = _text.text.trim();
    if (_layout && RegExp(r'\S {2,}\S').hasMatch(t) && !t.contains('```')) {
      return '```\n$t\n```';
    }
    return t;
  }

  Future<void> _selectOnImage() async {
    final d = _data;
    if (d == null || d.words.isEmpty || d.w <= 0) return;
    final t = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => OcrSelectScreen(image: _img, data: d)),
    );
    if (t == null || t.isEmpty || !mounted) return;
    setState(() => _text.text = t);
  }

  Future<void> _crop() async {
    final r = await Navigator.of(context).push<Rect>(
      MaterialPageRoute(builder: (_) => _CropScreen(image: widget.image)),
    );
    if (r == null || !mounted) return;
    try {
      _img = await cropImage(widget.image, r);
      _cropped = true;
    } catch (_) {
      return;
    }
    _recognize();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final win = ocrIsWindows;
    return AlertDialog(
      title: Text(tr('圖片轉文字')),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (win)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Text(tr('辨識語言')),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButton<String>(
                          isExpanded: true,
                          value: _lang,
                          items: [
                            for (final e in kWinOcrLangs.entries)
                              DropdownMenuItem(value: e.key, child: Text(e.value)),
                          ],
                          onChanged: _busy
                              ? null
                              : (v) {
                                  if (v == null) return;
                                  _lang = v;
                                  _recognize();
                                },
                        ),
                      ),
                    ],
                  ),
                ),
              if (win)
                Wrap(
                  spacing: 8,
                  children: [
                    FilterChip(
                      label: Text(tr('自動（試多種處理）')),
                      selected: _auto,
                      onSelected: _busy
                          ? null
                          : (v) {
                              _auto = v;
                              _recognize();
                            },
                    ),
                    FilterChip(
                      label: Text(tr('加強影像')),
                      selected: !_auto && _enhance,
                      onSelected: _busy
                          ? null
                          : (v) {
                              _auto = false;
                              _enhance = v;
                              _recognize();
                            },
                    ),
                    FilterChip(
                      label: Text(tr('反相（深色底）')),
                      selected: !_auto && _invert,
                      onSelected: _busy
                          ? null
                          : (v) {
                              _auto = false;
                              _invert = v;
                              _recognize();
                            },
                    ),
                  ],
                ),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Wrap(
                  spacing: 8,
                  children: [
                    ActionChip(
                      avatar: const Icon(Icons.touch_app_outlined, size: 18),
                      label: Text(tr('在圖上選取文字')),
                      onPressed: (_busy || (_data?.words.isEmpty ?? true)) ? null : _selectOnImage,
                    ),
                    ActionChip(
                      avatar: const Icon(Icons.crop, size: 18),
                      label: Text(tr('框選要辨識的範圍')),
                      onPressed: _busy ? null : _crop,
                    ),
                    if (_cropped)
                      ActionChip(
                        label: Text(tr('用整張圖')),
                        onPressed: _busy
                            ? null
                            : () {
                                _img = widget.image;
                                _cropped = false;
                                _recognize();
                              },
                      ),
                  ],
                ),
              ),
              Wrap(
                children: [
                  FilterChip(
                    label: Text(tr('保留排列（欄位對齊）')),
                    selected: _layout,
                    onSelected: _busy
                        ? null
                        : (v) {
                            setState(() {
                              _layout = v;
                              final d = _data;
                              if (d != null) _text.text = v ? d.layout : d.plain;
                            });
                          },
                  ),
                ],
              ),
              if (_busy)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 3)),
                      const SizedBox(width: 12),
                      Text(tr('辨識中…')),
                    ],
                  ),
                )
              else ...[
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(_error!, style: TextStyle(color: cs.error, fontSize: 13)),
                  ),
                TextField(
                  controller: _text,
                  style: _layout
                      ? const TextStyle(fontFamily: 'Consolas', fontFamilyFallback: ['Menlo', 'monospace'], fontSize: 13)
                      : null,
                  minLines: 6,
                  maxLines: 14,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    hintText: tr('辨識結果（可以直接修改錯字）'),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  tr('辨識在這台裝置上離線完成，圖片不會上傳。結果可能有錯字，請自行檢查。'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (widget.offerKeepImage)
                  SwitchListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(tr('同時把這張照片存成附件')),
                    value: _keep,
                    onChanged: (v) => setState(() => _keep = v),
                  ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('取消'))),
        if (!_busy && _text.text.isNotEmpty)
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: _text.text));
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(tr('已複製文字'))),
              );
            },
            child: Text(tr('複製')),
          ),
        FilledButton(
          onPressed: (_busy || _text.text.trim().isEmpty)
              ? null
              : () => Navigator.pop(context, OcrOutcome(_outText(), _keep)),
          child: Text(tr('插入到筆記')),
        ),
      ],
    );
  }
}

/// 框選範圍：在圖片上拖曳出一個矩形，按「確定」回傳比例座標。
class _CropScreen extends StatefulWidget {
  const _CropScreen({required this.image});
  final Uint8List image;

  @override
  State<_CropScreen> createState() => _CropScreenState();
}

class _CropScreenState extends State<_CropScreen> {
  double? _aspect;
  Offset? _a;
  Offset? _b;
  Size? _size;

  @override
  void initState() {
    super.initState();
    imageAspect(widget.image).then((v) {
      if (mounted) setState(() => _aspect = v);
    });
  }

  Rect? _frac(Size s) {
    if (_a == null || _b == null) return null;
    final r = Rect.fromPoints(_a!, _b!);
    if (r.width < 8 || r.height < 8) return null;
    return Rect.fromLTRB(
      (r.left / s.width).clamp(0.0, 1.0),
      (r.top / s.height).clamp(0.0, 1.0),
      (r.right / s.width).clamp(0.0, 1.0),
      (r.bottom / s.height).clamp(0.0, 1.0),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('框選要辨識的範圍')),
        actions: [
          TextButton(
            onPressed: () => setState(() {
              _a = null;
              _b = null;
            }),
            child: Text(tr('重選')),
          ),
        ],
      ),
      body: _aspect == null
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: AspectRatio(
                aspectRatio: _aspect!,
                child: LayoutBuilder(
                  builder: (ctx, box) {
                    final size = Size(box.maxWidth, box.maxHeight);
                    _size = size;
                    return GestureDetector(
                      onPanStart: (d) => setState(() {
                        _a = d.localPosition;
                        _b = d.localPosition;
                      }),
                      onPanUpdate: (d) => setState(() => _b = d.localPosition),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.memory(widget.image, fit: BoxFit.fill),
                          if (_a != null && _b != null)
                            Positioned.fromRect(
                              rect: Rect.fromPoints(_a!, _b!),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.blue.withOpacity(0.15),
                                  border: Border.all(color: Colors.blue, width: 2),
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('取消'))),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () {
                  final r = _size == null ? null : _frac(_size!);
                  if (r == null) return;
                  Navigator.pop(context, r);
                },
                child: Text(tr('確定')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
