import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../app_state.dart';
import 'common.dart';
import 'export_note.dart';
import '../i18n.dart';

/// 顯示加密儲存的圖片（讀檔後在記憶體中解密）。
class EncryptedImage extends StatefulWidget {
  const EncryptedImage({
    super.key,
    required this.id,
    this.fit = BoxFit.cover,
    this.cacheWidth,
  });

  final String id;
  final BoxFit fit;
  final int? cacheWidth;

  @override
  State<EncryptedImage> createState() => _EncryptedImageState();
}

class _EncryptedImageState extends State<EncryptedImage> {
  late Future<Uint8List?> _future;

  @override
  void initState() {
    super.initState();
    _future = vault.loadImage(widget.id);
  }

  @override
  void didUpdateWidget(covariant EncryptedImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id) {
      _future = vault.loadImage(widget.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        final bytes = snap.data;
        if (bytes == null) {
          return const Center(child: Icon(Icons.broken_image_outlined));
        }
        return Image.memory(
          bytes,
          fit: widget.fit,
          cacheWidth: widget.cacheWidth,
          gaplessPlayback: true,
        );
      },
    );
  }
}

/// 全螢幕檢視圖片；按右上角垃圾桶並確認後，會回傳 true 表示要刪除。
class ImageViewerScreen extends StatelessWidget {
  const ImageViewerScreen({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: tr('另存圖片'),
            icon: const Icon(Icons.save_alt),
            onPressed: () => saveAttachmentAs(context, id),
          ),
          IconButton(
            tooltip: tr('移除圖片'),
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              final ok = await confirmDialog(
                context,
                title: tr('移除圖片'),
                message: tr('要從這則筆記移除這張圖片嗎？'),
                confirmText: tr('移除'),
                danger: true,
              );
              if (ok && context.mounted) Navigator.pop(context, true);
            },
          ),
        ],
      ),
      body: Center(
        child: InteractiveViewer(
          maxScale: 6,
          child: EncryptedImage(id: id, fit: BoxFit.contain),
        ),
      ),
    );
  }
}
