import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart';

const _zoomGlobal = 'ReadDatamatrixCameraZoom';

/// Zoom kỹ thuật số — preview (CSS) + decode (crop trong patch mobile_scanner).
/// iOS Safari KHÔNG hỗ trợ MediaTrack.zoom — không dùng applyConstraints zoom.
Future<void> applyWebDigitalZoom(double scale) async {
  final clamped = scale.clamp(1.0, 4.0);
  globalContext.setProperty(_zoomGlobal.toJS, clamped.toJS);

  final videos = document.querySelectorAll('video');
  for (var i = 0; i < videos.length; i++) {
    final node = videos.item(i);
    if (node == null) continue;
    final video = node as HTMLVideoElement;
    final parent = video.parentElement as HTMLElement?;

    if (clamped <= 1.01) {
      video.style.removeProperty('transform');
      video.style.removeProperty('-webkit-transform');
      video.style.transformOrigin = 'center center';
      parent?.style.removeProperty('overflow');
      parent?.style.removeProperty('transform');
      parent?.style.removeProperty('-webkit-transform');
      continue;
    }

    // Preview: scale video trong khung (Flutter platform view).
    if (parent != null) {
      parent.style.overflow = 'hidden';
    }
    video.style.transformOrigin = 'center center';
    final transform = 'scale($clamped)';
    video.style.setProperty('transform', transform);
    video.style.setProperty('-webkit-transform', transform);
  }
}
