import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart';

void downloadTextFile(String name, String content, String mime) {
  final bytes = utf8.encode(content);
  final data = bytes.toJS;
  final blob = Blob(
    [data].toJS,
    BlobPropertyBag(type: mime),
  );
  final url = URL.createObjectURL(blob);
  final anchor = HTMLAnchorElement()
    ..href = url
    ..download = name
    ..style.display = 'none';
  document.body!.appendChild(anchor);
  anchor.click();
  anchor.remove();
  URL.revokeObjectURL(url);
}
