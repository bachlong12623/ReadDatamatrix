import 'web_zoom_stub.dart'
    if (dart.library.js_interop) 'web_zoom_web.dart' as impl;

/// Áp dụng zoom kỹ thuật số lên preview video (web).
Future<void> applyWebDigitalZoom(double scale) => impl.applyWebDigitalZoom(scale);
