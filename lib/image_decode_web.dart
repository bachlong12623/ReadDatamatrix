import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart';

import 'image_decode_result.dart';
import 'image_preprocess.dart';
import 'multi_decode_bridge.dart';

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

  await ensureMultiDecoders();

  final canvas = HTMLCanvasElement(width: w, height: h);
  final ctx = canvas.getContext('2d') as CanvasRenderingContext2D?;
  if (ctx == null) return null;

  // Thử parallel toàn ảnh trước (nhanh).
  ctx.drawImage(img, 0, 0);
  final full = ctx.getImageData(0, 0, w, h);
  final quick = await decodeImageDataParallel(full, thorough: true);
  if (quick != null) {
    return ImageDecodeResult(
      text: quick.text,
      engine: quick.engine,
      variant: 'full parallel',
    );
  }

  // Từng biến thể preprocess + decode song song.
  for (final v in buildThoroughVariants()) {
    final imageData = _renderVariant(ctx, canvas, img, w, h, v);
    if (imageData == null) continue;

    final hit = await decodeImageDataParallel(imageData, thorough: false);
    if (hit != null) {
      return ImageDecodeResult(
        text: hit.text,
        engine: hit.engine,
        variant: v.name,
      );
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

ImageData? _renderVariant(
  CanvasRenderingContext2D ctx,
  HTMLCanvasElement canvas,
  HTMLImageElement img,
  int srcW,
  int srcH,
  PreprocessVariant v,
) {
  var cropW = (srcW * v.cropScale).round().clamp(8, srcW);
  var cropH = (srcH * v.cropScale).round().clamp(8, srcH);
  final sx = ((srcW - cropW) / 2).round();
  final sy = ((srcH - cropH) / 2).round();

  final padX = (cropW * v.quietPad).round();
  final padY = (cropH * v.quietPad).round();
  var outW = cropW + padX * 2;
  var outH = cropH + padY * 2;

  if (v.upscale > 1.01) {
    outW = (outW * v.upscale).round();
    outH = (outH * v.upscale).round();
    cropW = (cropW * v.upscale).round();
    cropH = (cropH * v.upscale).round();
  }

  canvas.width = outW;
  canvas.height = outH;

  ctx.fillStyle = '#ffffff';
  ctx.fillRect(0, 0, outW.toDouble(), outH.toDouble());
  ctx.drawImage(
    img,
    sx.toDouble(),
    sy.toDouble(),
    (srcW * v.cropScale).round().toDouble(),
    (srcH * v.cropScale).round().toDouble(),
    padX.toDouble(),
    padY.toDouble(),
    cropW.toDouble(),
    cropH.toDouble(),
  );

  var data = ctx.getImageData(0, 0, outW, outH);

  if (v.niblack ||
      v.contrast != 1.0 ||
      v.brightness != 0 ||
      v.sharpen ||
      v.invert) {
    final processed = processRgba(data.data.toDart, outW, outH, v);
    final out = ImageData(outW, outH);
    final d = out.data.toDart;
    for (var i = 0; i < processed.length && i < d.length; i++) {
      d[i] = processed[i];
    }
    data = out;
  }

  return data;
}
