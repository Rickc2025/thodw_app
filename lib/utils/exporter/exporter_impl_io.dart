// Android/iOS: write to a temp file and open the system Share sheet.
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

Future<void> saveCsv(String baseName, String csv) async {
  // BOM for Excel + UTF-8
  final content = '\u{FEFF}$csv';
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$baseName.csv');
  await file.writeAsBytes(utf8.encode(content), flush: true);

  await Share.shareXFiles(
    [XFile(file.path, mimeType: 'text/csv', name: '$baseName.csv')],
    subject: 'Dive log CSV',
    text: 'Dive log export ($baseName.csv)',
  );
}

Future<void> saveXls(String baseName, String xmlXls) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$baseName.xls');
  await file.writeAsBytes(utf8.encode(xmlXls), flush: true);

  await Share.shareXFiles(
    [
      XFile(
        file.path,
        mimeType: 'application/vnd.ms-excel',
        name: '$baseName.xls',
      ),
    ],
    subject: 'Dive log Excel',
    text: 'Dive log export ($baseName.xls)',
  );
}
