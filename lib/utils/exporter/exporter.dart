// Facade that routes to the right implementation per platform.
import 'exporter_impl_stub.dart'
    if (dart.library.html) 'exporter_impl_web.dart'
    if (dart.library.io) 'exporter_impl_io.dart'
    as impl;

class Exporter {
  static Future<void> saveCsv(String baseName, String csv) =>
      impl.saveCsv(baseName, csv);

  static Future<void> saveXls(String baseName, String xmlXls) =>
      impl.saveXls(baseName, xmlXls);
}
