import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart';

/// iPhone / Safari: playsinline + continuous focus (không set zoom MediaTrack).
Future<void> tuneIosSafariCamera({double zoomScale = 1.0}) async {
  final videos = document.querySelectorAll('video');
  for (var i = 0; i < videos.length; i++) {
    final node = videos.item(i);
    if (node == null) continue;
    final video = node as HTMLVideoElement;

    video
      ..muted = true
      ..autoplay = true
      ..setAttribute('playsinline', 'true')
      ..setAttribute('webkit-playsinline', 'true');

    final src = video.srcObject;
    if (src == null) continue;

    final stream = src as MediaStream;
    for (final track in stream.getVideoTracks().toDart) {
      await _applyFocusIfSupported(track);
    }
  }
}

Future<void> _applyFocusIfSupported(MediaStreamTrack track) async {
  try {
    final focus = JSObject();
    focus.setProperty('focusMode'.toJS, 'continuous'.toJS);
    await track.applyConstraints(focus as MediaTrackConstraints).toDart;
  } catch (_) {
    // iOS Safari thường không hỗ trợ focusMode qua web API.
  }
}
