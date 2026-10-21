import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../i18n.dart';
import 'media_utils.dart';

class RecordResult {
  const RecordResult(this.bytes, this.ext);
  final Uint8List bytes;
  final String ext;
}

/// 錄音視窗：開始／停止，顯示時間。回傳錄好的音訊資料，取消則回傳 null。
class RecordDialog extends StatefulWidget {
  const RecordDialog({super.key});

  @override
  State<RecordDialog> createState() => _RecordDialogState();
}

class _RecordDialogState extends State<RecordDialog> {
  static const int _maxSeconds = 10 * 60;

  final AudioRecorder _rec = AudioRecorder();
  Timer? _timer;
  int _sec = 0;
  bool _recording = false;
  bool _busy = false;
  String? _error;
  String _ext = 'm4a';
  String? _path;

  @override
  void dispose() {
    _timer?.cancel();
    _rec.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (!await _rec.hasPermission()) {
        setState(() {
          _busy = false;
          _error = tr('沒有麥克風權限，請到系統設定允許後再試。');
        });
        return;
      }
      AudioEncoder enc = AudioEncoder.aacLc;
      if (!await _rec.isEncoderSupported(enc)) enc = AudioEncoder.wav;
      _ext = enc == AudioEncoder.wav ? 'wav' : 'm4a';
      final dir = await getTemporaryDirectory();
      _path = '${dir.path}/mido_rec_${DateTime.now().millisecondsSinceEpoch}.$_ext';
      await _rec.start(
        enc == AudioEncoder.wav
            ? const RecordConfig(encoder: AudioEncoder.wav, sampleRate: 16000, numChannels: 1)
            : const RecordConfig(encoder: AudioEncoder.aacLc),
        path: _path!,
      );
      _sec = 0;
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _sec++);
        if (_sec >= _maxSeconds) _stop();
      });
      setState(() {
        _recording = true;
        _busy = false;
      });
    } catch (e) {
      setState(() {
        _busy = false;
        _error = '$e';
      });
    }
  }

  Future<void> _stop() async {
    if (!_recording) return;
    _timer?.cancel();
    setState(() => _busy = true);
    try {
      final p = await _rec.stop() ?? _path;
      if (p == null) {
        if (mounted) Navigator.pop(context);
        return;
      }
      final f = File(p);
      final len = await f.length();
      if (len > kMaxMediaBytes) {
        try {
          await f.delete();
        } catch (_) {}
        if (mounted) {
          setState(() {
            _recording = false;
            _busy = false;
            _error = tr('錄音檔太大（超過 30 MB），沒有儲存。');
          });
        }
        return;
      }
      final bytes = await f.readAsBytes();
      try {
        await f.delete(); // 錄音時系統留下的是未加密暫存檔，讀完立刻刪除
      } catch (_) {}
      if (mounted) Navigator.pop(context, RecordResult(bytes, _ext));
    } catch (e) {
      if (mounted) {
        setState(() {
          _recording = false;
          _busy = false;
          _error = '$e';
        });
      }
    }
  }

  Future<void> _cancel() async {
    _timer?.cancel();
    try {
      if (_recording) await _rec.stop();
      if (_path != null) {
        final f = File(_path!);
        if (await f.exists()) await f.delete();
      }
    } catch (_) {}
    if (mounted) Navigator.pop(context);
  }

  String _fmt(int s) =>
      '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: Text(tr('錄音')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Icon(
              _recording ? Icons.mic : Icons.mic_none,
              size: 56,
              color: _recording ? cs.error : cs.outline,
            ),
            const SizedBox(height: 8),
            Text(_fmt(_sec), style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 4),
            Text(
              _recording ? tr('錄音中…') : tr('按下開始錄音（最長 10 分鐘）'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: cs.error, fontSize: 13)),
            ],
          ],
        ),
        actions: [
          TextButton(onPressed: _busy ? null : _cancel, child: Text(tr('取消'))),
          if (!_recording)
            FilledButton.icon(
              onPressed: _busy ? null : _start,
              icon: const Icon(Icons.fiber_manual_record),
              label: Text(tr('開始')),
            )
          else
            FilledButton.icon(
              onPressed: _busy ? null : _stop,
              icon: const Icon(Icons.stop),
              label: Text(tr('停止並儲存')),
            ),
        ],
      ),
    );
  }
}
