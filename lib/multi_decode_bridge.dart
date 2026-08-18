import 'multi_decode_stub.dart'
    if (dart.library.js_interop) 'multi_decode_web.dart' as impl;

export 'multi_decode.dart';

Future<MultiDecodeHit?> decodeImageDataParallel(
  Object imageData, {
  bool thorough = false,
}) =>
    impl.decodeImageDataParallel(imageData, thorough: thorough);

Future<void> ensureMultiDecoders() => impl.ensureMultiDecoders();
