// Web: trigger browser download via Blob + <a download>.
import 'dart:convert';
import 'dart:html' as html;

Future<void> saveCsv(String baseName, String csv) async {
  // Add BOM so Excel opens UTF‑8 properly.
  final content = '\u{FEFF}$csv';
  final bytes = utf8.encode(content);
  _downloadBytes('$baseName.csv', 'text/csv;charset=utf-8', bytes);
}

Future<void> saveXls(String baseName, String xmlXls) async {
  // Excel 97–2003 XML Spreadsheet (.xls)
  final bytes = utf8.encode(xmlXls);
  _downloadBytes(
    '$baseName.xls',
    'application/vnd.ms-excel;charset=utf-8',
    bytes,
  );
}

void _downloadBytes(String filename, String mimeType, List<int> bytes) {
  final blob = html.Blob([bytes], mimeType);
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)..download = filename;

  anchor.style.display = 'none';
  html.document.body?.append(anchor);
  anchor.click();
  anchor.remove();

  html.Url.revokeObjectUrl(url);
}
