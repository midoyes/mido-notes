import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart' show MethodChannel;

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';

import 'i18n.dart';

/// 辨識失敗（訊息可直接顯示給使用者）。
class OcrException implements Exception {
  OcrException(this.message);
  final String message;
  @override
  String toString() => message;
}

bool get ocrIsWindows => Platform.isWindows;

bool get ocrSupported => Platform.isAndroid || Platform.isIOS || Platform.isWindows;

/// Windows 可選的辨識語言：代碼 → 顯示名稱。'auto' 表示使用 Windows 使用者的語言設定。
Map<String, String> get kWinOcrLangs => <String, String>{
      'auto': tr('自動（Windows 語言設定）'),
      'zh-Hant-TW': tr('繁體中文'),
      'zh-Hans-CN': tr('簡體中文'),
      'en-US': 'English',
      'ja-JP': '日本語',
    };

String _imgExt(Uint8List b) {
  if (b.length > 4 && b[0] == 0x89 && b[1] == 0x50) return 'png';
  if (b.length > 3 && b[0] == 0xFF && b[1] == 0xD8) return 'jpg';
  if (b.length > 2 && b[0] == 0x47 && b[1] == 0x49) return 'gif';
  if (b.length > 2 && b[0] == 0x42 && b[1] == 0x4D) return 'bmp';
  return 'png';
}

/// 把圖片轉成文字。手機用 Google ML Kit（離線、內建中英文模型）；
/// Windows 用系統內建的 OCR（離線）。圖片只在本機處理，不會上傳。
///
/// Windows 的內建辨識對「拍螢幕」這類模糊、有摩爾紋的照片比較吃力，
/// 所以可以先放大並提高對比（[enhance]），淺色字深色底時可再反相（[invert]）。
Future<String> recognizeText(
  Uint8List image, {
  String winLang = 'auto',
  bool enhance = false,
  bool invert = false,
  double? maxSide,
}) async =>
    (await recognizeData(image, winLang: winLang, enhance: enhance, invert: invert, maxSide: maxSide)).plain;

/// 一個辨識出來的字（含位置），用來還原原本的排列。
class OcrWord {
  const OcrWord(this.x, this.y, this.w, this.h, this.text);
  final double x, y, w, h;
  final String text;
}

/// 辨識結果：[plain] 是引擎給的原始行；[layout] 依文字位置還原成接近圖片的欄位排列。
class OcrData {
  const OcrData(this.plain, this.words, {this.w = 0, this.h = 0});
  final String plain;
  final List<OcrWord> words;

  /// 被辨識的那張（處理後）圖片的像素寬高，字的位置都以它為準。
  final double w, h;
  OcrData withSize(double w, double h) => OcrData(plain, words, w: w, h: h);
  String get layout => words.isEmpty ? plain : layoutText(words);
}

int _dispW(String s) {
  var n = 0;
  for (final r in s.runes) {
    n += r >= 0x2E80 ? 2 : 1;
  }
  return n;
}

double _median(List<double> v) {
  final a = List<double>.from(v)..sort();
  return a[a.length ~/ 2];
}

/// 依每個字的位置排成「列」，再用空格補到對應的欄位，
/// 讓「左邊標題 : 右邊內容」這類表格或終端機畫面保持原本的排列。
String layoutText(List<OcrWord> words) {
  final ws = words.where((w) => w.text.trim().isNotEmpty && w.w > 0).toList();
  if (ws.isEmpty) return '';
  final charW = _median([for (final w in ws) w.w / _dispW(w.text)]);
  final medH = _median([for (final w in ws) w.h]);
  ws.sort((a, b) => (a.y + a.h / 2).compareTo(b.y + b.h / 2));
  final rows = <List<OcrWord>>[];
  double rowY = 0;
  for (final w in ws) {
    final yc = w.y + w.h / 2;
    if (rows.isNotEmpty && (yc - rowY).abs() <= medH * 0.6) {
      rows.last.add(w);
      rowY = (rowY * (rows.last.length - 1) + yc) / rows.last.length;
    } else {
      rows.add([w]);
      rowY = yc;
    }
  }
  final minX = ws.map((w) => w.x).reduce(math.min);
  final out = StringBuffer();
  for (final row in rows) {
    row.sort((a, b) => a.x.compareTo(b.x));
    final line = StringBuffer();
    var cur = 0;
    for (final w in row) {
      final col = ((w.x - minX) / charW).round();
      if (cur > 0 && col <= cur) {
        line.write(' ');
        cur += 1;
      } else if (col > cur) {
        line.write(' ' * (col - cur));
        cur = col;
      }
      line.write(w.text);
      cur += _dispW(w.text);
    }
    out.writeln(line.toString().trimRight());
  }
  return out.toString().trimRight();
}

Future<OcrData> recognizeData(
  Uint8List image, {
  String winLang = 'auto',
  bool enhance = false,
  bool invert = false,
  double? maxSide,
  bool ai = false,
}) async {
  if (ai && Platform.isWindows) return _aiWindows(image);
  if (ai && Platform.isAndroid) return _aiAndroid(image);
  if (Platform.isAndroid || Platform.isIOS) {
    final d = await _mlkit(image);
    final sz = await imageSize(image);
    return d.withSize(sz.width, sz.height);
  }
  if (Platform.isWindows) {
    var src = image;
    if (enhance || invert || maxSide != null) {
      try {
        src = await enhanceForOcr(image, invert: invert, contrast: enhance, maxSide: maxSide);
      } catch (_) {
        src = image;
      }
    }
    final d = await _windows(src, winLang);
    final sz = await imageSize(src);
    return d.withSize(sz.width, sz.height);
  }
  throw OcrException(tr('這個平台尚不支援圖片轉文字。'));
}

/// Windows：試多種語言與影像處理，挑辨識結果最像正常文字的。
Future<OcrData> recognizeBestWindows(Uint8List image, String lang) async {
  OcrData best = const OcrData('', []);
  double bestScore = -1;
  OcrException? lastErr;
  Future<void> tryOne(String l, bool enh, bool inv, double? maxSide) async {
    try {
      final d = await recognizeData(image, winLang: l, enhance: enh, invert: inv, maxSide: maxSide);
      final s = _ocrScore(d.plain);
      if (s > bestScore) {
        bestScore = s;
        best = d;
      }
    } on OcrException catch (e) {
      lastErr = e;
    }
  }

  // 語言：使用者選的；若是「自動」再多試英文（路徑、程式碼、英文訊息多半用英文引擎更準）。
  final langs = lang == 'auto' ? <String>['auto', 'en-US'] : <String>[lang];
  for (final l in langs) {
    await tryOne(l, false, false, null); // 原圖
    await tryOne(l, false, false, 1400); // 縮到 1400 像素
    await tryOne(l, true, false, null); // 放大＋對比
  }
  if (bestScore < 25) {
    // 還是不好：可能是深色底，試反相。
    for (final l in langs) {
      await tryOne(l, false, true, 1400);
      await tryOne(l, true, true, null);
    }
  }
  if (bestScore < 0 && lastErr != null) throw lastErr!;
  return best;
}

/// 分數：正常字元（英數、中日文）越多越好，零碎符號與過短的行扣分。
double _ocrScore(String t) {
  if (t.trim().isEmpty) return 0;
  final good = RegExp(r'[A-Za-z0-9\u3400-\u9fff]').allMatches(t).length;
  final lines = t.split('\n').where((l) => l.trim().isNotEmpty).toList();
  final short = lines.where((l) => l.trim().length <= 2).length;
  final total = t.replaceAll(RegExp(r'\s'), '').length;
  final junk = total - good;
  return good - junk * 0.5 - short * 2.0;
}

/// 放大（約 2 倍，最大邊不超過 6000 像素）、轉灰階並提高對比，回傳 PNG。
Future<Uint8List> enhanceForOcr(
  Uint8List src, {
  bool invert = false,
  bool contrast = true,
  double? maxSide,
}) async {
  final codec = await ui.instantiateImageCodec(src);
  final frame = await codec.getNextFrame();
  final img = frame.image;
  final longest = math.max(img.width, img.height);
  double scale;
  if (maxSide != null) {
    // 大張手機照片先縮小：縮小能減輕摩爾紋，文字也落在引擎最擅長的大小。
    scale = longest > maxSide ? maxSide / longest : 1.0;
  } else {
    scale = 2.0;
    if (longest * scale > 6000) scale = 6000 / longest;
    if (scale < 1.0) scale = 1.0;
  }
  final w = (img.width * scale).round();
  final h = (img.height * scale).round();
  final c = contrast ? 1.5 : 1.0; // 對比
  final sign = invert ? -1.0 : 1.0;
  final off = invert ? 128 * (1 + c) : 128 * (1 - c);
  final paint = ui.Paint()
    ..filterQuality = ui.FilterQuality.high
    ..colorFilter = ui.ColorFilter.matrix(<double>[
      sign * c * 0.299, sign * c * 0.587, sign * c * 0.114, 0, off,
      sign * c * 0.299, sign * c * 0.587, sign * c * 0.114, 0, off,
      sign * c * 0.299, sign * c * 0.587, sign * c * 0.114, 0, off,
      0, 0, 0, 1, 0,
    ]);
  final rec = ui.PictureRecorder();
  final canvas = ui.Canvas(rec);
  canvas.drawImageRect(
    img,
    ui.Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
    ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    paint,
  );
  final out = await rec.endRecording().toImage(w, h);
  final bd = await out.toByteData(format: ui.ImageByteFormat.png);
  if (bd == null) throw OcrException(tr('影像處理失敗'));
  return bd.buffer.asUint8List();
}

/// Windows：讀取剪貼簿裡的圖片（例如用 Win+Shift+S 截圖）。沒有圖片回傳 null。
Future<Uint8List?> readClipboardImage() async {
  if (!Platform.isWindows) return null;
  final dir = await _tmp();
  final stamp = DateTime.now().microsecondsSinceEpoch;
  final out = File('${dir.path}\\clip_$stamp.png');
  final ps1 = File('${dir.path}\\clip_$stamp.ps1');
  try {
    const script = r'''
param([string]$OutPath)
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$img = [System.Windows.Forms.Clipboard]::GetImage()
if ($img -ne $null) { $img.Save($OutPath, [System.Drawing.Imaging.ImageFormat]::Png); $img.Dispose() }
''';
    await ps1.writeAsBytes(<int>[0xEF, 0xBB, 0xBF, ...utf8.encode(script)], flush: true);
    await Process.run(
      'powershell.exe',
      <String>['-NoProfile', '-NonInteractive', '-STA', '-ExecutionPolicy', 'Bypass', '-File', ps1.path, '-OutPath', out.path],
    ).timeout(const Duration(seconds: 30));
    if (!await out.exists()) return null;
    return await out.readAsBytes();
  } catch (_) {
    return null;
  } finally {
    for (final f in <File>[out, ps1]) {
      try {
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
  }
}

Future<Directory> _tmp() async {
  final t = await getTemporaryDirectory();
  final d = Directory('${t.path}/mido_ocr');
  if (!await d.exists()) await d.create(recursive: true);
  return d;
}

Future<void> cleanOcrTemp() async {
  try {
    final t = await getTemporaryDirectory();
    final d = Directory('${t.path}/mido_ocr');
    if (await d.exists()) await d.delete(recursive: true);
  } catch (_) {}
}

Future<OcrData> _mlkit(Uint8List image) async {
  final dir = await _tmp();
  final f = File('${dir.path}/in_${DateTime.now().microsecondsSinceEpoch}.${_imgExt(image)}');
  await f.writeAsBytes(image, flush: true);
  // 中文辨識模型同時能辨識英文與數字
  final rec = TextRecognizer(script: TextRecognitionScript.chinese);
  try {
    final r = await rec.processImage(InputImage.fromFilePath(f.path));
    final words = <OcrWord>[];
    for (final b in r.blocks) {
      for (final l in b.lines) {
        for (final e in l.elements) {
          final bb = e.boundingBox;
          words.add(OcrWord(bb.left, bb.top, bb.width, bb.height, e.text));
        }
      }
    }
    return OcrData(r.text.trim(), words);
  } catch (e) {
    throw OcrException('${tr('辨識失敗')}：$e');
  } finally {
    await rec.close();
    try {
      await f.delete();
    } catch (_) {}
  }
}

// 以 PowerShell 呼叫 Windows 內建的 Windows.Media.Ocr（不需要額外安裝程式、不需要編譯原生程式碼）。
const String _ps = r"""
param([string]$ImagePath,[string]$OutPath,[string]$Lang)
$ErrorActionPreference = 'Stop'
function Out-Result([string]$s){ [IO.File]::WriteAllText($OutPath,$s,(New-Object Text.UTF8Encoding($false))) }
try {
  Add-Type -AssemblyName System.Runtime.WindowsRuntime
  $null = [Windows.Storage.StorageFile,Windows.Storage,ContentType=WindowsRuntime]
  $null = [Windows.Storage.Streams.IRandomAccessStream,Windows.Storage.Streams,ContentType=WindowsRuntime]
  $null = [Windows.Graphics.Imaging.BitmapDecoder,Windows.Graphics,ContentType=WindowsRuntime]
  $null = [Windows.Graphics.Imaging.SoftwareBitmap,Windows.Graphics,ContentType=WindowsRuntime]
  $null = [Windows.Media.Ocr.OcrEngine,Windows.Foundation,ContentType=WindowsRuntime]
  $null = [Windows.Media.Ocr.OcrResult,Windows.Foundation,ContentType=WindowsRuntime]
  $null = [Windows.Globalization.Language,Windows.Globalization,ContentType=WindowsRuntime]
  $asTask = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]
  function Await($op,$type){ $m=$asTask.MakeGenericMethod($type); $t=$m.Invoke($null,@($op)); $t.Wait(-1) | Out-Null; $t.Result }
  $engine = $null
  if ($Lang -eq 'auto') {
    $engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages()
    if ($engine -eq $null) { $engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromLanguage((New-Object Windows.Globalization.Language('en-US'))) }
  } else {
    $engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromLanguage((New-Object Windows.Globalization.Language($Lang)))
    if ($engine -eq $null) { Out-Result ('ERR:LANG:' + $Lang); exit 0 }
  }
  if ($engine -eq $null) { Out-Result 'ERR:NOENGINE'; exit 0 }
  $file = Await ([Windows.Storage.StorageFile]::GetFileFromPathAsync($ImagePath)) ([Windows.Storage.StorageFile])
  $stream = Await ($file.OpenAsync([Windows.Storage.FileAccessMode]::Read)) ([Windows.Storage.Streams.IRandomAccessStream])
  $decoder = Await ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)) ([Windows.Graphics.Imaging.BitmapDecoder])
  $bmp = Await ($decoder.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
  $res = Await ($engine.RecognizeAsync($bmp)) ([Windows.Media.Ocr.OcrResult])
  $lines = @()
  $words = @()
  foreach ($l in $res.Lines) {
    $lines += $l.Text
    foreach ($w in $l.Words) {
      $r = $w.BoundingRect
      $words += ([string]$r.X + "`t" + [string]$r.Y + "`t" + [string]$r.Width + "`t" + [string]$r.Height + "`t" + $w.Text)
    }
  }
  Out-Result ('OK:' + ($lines -join [Environment]::NewLine) + [Environment]::NewLine + '@@WORDS@@' + [Environment]::NewLine + ($words -join [Environment]::NewLine))
} catch {
  Out-Result ('ERR:EX:' + $_.Exception.Message)
}
""";

Future<OcrData> _windows(Uint8List image, String lang) async {
  final dir = await _tmp();
  final stamp = DateTime.now().microsecondsSinceEpoch;
  final img = File('${dir.path}\\in_$stamp.${_imgExt(image)}');
  final ps1 = File('${dir.path}\\ocr_$stamp.ps1');
  final out = File('${dir.path}\\out_$stamp.txt');
  try {
    await img.writeAsBytes(image, flush: true);
    // 加上 BOM，Windows PowerShell 才會正確讀取含中文的腳本
    await ps1.writeAsBytes(<int>[0xEF, 0xBB, 0xBF, ...utf8.encode(_ps)], flush: true);
    final p = await Process.run(
      'powershell.exe',
      <String>[
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        ps1.path,
        '-ImagePath',
        img.path,
        '-OutPath',
        out.path,
        '-Lang',
        lang,
      ],
    ).timeout(const Duration(seconds: 90));
    if (!await out.exists()) {
      throw OcrException(
        '${tr('無法執行 Windows 文字辨識')}。${p.stderr.toString().trim()}',
      );
    }
    final s = utf8.decode(await out.readAsBytes(), allowMalformed: true);
    if (s.startsWith('OK:')) {
      final body = s.substring(3);
      final i = body.indexOf('@@WORDS@@');
      final plain = (i < 0 ? body : body.substring(0, i)).trim();
      final words = <OcrWord>[];
      if (i >= 0) {
        for (final ln in body.substring(i + 9).split(RegExp(r'\r?\n'))) {
          final p = ln.split('\t');
          if (p.length < 5) continue;
          final x = double.tryParse(p[0]), y = double.tryParse(p[1]);
          final w = double.tryParse(p[2]), h = double.tryParse(p[3]);
          if (x == null || y == null || w == null || h == null) continue;
          words.add(OcrWord(x, y, w, h, p.sublist(4).join('\t')));
        }
      }
      return OcrData(plain, words);
    }
    if (s.startsWith('ERR:LANG:')) {
      throw OcrException(
        tr('這台電腦沒有安裝這個語言的文字辨識功能。\n請到「設定 → 時間與語言 → 語言與區域」加入該語言，並勾選安裝「光學字元辨識」。'),
      );
    }
    if (s.startsWith('ERR:NOENGINE')) {
      throw OcrException(
        tr('找不到可用的文字辨識語言。請到 Windows「語言與區域」設定加入語言並安裝「光學字元辨識」。'),
      );
    }
    throw OcrException('${tr('辨識失敗')}：${s.replaceFirst('ERR:EX:', '')}');
  } on OcrException {
    rethrow;
  } on ProcessException catch (e) {
    throw OcrException('${tr('無法啟動 PowerShell')}：${e.message}');
  } catch (e) {
    throw OcrException('${tr('辨識失敗')}：$e');
  } finally {
    for (final f in <File>[img, ps1, out]) {
      try {
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
  }
}

/// 依比例（0~1）裁切圖片，回傳 PNG。
Future<Uint8List> cropImage(Uint8List src, ui.Rect frac) async {
  final codec = await ui.instantiateImageCodec(src);
  final img = (await codec.getNextFrame()).image;
  final l = (frac.left * img.width).clamp(0, img.width - 1).toDouble();
  final t = (frac.top * img.height).clamp(0, img.height - 1).toDouble();
  final r = (frac.right * img.width).clamp(l + 1, img.width.toDouble()).toDouble();
  final b = (frac.bottom * img.height).clamp(t + 1, img.height.toDouble()).toDouble();
  final w = (r - l).round();
  final h = (b - t).round();
  final rec = ui.PictureRecorder();
  ui.Canvas(rec).drawImageRect(
    img,
    ui.Rect.fromLTRB(l, t, r, b),
    ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    ui.Paint()..filterQuality = ui.FilterQuality.high,
  );
  final out = await rec.endRecording().toImage(w, h);
  final bd = await out.toByteData(format: ui.ImageByteFormat.png);
  if (bd == null) throw OcrException(tr('影像處理失敗'));
  return bd.buffer.asUint8List();
}

/// 讀出圖片的像素寬高比（寬 / 高）。
Future<double> imageAspect(Uint8List src) async {
  final codec = await ui.instantiateImageCodec(src);
  final img = (await codec.getNextFrame()).image;
  return img.width / img.height;
}

/// 讀出圖片的像素大小。
Future<ui.Size> imageSize(Uint8List src) async {
  final codec = await ui.instantiateImageCodec(src);
  final img = (await codec.getNextFrame()).image;
  return ui.Size(img.width.toDouble(), img.height.toDouble());
}

// ───────────── AI 辨識（Windows）：內建的 RapidOCR（PaddleOCR 模型，離線）─────────────

const MethodChannel _aiChannel = MethodChannel('mido_notes/ocr');

/// 這個平台有沒有 AI 辨識可用（Windows、Android）。
bool get ocrHasAi => Platform.isWindows || Platform.isAndroid;

String _aiDir() => '${File(Platform.resolvedExecutable).parent.path}\\ocr';

/// 內建的官方 Python（embeddable）執行 mido_ocr.py。
String _aiPython() => '${_aiDir()}\\python\\python.exe';
String _aiScript() => '${_aiDir()}\\mido_ocr.py';

/// 這個安裝包裡有沒有 AI 辨識程式（只有 Windows 正式建置才有）。
Future<bool> aiOcrAvailable() async {
  if (Platform.isAndroid) {
    try {
      return await _aiChannel.invokeMethod<bool>('available') ?? false;
    } catch (_) {
      return false;
    }
  }
  if (!Platform.isWindows) return false;
  try {
    return await File(_aiPython()).exists() && await File(_aiScript()).exists();
  } catch (_) {
    return false;
  }
}

Future<OcrData> _aiWindows(Uint8List image) async {
  final exe = _aiPython();
  if (!await File(exe).exists() || !await File(_aiScript()).exists()) {
    throw OcrException(tr('找不到 AI 辨識程式。'));
  }
  final dir = await _tmp();
  final stamp = DateTime.now().microsecondsSinceEpoch;
  final img = File('${dir.path}\\ai_$stamp.${_imgExt(image)}');
  final out = File('${dir.path}\\ai_$stamp.json');
  try {
    await img.writeAsBytes(image, flush: true);
    final p = await Process.run(
      exe,
      <String>[_aiScript(), '--image', img.path, '--out', out.path],
      stdoutEncoding: null,
      stderrEncoding: null,
    ).timeout(const Duration(seconds: 180));
    if (!await out.exists()) {
      throw OcrException('${tr('AI 辨識失敗')}：exit ${p.exitCode}');
    }
    final map = jsonDecode(utf8.decode(await out.readAsBytes(), allowMalformed: true));
    if (map is! Map) throw OcrException(tr('AI 辨識失敗'));
    if (map['error'] != null) {
      throw OcrException('${tr('AI 辨識失敗')}：${map['error']}');
    }
    return _parseAi(map);
  } on OcrException {
    rethrow;
  } on ProcessException catch (e) {
    throw OcrException('${tr('無法啟動 AI 辨識程式')}：${e.message}');
  } catch (e) {
    throw OcrException('${tr('AI 辨識失敗')}：$e');
  } finally {
    for (final f in <File>[img, out]) {
      try {
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
  }
}

OcrData _parseAi(Map map) {
  final words = <OcrWord>[];
  final plain = <String>[];
  for (final l in (map['lines'] as List? ?? const [])) {
    if (l is! Map) continue;
    final t = (l['text'] ?? '').toString();
    if (t.trim().isEmpty) continue;
    words.add(OcrWord(
      (l['x'] as num).toDouble(),
      (l['y'] as num).toDouble(),
      (l['w'] as num).toDouble(),
      (l['h'] as num).toDouble(),
      t,
    ));
    plain.add(t);
  }
  return OcrData(
    plain.join('\n'),
    words,
    w: (map['w'] as num?)?.toDouble() ?? 0,
    h: (map['h'] as num?)?.toDouble() ?? 0,
  );
}

/// Android：Kotlin 端用 ONNX Runtime 執行 PaddleOCR 模型。
Future<OcrData> _aiAndroid(Uint8List image) async {
  final dir = await _tmp();
  final f = File('${dir.path}/ai_${DateTime.now().microsecondsSinceEpoch}.${_imgExt(image)}');
  try {
    await f.writeAsBytes(image, flush: true);
    final s = await _aiChannel
        .invokeMethod<String>('recognize', <String, dynamic>{'path': f.path})
        .timeout(const Duration(seconds: 180));
    if (s == null || s.isEmpty) throw OcrException(tr('AI 辨識失敗'));
    final map = jsonDecode(s);
    if (map is! Map) throw OcrException(tr('AI 辨識失敗'));
    return _parseAi(map);
  } on OcrException {
    rethrow;
  } catch (e) {
    throw OcrException('${tr('AI 辨識失敗')}：$e');
  } finally {
    try {
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}
