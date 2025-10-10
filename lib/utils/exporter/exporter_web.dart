import 'dart:convert' show utf8;
import 'dart:typed_data';
import 'dart:html' as html;

class Exporter {
  static Future<void> saveCsv(String baseFileName, String content) async {
    _download(utf8.encode(content), '$baseFileName.csv', 'text/csv');
  }

  static Future<void> saveXls(String baseFileName, String content) async {
    _download(
      utf8.encode(content),
      '$baseFileName.xls',
      'application/vnd.ms-excel',
    );
  }

  static void _download(List<int> bytes, String filename, String mime) {
    final data = Uint8List.fromList(bytes);
    final blob = html.Blob([data], mime);
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.AnchorElement(href: url)
      ..download = filename
      ..style.display = 'none';
    html.document.body!.append(anchor);
    anchor.click();
    anchor.remove();
    html.Url.revokeObjectUrl(url);
  }
}
