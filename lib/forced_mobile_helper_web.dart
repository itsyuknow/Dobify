// Web-only implementation
import 'dart:html' as html;

bool getForceMobileFlagImpl() {
  try {
    final value = html.window.localStorage['forceMobileUI'];
    return value != null && value == '1';
  } catch (_) {
    return false;
  }
}
