import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class Exporter {
  static Future<void> saveCsv(String baseFileName, String content) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$baseFileName.csv');
    await file.writeAsString(content);
    await Share.shareXFiles(
      [XFile(file.path)],
      text: 'Dive History CSV Export',
      subject: 'Dive History CSV',
    );
  }

  static Future<void> saveXls(String baseFileName, String content) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$baseFileName.xls');
    await file.writeAsString(content);
    await Share.shareXFiles(
      [XFile(file.path)],
      text: 'Dive History Excel Export',
      subject: 'Dive History XLS',
    );
  }
}
