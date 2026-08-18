import 'ios_camera_tune_stub.dart'
    if (dart.library.js_interop) 'ios_camera_tune_web.dart' as impl;

/// Tinh chỉnh camera web (iPhone Air / Safari).
Future<void> tuneIosSafariCamera({double zoomScale = 1.0}) =>
    impl.tuneIosSafariCamera(zoomScale: zoomScale);
