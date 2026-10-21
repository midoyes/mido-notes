import 'dart:convert';
import 'dart:typed_data';

/// 極簡 ZIP 寫入器（不壓縮、只存放），不需要額外套件。
/// 檔名使用 UTF-8（支援中文），Windows 檔案總管與手機的檔案管理員都能開啟。
class ZipWriter {
  final List<_Entry> _entries = <_Entry>[];

  static final List<int> _table = _makeTable();

  static List<int> _makeTable() {
    final t = List<int>.filled(256, 0);
    for (var n = 0; n < 256; n++) {
      var c = n;
      for (var k = 0; k < 8; k++) {
        c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1);
      }
      t[n] = c;
    }
    return t;
  }

  static int crc32(Uint8List data) {
    var c = 0xFFFFFFFF;
    for (final b in data) {
      c = _table[(c ^ b) & 0xFF] ^ (c >> 8);
    }
    return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
  }

  void add(String name, Uint8List data, {DateTime? time}) {
    _entries.add(_Entry(name, data, time ?? DateTime.now()));
  }

  Uint8List build() {
    final out = BytesBuilder(copy: false);
    final central = BytesBuilder(copy: false);
    var offset = 0;
    for (final e in _entries) {
      final nameBytes = utf8.encode(e.name);
      final crc = crc32(e.data);
      final t = _dosTime(e.time);
      final d = _dosDate(e.time);

      final local = ByteData(30);
      local.setUint32(0, 0x04034B50, Endian.little);
      local.setUint16(4, 20, Endian.little); // 版本
      local.setUint16(6, 0x0800, Endian.little); // UTF-8 檔名
      local.setUint16(8, 0, Endian.little); // 不壓縮
      local.setUint16(10, t, Endian.little);
      local.setUint16(12, d, Endian.little);
      local.setUint32(14, crc, Endian.little);
      local.setUint32(18, e.data.length, Endian.little);
      local.setUint32(22, e.data.length, Endian.little);
      local.setUint16(26, nameBytes.length, Endian.little);
      local.setUint16(28, 0, Endian.little);
      out.add(local.buffer.asUint8List());
      out.add(nameBytes);
      out.add(e.data);

      final cd = ByteData(46);
      cd.setUint32(0, 0x02014B50, Endian.little);
      cd.setUint16(4, 20, Endian.little);
      cd.setUint16(6, 20, Endian.little);
      cd.setUint16(8, 0x0800, Endian.little);
      cd.setUint16(10, 0, Endian.little);
      cd.setUint16(12, t, Endian.little);
      cd.setUint16(14, d, Endian.little);
      cd.setUint32(16, crc, Endian.little);
      cd.setUint32(20, e.data.length, Endian.little);
      cd.setUint32(24, e.data.length, Endian.little);
      cd.setUint16(28, nameBytes.length, Endian.little);
      cd.setUint16(30, 0, Endian.little);
      cd.setUint16(32, 0, Endian.little);
      cd.setUint16(34, 0, Endian.little);
      cd.setUint16(36, 0, Endian.little);
      cd.setUint32(38, 0, Endian.little);
      cd.setUint32(42, offset, Endian.little);
      central.add(cd.buffer.asUint8List());
      central.add(nameBytes);

      offset += 30 + nameBytes.length + e.data.length;
    }
    final cdBytes = central.toBytes();
    out.add(cdBytes);
    final end = ByteData(22);
    end.setUint32(0, 0x06054B50, Endian.little);
    end.setUint16(8, _entries.length, Endian.little);
    end.setUint16(10, _entries.length, Endian.little);
    end.setUint32(12, cdBytes.length, Endian.little);
    end.setUint32(16, offset, Endian.little);
    out.add(end.buffer.asUint8List());
    return out.toBytes();
  }

  static int _dosTime(DateTime t) =>
      (t.hour << 11) | (t.minute << 5) | (t.second ~/ 2);

  static int _dosDate(DateTime t) =>
      (((t.year - 1980).clamp(0, 127)) << 9) | (t.month << 5) | t.day;
}

class _Entry {
  _Entry(this.name, this.data, this.time);
  final String name;
  final Uint8List data;
  final DateTime time;
}
