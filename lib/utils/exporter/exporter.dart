// Facade that picks the right implementation per platform (web or io).
import 'exporter_stub.dart'
    if (dart.library.html) 'exporter_web.dart'
    if (dart.library.io) 'exporter_io.dart';

export 'exporter_stub.dart';
