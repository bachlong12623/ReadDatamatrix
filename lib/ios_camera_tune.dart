import 'ios_camera_tune_stub.dart'
    if (dart.library.js_interop) 'ios_camera_tune_web.dart' as impl;

/// Khóa zoom ~1x + playsinline cho camera web (iPhone Air / Safari).
Future<void> tuneIosSafariCamera() => impl.tuneIosSafariCamera();
