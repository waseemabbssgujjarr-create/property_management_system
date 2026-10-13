// Platform-conditional File export.
// On native (Android/iOS/desktop): real dart:io.File
// On web: a stub class (never instantiated since all usages are kIsWeb-guarded)
export 'file_support_native.dart'
    if (dart.library.html) 'file_support_web.dart';
