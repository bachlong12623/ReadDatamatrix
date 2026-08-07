import 'dart:convert';
import 'dart:io';

/// Patches mobile_scanner for:
/// - Web: enable tryInvert (white-on-black Data Matrix)
/// - Android: alternate normal/inverted frames each tick
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
  changed |= _patchWebTryInvert(root);
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
      // package_config rootUri often omits trailing slash; without it,
      // Uri.resolve replaces the last path segment.
      if (!root.path.endsWith('/')) {
        root = Uri.parse('$root/');
      }
      return root;
    }
  }
  return null;
}

bool _patchWebTryInvert(Uri root) {
  final file = File.fromUri(
    root.resolve('lib/src/web/zxing_wasm/zxing_wasm_barcode_reader.dart'),
  );
  if (!file.existsSync()) return false;

  final original = file.readAsStringSync();
  final updated = original.replaceAll('tryInvert: false', 'tryInvert: true');
  if (updated == original) return false;

  file.writeAsStringSync(updated);
  stdout.writeln('✓ Web tryInvert enabled');
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

  // Add frame toggle field near invertImage.
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

  // returnImage path checks invertImage for reverting preview; use shouldInvert
  // via invertedBitmap presence instead — already uses invertedBitmap when set.
  // The revert block uses invertImage flag; update to invertedBitmap != null.
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
