/// 簡單的 CSV 解析（RFC 4180）：支援雙引號、引號內的逗號與換行、`""` 跳脫、UTF-8 BOM。
List<List<String>> parseCsv(String input) {
  var text = input;
  if (text.startsWith('﻿')) text = text.substring(1);

  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var inQuotes = false;
  var i = 0;
  final n = text.length;

  void endRow() {
    row.add(field.toString());
    field.clear();
    // 略過空白行
    if (row.length > 1 || row.first.isNotEmpty) rows.add(row);
    row = <String>[];
  }

  while (i < n) {
    final ch = text[i];
    if (inQuotes) {
      if (ch == '"') {
        if (i + 1 < n && text[i + 1] == '"') {
          field.write('"');
          i += 2;
          continue;
        }
        inQuotes = false;
        i++;
        continue;
      }
      field.write(ch);
      i++;
      continue;
    }
    if (ch == '"') {
      inQuotes = true;
      i++;
    } else if (ch == ',') {
      row.add(field.toString());
      field.clear();
      i++;
    } else if (ch == '\r' || ch == '\n') {
      if (ch == '\r' && i + 1 < n && text[i + 1] == '\n') i++;
      i++;
      endRow();
    } else {
      field.write(ch);
      i++;
    }
  }
  if (field.isNotEmpty || row.isNotEmpty) endRow();
  return rows;
}
