import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart';

import 'image_decode.dart';

/// zxing-wasm version — khớp mobile_scanner 7.4.
const _zxingWasmVersion = '2.1.0';

@JS('ZXingWASM.readBarcodes')
external JSPromise<JSArray<JSObject>> _wasmReadBarcodes(
  ImageData imageData,
  JSObject options,
);

@JS()
@staticInterop
class WasmReadResult {}

extension WasmReadResultExt on WasmReadResult {
  @JS('isValid')
  external bool get isValid;

  @JS('text')
  external String? get text;
}

Future<ImageDecodeResult?> pickAndDecodeImage() async {
  final input = HTMLInputElement()
    ..type = 'file'
    ..accept = 'image/*'
    ..style.display = 'none';

  document.body?.appendChild(input);

  final completer = Completer<ImageDecodeResult?>();

  void cleanup() {
    input.remove();
  }

  input.onchange = ((Event _) async {
    try {
      final files = input.files;
      if (files == null || files.length == 0) {
        completer.complete(null);
        cleanup();
        return;
      }
      final file = files.item(0);
      if (file == null) {
        completer.complete(null);
        cleanup();
        return;
      }
      final url = URL.createObjectURL(file);
      try {
        final result = await _decodeImageUrl(url);
        completer.complete(result);
      } finally {
        URL.revokeObjectURL(url);
      }
    } catch (e) {
      completer.completeError(e);
    } finally {
      cleanup();
    }
  }).toJS;

  input.click();

  return completer.future.timeout(
    const Duration(minutes: 2),
    onTimeout: () {
      cleanup();
      return null;
    },
  );
}

Future<ImageDecodeResult?> _decodeImageUrl(String url) async {
  final img = HTMLImageElement()
    ..src = url
    ..decoding = 'async';

  await _waitImageLoad(img);

  final w = img.naturalWidth;
  final h = img.naturalHeight;
  if (w <= 0 || h <= 0) return null;

  await _ensureZxingWasm();

  final canvas = HTMLCanvasElement(width: w, height: h);
  final ctx = canvas.getContext('2d') as CanvasRenderingContext2D?;
  if (ctx == null) return null;

  final variants = _buildVariants();
  for (final v in variants) {
    final imageData = _renderVariant(ctx, canvas, img, w, h, v);
    if (imageData == null) continue;

    final text = await _readDataMatrix(imageData);
    if (text != null && text.isNotEmpty) {
      return ImageDecodeResult(text: text, variant: v.name);
    }
  }

  return null;
}

Future<void> _waitImageLoad(HTMLImageElement img) {
  final c = Completer<void>();
  img.onload = ((Event _) {
    if (!c.isCompleted) c.complete();
  }).toJS;
  img.onerror = ((Event _) {
    if (!c.isCompleted) c.completeError('Image load failed');
  }).toJS;
  if (img.complete && img.naturalWidth > 0) {
    c.complete();
  }
  return c.future;
}

class _Variant {
  const _Variant({
    required this.name,
    this.quietPad = 0.12,
    this.cropScale = 1.0,
    this.contrast = 1.0,
    this.brightness = 0,
    this.sharpen = false,
    this.invert = false,
  });

  final String name;
  final double quietPad;
  final double cropScale;
  final double contrast;
  final double brightness;
  final bool sharpen;
  final bool invert;
}

List<_Variant> _buildVariants() => const [
      _Variant(name: 'gốc'),
      _Variant(name: 'quiet 18%', quietPad: 0.18),
      _Variant(name: 'quiet 25%', quietPad: 0.25),
      _Variant(name: 'quiet 35%', quietPad: 0.35),
      _Variant(name: 'contrast 1.4', contrast: 1.4),
      _Variant(name: 'contrast 1.8', contrast: 1.8),
      _Variant(name: 'tối', contrast: 1.2, brightness: -18),
      _Variant(name: 'sáng', contrast: 1.2, brightness: 18),
      _Variant(name: 'sharpen', sharpen: true, contrast: 1.15),
      _Variant(name: 'đảo màu', invert: true),
      _Variant(name: 'crop 75%', cropScale: 0.75),
      _Variant(name: 'crop 55%', cropScale: 0.55),
      _Variant(name: 'crop 40%', cropScale: 0.40),
      _Variant(name: 'crop 30% + quiet', cropScale: 0.30, quietPad: 0.25),
      _Variant(
        name: 'dot contrast',
        contrast: 1.6,
        sharpen: true,
        cropScale: 0.65,
      ),
      _Variant(
        name: 'dot invert',
        invert: true,
        cropScale: 0.55,
        contrast: 1.3,
      ),
    ];

ImageData? _renderVariant(
  CanvasRenderingContext2D ctx,
  HTMLCanvasElement canvas,
  HTMLImageElement img,
  int srcW,
  int srcH,
  _Variant v,
) {
  final cropW = (srcW * v.cropScale).round().clamp(8, srcW);
  final cropH = (srcH * v.cropScale).round().clamp(8, srcH);
  final sx = ((srcW - cropW) / 2).round();
  final sy = ((srcH - cropH) / 2).round();

  final padX = (cropW * v.quietPad).round();
  final padY = (cropH * v.quietPad).round();
  final outW = cropW + padX * 2;
  final outH = cropH + padY * 2;

  canvas.width = outW;
  canvas.height = outH;

  ctx.fillStyle = '#ffffff';
  ctx.fillRect(0, 0, outW.toDouble(), outH.toDouble());
  ctx.drawImage(
    img,
    sx.toDouble(),
    sy.toDouble(),
    cropW.toDouble(),
    cropH.toDouble(),
    padX.toDouble(),
    padY.toDouble(),
    cropW.toDouble(),
    cropH.toDouble(),
  );

  var data = ctx.getImageData(0, 0, outW, outH);
  if (v.contrast != 1.0 || v.brightness != 0 || v.sharpen || v.invert) {
    data = _processImageData(data, v);
  }

  return data;
}

ImageData _processImageData(ImageData src, _Variant v) {
  final out = ImageData(src.width, src.height);
  final s = src.data.toDart;
  final d = out.data.toDart;
  final factor = v.contrast;
  final bias = 128 * (1 - factor) + v.brightness;

  for (var i = 0; i < s.length; i += 4) {
    var r = s[i].toDouble();
    var g = s[i + 1].toDouble();
    var b = s[i + 2].toDouble();

    if (v.sharpen) {
      final lum = 0.299 * r + 0.587 * g + 0.114 * b;
      final edge = (lum - 128) * 0.15;
      r = (r + edge).clamp(0, 255);
      g = (g + edge).clamp(0, 255);
      b = (b + edge).clamp(0, 255);
    }

    r = (r * factor + bias).clamp(0, 255);
    g = (g * factor + bias).clamp(0, 255);
    b = (b * factor + bias).clamp(0, 255);

    if (v.invert) {
      r = 255 - r;
      g = 255 - g;
      b = 255 - b;
    }

    d[i] = r.round();
    d[i + 1] = g.round();
    d[i + 2] = b.round();
    d[i + 3] = s[i + 3];
  }

  return out;
}

Future<void> _ensureZxingWasm() async {
  final hasWasm = globalContext.has('ZXingWASM');
  if (hasWasm) return;

  await _loadScript(
    'https://cdn.jsdelivr.net/npm/zxing-wasm@$_zxingWasmVersion/dist/iife/reader/index.js',
  );

  for (var i = 0; i < 50; i++) {
    if (globalContext.has('ZXingWASM')) return;
    await Future<void>.delayed(const Duration(milliseconds: 60));
  }

  throw StateError('Không tải được zxing-wasm.');
}

Future<void> _loadScript(String url) {
  final completer = Completer<void>();
  final script = HTMLScriptElement()
    ..src = url
    ..async = true
    ..onload = ((Event _) => completer.complete()).toJS
    ..onerror =
        ((Event _) => completer.completeError('Script load failed: $url')).toJS;
  document.head?.appendChild(script);
  return completer.future;
}

Future<String?> _readDataMatrix(ImageData imageData) async {
  final options = JSObject();
  options.setProperty('formats'.toJS, JSArray.from(['DataMatrix'.toJS]));
  options.setProperty('tryHarder'.toJS, true.toJS);
  options.setProperty('tryRotate'.toJS, true.toJS);
  options.setProperty('tryInvert'.toJS, true.toJS);
  options.setProperty('tryDenoise'.toJS, true.toJS);
  options.setProperty('tryDownscale'.toJS, true.toJS);

  final jsResults = await _wasmReadBarcodes(imageData, options).toDart;

  for (final item in jsResults.toDart) {
    final valid = item.getProperty('isValid'.toJS);
    if (valid != true.toJS && valid != true) continue;
    final textVal = item.getProperty('text'.toJS);
    if (textVal is JSString) {
      final s = textVal.toDart;
      if (s.isNotEmpty) return s;
    }
  }

  return null;
}
