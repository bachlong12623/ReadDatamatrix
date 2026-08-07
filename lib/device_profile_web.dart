import 'package:web/web.dart';

import 'device_profile.dart';

DeviceProfile detectWebDeviceProfile() {
  final ua = window.navigator.userAgent;
  final isIphone = ua.contains('iPhone');
  final isIpad = ua.contains('iPad') ||
      (ua.contains('Macintosh') && window.navigator.maxTouchPoints > 1);
  final isAppleMobile = isIphone || isIpad;

  return DeviceProfile(
    isWeb: true,
    isAppleMobileWeb: isAppleMobile,
    isIphone: isIphone,
  );
}
