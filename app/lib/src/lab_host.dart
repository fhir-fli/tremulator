/// What a lab run needs from the platform it runs on: its arguments, its
/// log, its keys, its stop sign and its exit. The Linux app uses files and
/// the process (lab_host_io.dart); the browser build (E1, Chrome in the lab)
/// uses the page's address and the lab helper beside it (lab_host_web.dart).
library;

export 'lab_host_io.dart' if (dart.library.js_interop) 'lab_host_web.dart';
