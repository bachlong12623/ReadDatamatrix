import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

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

  void onChange(Event _) {
    unawaited(_handleFilePick(input, completer, cleanup));
  }

  input.onchange = onChange.toJS;
  input.click();

  return completer.future.timeout(
    const Duration(minutes: 2),
    onTimeout: () {
      cleanup();
      return null;
    },
  );
}

Future<void> _handleFilePick(
  HTMLInputElement input,
  Completer<ImageDecodeResult?> completer,
  void Function() cleanup,
) async {
  try {
    final files = input.files;
    if (files == null || files.length == 0) {
      completer.complete(null);
      return;
    }
    final file = files.item(0);
    if (file == null) {
      completer.complete(null);
      return;
    }
    final url = URL.createObjectURL(file);
    try {
      final result = await _decodeImageUrl(url);
      completer.complete(result);
    } finally {
      URL.revokeObjectURL(url);
    }
  } catch (e, st) {
    if (!completer.isCompleted) {
      completer.completeError(e, st);
    }
  } finally {
    cleanup();
  }
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

  final canvas = HTMLCanvasElement()
    ..width = w
    ..height = h;
  final ctx = canvas.getContext('2d') as CanvasRenderingContext2D?;
  if (ctx == null) return null;

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

ImageData _newImageData(int width, int height) =>
    ImageData(width.toJS, height.toJS);

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

  ctx.fillStyle = '#ffffff'.toJS;
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
    final rgba = data.data.toDart;
    final processed = processRgba(
      Uint8List.fromList(rgba),
      outW,
      outH,
      v,
    );
    final out = _newImageData(outW, outH);
    final d = out.data.toDart;
    for (var i = 0; i < processed.length && i < d.length; i++) {
      d[i] = processed[i];
    }
    data = out;
  }

  return data;
}
