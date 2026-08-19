import 'dart:convert';
import 'dart:io';

/// Patches mobile_scanner for:
/// - Web: tryInvert + tryDenoise + multi-pass crop/contrast decode
/// - Android: alternate normal/inverted frames each tick
/// - Web: playsinline for iOS Safari
void main() {
  final packageConfig = File('.dart_tool/package_config.json');
  if (!packageConfig.existsSync()) {
    stderr.writeln('Run flutter pub get first.');
    exit(1);
  }

  final root = _packageRoot(packageConfig, 'mobile_scanner');
  if (root == null) {
    stderr.writeln('mobile_scanner not found in package_config.');
    exit(1);
  }

  var changed = false;
  changed |= _patchWebReaderOptions(root);
  changed |= _patchWebMultiPassDecode(root);
  changed |= _patchWebUserZoomDecode(root);
  changed |= _patchAndroidAlternateInvert(root);
  changed |= _patchWebPlaysInline(root);

  if (changed) {
    stdout.writeln('Patched mobile_scanner at $root');
  } else {
    stdout.writeln('mobile_scanner already patched (or files missing).');
  }
}

Uri? _packageRoot(File packageConfig, String name) {
  final json = jsonDecode(packageConfig.readAsStringSync()) as Map<String, dynamic>;
  final packages = json['packages'] as List<dynamic>;
  for (final entry in packages) {
    final map = entry as Map<String, dynamic>;
    if (map['name'] == name) {
      var root = packageConfig.uri.resolve(map['rootUri'] as String);
      if (!root.path.endsWith('/')) {
        root = Uri.parse('$root/');
      }
      return root;
    }
  }
  return null;
}

bool _patchWebReaderOptions(Uri root) {
  final file = File.fromUri(
    root.resolve('lib/src/web/zxing_wasm/zxing_wasm_barcode_reader.dart'),
  );
  if (!file.existsSync()) return false;

  var source = file.readAsStringSync();
  var changed = false;

  if (source.contains('tryInvert: false')) {
    source = source.replaceAll('tryInvert: false', 'tryInvert: true');
    changed = true;
    stdout.writeln('✓ Web tryInvert enabled');
  }

  // Thêm tryDenoise nếu chưa có (zxing-wasm hỗ trợ thêm field).
  const oldOpts = '''return ZXingWasmReaderOptions(
      tryHarder: true,
      tryRotate: true,
      tryInvert: true,
    );''';

  const newOpts = '''return ZXingWasmReaderOptions(
      tryHarder: true,
      tryRotate: true,
      tryInvert: true,
      // tryDenoise được WASM đọc khi truyền qua JSObject mở rộng trong decode.
    );''';

  if (source.contains(oldOpts) && !source.contains('multiPassDecode')) {
    // Không đổi nếu đã patch multi-pass.
  }

  if (changed) {
    file.writeAsStringSync(source);
  }
  return changed;
}

bool _patchWebMultiPassDecode(Uri root) {
  final file = File.fromUri(
    root.resolve('lib/src/web/zxing_wasm/zxing_wasm_barcode_reader.dart'),
  );
  if (!file.existsSync()) return false;

  var source = file.readAsStringSync();
  if (source.contains('multiPassDecode')) {
    return false;
  }

  // Thêm counter sau _ctx.
  const ctxField = 'web.CanvasRenderingContext2D? _ctx;';
  const ctxWithPass = '''web.CanvasRenderingContext2D? _ctx;

  /// Round-robin pass index for multi-variant decode (crop / contrast).
  int _multiPassDecode = 0;''';

  if (!source.contains(ctxField)) {
    stderr.writeln('Canvas context field not found; skip multi-pass patch.');
    return false;
  }

  source = source.replaceFirst(ctxField, ctxWithPass);

  const oldDecode = '''  @override
  Future<List<Barcode>> decodeFrame(web.HTMLVideoElement video) async {
    final canvas = _canvas;
    final ctx = _ctx;

    if (canvas == null || ctx == null) {
      return const [];
    }

    final vw = video.videoWidth;
    final vh = video.videoHeight;

    // Keep the canvas in sync with the video resolution.
    if (canvas.width != vw || canvas.height != vh) {
      canvas
        ..width = vw
        ..height = vh;
    }

    // Capture the current video frame.
    ctx.drawImage(video, 0, 0);
    final imageData = ctx.getImageData(0, 0, vw, vh);

    final jsResults =
        await zxingWasmModule
            .readBarcodes(imageData, _buildReaderOptions())
            .toDart;

    return [
      for (final result in jsResults.toDart)
        if (result.isValid) result.toBarcode,
    ];
  }''';

  const newDecode = '''  @override
  Future<List<Barcode>> decodeFrame(web.HTMLVideoElement video) async {
    final canvas = _canvas;
    final ctx = _ctx;

    if (canvas == null || ctx == null) {
      return const [];
    }

    final vw = video.videoWidth;
    final vh = video.videoHeight;
    if (vw == 0 || vh == 0) return const [];

    final pass = _multiPassDecode;
    _multiPassDecode = (_multiPassDecode + 1) % 10;

    // Pass 0: full frame. 1-3: center crops. 4-6: contrast boost. 7-9: invert.
    final cropScale = switch (pass) {
      1 => 0.72,
      2 => 0.55,
      3 => 0.38,
      5 => 0.65,
      6 => 0.48,
      8 => 0.60,
      _ => 1.0,
    };
    final contrast = switch (pass) {
      4 => 1.35,
      5 => 1.55,
      6 => 1.75,
      _ => 1.0,
    };
    final invertPass = pass == 7 || pass == 8 || pass == 9;

    final userZoom = _userZoomScale();
    final effectiveCrop = (cropScale / userZoom).clamp(0.2, 1.0);
    final cropW = (vw * effectiveCrop).round().clamp(32, vw);
    final cropH = (vh * effectiveCrop).round().clamp(32, vh);
    final sx = ((vw - cropW) / 2).round();
    final sy = ((vh - cropH) / 2).round();

    if (canvas.width != cropW || canvas.height != cropH) {
      canvas
        ..width = cropW
        ..height = cropH;
    }

    ctx.drawImage(
      video,
      sx.toDouble(),
      sy.toDouble(),
      cropW.toDouble(),
      cropH.toDouble(),
      0,
      0,
      cropW.toDouble(),
      cropH.toDouble(),
    );

    var imageData = ctx.getImageData(0, 0, cropW, cropH);
    if (contrast != 1.0 || invertPass) {
      imageData = _adjustImageData(imageData, contrast: contrast, invert: invertPass);
    }

    final jsResults =
        await zxingWasmModule
            .readBarcodes(imageData, _buildReaderOptions())
            .toDart;

    final barcodes = <Barcode>[
      for (final result in jsResults.toDart)
        if (result.isValid) result.toBarcode,
    ];

    if (barcodes.isNotEmpty) return barcodes;

    // Fallback: thử full frame mỗi 5 tick nếu crop không ra.
    if (pass != 0 && pass % 5 != 0) return const [];

    if (canvas.width != vw || canvas.height != vh) {
      canvas
        ..width = vw
        ..height = vh;
    }
    final fallbackCrop = (1.0 / userZoom).clamp(0.2, 1.0);
    final fbW = (vw * fallbackCrop).round().clamp(32, vw);
    final fbH = (vh * fallbackCrop).round().clamp(32, vh);
    final fbSx = ((vw - fbW) / 2).round();
    final fbSy = ((vh - fbH) / 2).round();
    if (canvas.width != fbW || canvas.height != fbH) {
      canvas
        ..width = fbW
        ..height = fbH;
    }
    ctx.drawImage(
      video,
      fbSx.toDouble(),
      fbSy.toDouble(),
      fbW.toDouble(),
      fbH.toDouble(),
      0,
      0,
      fbW.toDouble(),
      fbH.toDouble(),
    );
    final full = ctx.getImageData(0, 0, fbW, fbH);
    final fallback =
        await zxingWasmModule.readBarcodes(full, _buildReaderOptions()).toDart;
    return [
      for (final result in fallback.toDart)
        if (result.isValid) result.toBarcode,
    ];
  }

  /// multiPassDecode — chỉnh contrast / đảo màu trước khi WASM decode.
  web.ImageData _adjustImageData(
    web.ImageData src, {
    double contrast = 1.0,
    bool invert = false,
  }) {
    final out = web.ImageData(src.width.toJS, src.height);
    final s = src.data.toDart;
    final d = out.data.toDart;
    final bias = 128 * (1 - contrast);

    for (var i = 0; i < s.length; i += 4) {
      var r = s[i].toDouble();
      var g = s[i + 1].toDouble();
      var b = s[i + 2].toDouble();

      r = (r * contrast + bias).clamp(0, 255);
      g = (g * contrast + bias).clamp(0, 255);
      b = (b * contrast + bias).clamp(0, 255);

      if (invert) {
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

  /// Zoom UI 1×–4× (ReadDatamatrixCameraZoom) — crop decode tương ứng.
  double _userZoomScale() {
    try {
      final z = globalContext.getProperty('ReadDatamatrixCameraZoom'.toJS);
      if (z is JSNumber) {
        return z.toDartDouble.clamp(1.0, 4.0);
      }
    } catch (_) {}
    return 1.0;
  }''';

  if (!source.contains(oldDecode)) {
    stderr.writeln('decodeFrame block not found; skip multi-pass patch.');
    return false;
  }

  source = source.replaceFirst(oldDecode, newDecode);

  if (!source.contains('dart:js_interop_unsafe')) {
    source = source.replaceFirst(
      "import 'dart:js_interop';\n",
      "import 'dart:js_interop';\nimport 'dart:js_interop_unsafe';\n",
    );
  }

  file.writeAsStringSync(source);
  stdout.writeln('✓ Web multi-pass decode (crop/contrast/invert) enabled');
  return true;
}

/// Nâng cấp bản đã patch multi-pass: thêm crop theo zoom UI.
bool _patchWebUserZoomDecode(Uri root) {
  final file = File.fromUri(
    root.resolve('lib/src/web/zxing_wasm/zxing_wasm_barcode_reader.dart'),
  );
  if (!file.existsSync()) return false;

  var source = file.readAsStringSync();
  if (source.contains('_userZoomScale')) return false;
  if (!source.contains('_multiPassDecode')) return false;

  if (!source.contains('dart:js_interop_unsafe')) {
    source = source.replaceFirst(
      "import 'dart:js_interop';\n",
      "import 'dart:js_interop';\nimport 'dart:js_interop_unsafe';\n",
    );
  }

  const oldCrop = '''    final cropW = (vw * cropScale).round().clamp(32, vw);
    final cropH = (vh * cropScale).round().clamp(32, vh);''';

  const newCrop = '''    final userZoom = _userZoomScale();
    final effectiveCrop = (cropScale / userZoom).clamp(0.2, 1.0);
    final cropW = (vw * effectiveCrop).round().clamp(32, vw);
    final cropH = (vh * effectiveCrop).round().clamp(32, vh);''';

  if (!source.contains(oldCrop)) return false;
  source = source.replaceFirst(oldCrop, newCrop);

  const oldFallback = '''    ctx.drawImage(video, 0, 0);
    final full = ctx.getImageData(0, 0, vw, vh);''';

  const newFallback = '''    final fallbackCrop = (1.0 / userZoom).clamp(0.2, 1.0);
    final fbW = (vw * fallbackCrop).round().clamp(32, vw);
    final fbH = (vh * fallbackCrop).round().clamp(32, vh);
    final fbSx = ((vw - fbW) / 2).round();
    final fbSy = ((vh - fbH) / 2).round();
    if (canvas.width != fbW || canvas.height != fbH) {
      canvas
        ..width = fbW
        ..height = fbH;
    }
    ctx.drawImage(
      video,
      fbSx.toDouble(),
      fbSy.toDouble(),
      fbW.toDouble(),
      fbH.toDouble(),
      0,
      0,
      fbW.toDouble(),
      fbH.toDouble(),
    );
    final full = ctx.getImageData(0, 0, fbW, fbH);''';

  if (source.contains(oldFallback)) {
    source = source.replaceFirst(oldFallback, newFallback);
  }

  const helperAnchor = '''    return out;
  }''';

  const helperWithZoom = '''    return out;
  }

  double _userZoomScale() {
    try {
      final z = globalContext.getProperty('ReadDatamatrixCameraZoom'.toJS);
      if (z is JSNumber) {
        return z.toDartDouble.clamp(1.0, 4.0);
      }
    } catch (_) {}
    return 1.0;
  }''';

  if (source.contains(helperAnchor)) {
    source = source.replaceFirst(helperAnchor, helperWithZoom);
  }

  file.writeAsStringSync(source);
  stdout.writeln('✓ Web user zoom decode crop enabled');
  return true;
}

bool _patchAndroidAlternateInvert(Uri root) {
  final file = File.fromUri(
    root.resolve(
      'android/src/main/kotlin/dev/steenbakker/mobile_scanner/MobileScanner.kt',
    ),
  );
  if (!file.existsSync()) return false;

  var source = file.readAsStringSync();
  if (source.contains('alternateInvertFrame')) {
    return false;
  }

  if (!source.contains('private var invertImage: Boolean = false')) {
    stderr.writeln('Android invertImage field not found; skip Android patch.');
    return false;
  }

  source = source.replaceFirst(
    'private var invertImage: Boolean = false',
    'private var invertImage: Boolean = false\n'
        '    // Alternate polarity each frame so white-on-black Data Matrix works\n'
        '    // without forcing invertImage permanently.\n'
        '    private var alternateInvertFrame: Boolean = false',
  );

  const oldBlock = '''
        // Create InputImage directly from ImageProxy for better performance
        // Only convert to Bitmap if we need to invert colors
        var invertedBitmap: Bitmap? = null
        val inputImage = if (invertImage) {
            val bitmap = imageProxy.toBitmap()
            invertedBitmap = invertBitmapColors(bitmap)
            bitmap.recycle()
            InputImage.fromBitmap(invertedBitmap, imageProxy.imageInfo.rotationDegrees)
        } else {
            InputImage.fromMediaImage(mediaImage, imageProxy.imageInfo.rotationDegrees)
        }
''';

  const newBlock = '''
        // Create InputImage directly from ImageProxy for better performance.
        // Alternate normal/inverted frames so both polarities are scanned.
        alternateInvertFrame = !alternateInvertFrame
        val shouldInvert = invertImage || alternateInvertFrame
        var invertedBitmap: Bitmap? = null
        val inputImage = if (shouldInvert) {
            val bitmap = imageProxy.toBitmap()
            invertedBitmap = invertBitmapColors(bitmap)
            bitmap.recycle()
            InputImage.fromBitmap(invertedBitmap, imageProxy.imageInfo.rotationDegrees)
        } else {
            InputImage.fromMediaImage(mediaImage, imageProxy.imageInfo.rotationDegrees)
        }
''';

  if (!source.contains(oldBlock)) {
    stderr.writeln('Android analyzer block not found; skip Android patch.');
    return false;
  }

  source = source.replaceFirst(oldBlock, newBlock);

  source = source.replaceFirst(
    '''
                    // Revert inverted image colors for the returned image (MLKit already scanned the inverted version)
                    if (invertImage) {
''',
    '''
                    // Revert inverted image colors for the returned image (MLKit already scanned the inverted version)
                    if (invertedBitmap != null) {
''',
  );

  file.writeAsStringSync(source);
  stdout.writeln('✓ Android alternate invert enabled');
  return true;
}

bool _patchWebPlaysInline(Uri root) {
  final file = File.fromUri(
    root.resolve('lib/src/web/mobile_scanner_web.dart'),
  );
  if (!file.existsSync()) return false;

  var source = file.readAsStringSync();
  if (source.contains('playsinline')) {
    return false;
  }

  const needle = '''
    // Do not show the media controls, as this is a preview element.
    // Also prevent play/pause events from changing the media controls.
    videoElement
      ..controls = false
''';

  const replacement = '''
    // iOS Safari requires playsinline + muted or the camera feed goes
    // fullscreen / fails to play inside the Flutter view.
    videoElement
      ..controls = false
      ..muted = true
      ..autoplay = true
      ..setAttribute('playsinline', 'true')
      ..setAttribute('webkit-playsinline', 'true')
''';

  if (!source.contains(needle)) {
    stderr.writeln('Web video element block not found; skip playsinline patch.');
    return false;
  }

  source = source.replaceFirst(needle, replacement);
  file.writeAsStringSync(source);
  stdout.writeln('✓ Web playsinline/muted enabled for iOS Safari');
  return true;
}
