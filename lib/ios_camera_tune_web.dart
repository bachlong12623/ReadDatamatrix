import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart';

/// iPhone Air / Safari: playsinline + zoom + continuous focus.
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
      await _applyBestEffortConstraints(track, zoomScale: zoomScale);
    }
  }
}

Future<void> _applyBestEffortConstraints(
  MediaStreamTrack track, {
  double zoomScale = 1.0,
}) async {
  // Continuous AF — Fusion Main (ƒ/1.6) lấy nét mã gần tốt hơn.
  try {
    final focus = JSObject();
    focus.setProperty('focusMode'.toJS, 'continuous'.toJS);
    await track.applyConstraints(focus as MediaTrackConstraints).toDart;
  } catch (_) {}

  // Zoom — 1× mặc định; user có thể chọn 2×/4× cho mã nhỏ / chấm.
  try {
    final zoom = JSObject();
    zoom.setProperty('zoom'.toJS, zoomScale.clamp(1.0, 4.0).toJS);
    final advanced = JSArray<JSObject>();
    advanced.add(zoom);

    final constraints = JSObject();
    constraints.setProperty('advanced'.toJS, advanced);
    await track.applyConstraints(constraints as MediaTrackConstraints).toDart;
  } catch (_) {}
}
