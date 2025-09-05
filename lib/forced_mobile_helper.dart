// This file chooses the right implementation depending on the platform.
import 'forced_mobile_helper_stub.dart'
if (dart.library.html) 'forced_mobile_helper_web.dart';

// Public function used in your app
bool getForceMobileFlag() => getForceMobileFlagImpl();
