import 'dart:math' as math;
import 'dart:typed_data';

/// Biến thể tiền xử lý ảnh trước khi decode.
class PreprocessVariant {
  const PreprocessVariant({
    required this.name,
    this.quietPad = 0.12,
    this.cropScale = 1.0,
    this.contrast = 1.0,
    this.brightness = 0,
    this.sharpen = false,
    this.invert = false,
    this.niblack = false,
    this.upscale = 1.0,
  });

  final String name;
  final double quietPad;
  final double cropScale;
  final double contrast;
  final double brightness;
  final bool sharpen;
  final bool invert;
  final bool niblack;
  final double upscale;
}

/// Danh sách biến thể cho decode ảnh tĩnh (thorough).
List<PreprocessVariant> buildThoroughVariants() => const [
      PreprocessVariant(name: 'gốc'),
      PreprocessVariant(name: 'quiet 18%', quietPad: 0.18),
      PreprocessVariant(name: 'quiet 25%', quietPad: 0.25),
      PreprocessVariant(name: 'quiet 35%', quietPad: 0.35),
      PreprocessVariant(name: 'contrast 1.4', contrast: 1.4),
      PreprocessVariant(name: 'contrast 1.8', contrast: 1.8),
      PreprocessVariant(name: 'tối', contrast: 1.2, brightness: -18),
      PreprocessVariant(name: 'sáng', contrast: 1.2, brightness: 18),
      PreprocessVariant(name: 'sharpen', sharpen: true, contrast: 1.15),
      PreprocessVariant(name: 'niblack', niblack: true),
      PreprocessVariant(name: 'đảo màu', invert: true),
      PreprocessVariant(name: 'upscale 2×', upscale: 2.0),
      PreprocessVariant(name: 'crop 75%', cropScale: 0.75),
      PreprocessVariant(name: 'crop 55%', cropScale: 0.55),
      PreprocessVariant(name: 'crop 40%', cropScale: 0.40),
      PreprocessVariant(
        name: 'dot niblack crop',
        niblack: true,
        cropScale: 0.65,
        contrast: 1.2,
      ),
      PreprocessVariant(
        name: 'dot invert',
        invert: true,
        cropScale: 0.55,
        contrast: 1.3,
      ),
    ];

/// Xử lý RGBA buffer — trả về buffer mới cùng kích thước.
Uint8List processRgba(
  Uint8List src,
  int width,
  int height,
  PreprocessVariant v,
) {
  final out = Uint8List.fromList(src);
  final factor = v.contrast;
  final bias = 128 * (1 - factor) + v.brightness;

  if (v.niblack) {
    return _niblackRgba(out, width, height);
  }

  for (var i = 0; i < out.length; i += 4) {
    var r = out[i].toDouble();
    var g = out[i + 1].toDouble();
    var b = out[i + 2].toDouble();

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

    out[i] = r.round();
    out[i + 1] = g.round();
    out[i + 2] = b.round();
  }

  return out;
}

Uint8List _niblackRgba(Uint8List src, int width, int height) {
  const window = 15;
  const k = -0.2;
  final gray = Float32List(width * height);

  for (var i = 0, p = 0; i < src.length; i += 4, p++) {
    gray[p] = 0.299 * src[i] + 0.587 * src[i + 1] + 0.114 * src[i + 2];
  }

  final out = Uint8List.fromList(src);
  final half = window ~/ 2;

  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      var sum = 0.0;
      var sumSq = 0.0;
      var count = 0;
      for (var dy = -half; dy <= half; dy++) {
        for (var dx = -half; dx <= half; dx++) {
          final nx = x + dx;
          final ny = y + dy;
          if (nx < 0 || ny < 0 || nx >= width || ny >= height) continue;
          final v = gray[ny * width + nx];
          sum += v;
          sumSq += v * v;
          count++;
        }
      }
      final mean = sum / count;
      final std = math.sqrt(math.max(0, sumSq / count - mean * mean));
      final threshold = mean + k * std;
      final lum = gray[y * width + x];
      final bin = lum < threshold ? 0 : 255;
      final idx = (y * width + x) * 4;
      out[idx] = bin;
      out[idx + 1] = bin;
      out[idx + 2] = bin;
    }
  }

  return out;
}
