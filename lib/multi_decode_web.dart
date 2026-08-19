import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart';

import 'multi_decode.dart';

@JS('ReadDatamatrixMultiDecoder.decodeParallel')
external JSPromise<JSObject?> _jsDecodeParallel(
  ImageData imageData,
  JSObject options,
);

@JS('ReadDatamatrixMultiDecoder.ensureZxing')
external JSPromise<JSAny?> _jsEnsureZxing();

@JS('ReadDatamatrixMultiDecoder.ensureRxing')
external JSPromise<JSAny?> _jsEnsureRxing();

Future<void> ensureMultiDecoders() async {
  try {
    await _jsEnsureZxing().toDart;
    await _jsEnsureRxing().toDart;
  } catch (_) {
    // rxing optional
  }
}

Future<MultiDecodeHit?> decodeImageDataParallel(
  Object imageData, {
  bool thorough = false,
}) async {
  final opts = JSObject();
  opts.setProperty('thorough'.toJS, thorough.toJS);

  final hit = await _jsDecodeParallel(imageData as ImageData, opts).toDart;
  if (hit == null) return null;

  final textVal = hit.getProperty('text'.toJS);
  if (textVal is! JSString) return null;
  final text = textVal.toDart;
  if (text.isEmpty) return null;

  final engineVal = hit.getProperty('engine'.toJS);
  final engine = engineVal is JSString ? engineVal.toDart : 'unknown';

  return MultiDecodeHit(text: text, engine: engine);
}
