import 'image_decode_stub.dart'
    if (dart.library.js_interop) 'image_decode_web.dart' as impl;

/// Kết quả quét ảnh tĩnh.
class ImageDecodeResult {
  const ImageDecodeResult({required this.text, this.variant});

  final String text;
  final String? variant;
}

/// Chọn ảnh từ thư viện / file và thử nhiều pipeline decode.
Future<ImageDecodeResult?> pickAndDecodeImage() => impl.pickAndDecodeImage();
