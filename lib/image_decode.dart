import 'image_decode_result.dart';
import 'image_decode_stub.dart'
    if (dart.library.js_interop) 'image_decode_web.dart' as impl;

export 'image_decode_result.dart';

/// Chọn ảnh từ thư viện / file và thử nhiều pipeline decode song song.
Future<ImageDecodeResult?> pickAndDecodeImage() => impl.pickAndDecodeImage();
