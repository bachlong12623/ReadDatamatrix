import 'dart:typed_data';

import 'package:read_datamatrix/image_preprocess.dart';
import 'package:test/test.dart';

void main() {
  test('buildThoroughVariants includes niblack and upscale', () {
    final names = buildThoroughVariants().map((v) => v.name).toSet();
    expect(names, contains('niblack'));
    expect(names, contains('upscale 2×'));
  });

  test('processRgba invert flips pixels', () {
    const src = [100, 120, 140, 255];
    final out = processRgba(
      Uint8List.fromList(src),
      1,
      1,
      const PreprocessVariant(name: 'inv', invert: true),
    );
    expect(out[0], 155);
    expect(out[1], 135);
    expect(out[2], 115);
  });

  test('niblack produces binary values', () {
    final src = Uint8List(16);
    for (var i = 0; i < 16; i += 4) {
      src[i] = i < 8 ? 40 : 200;
      src[i + 1] = src[i];
      src[i + 2] = src[i];
      src[i + 3] = 255;
    }
    final out = processRgba(
      src,
      2,
      2,
      const PreprocessVariant(name: 'nb', niblack: true),
    );
    expect(out.every((v) => v == 0 || v == 255 || v == 255 /* alpha */), isTrue);
  });
}
