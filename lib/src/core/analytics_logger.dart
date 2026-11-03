import 'dart:developer' as developer;

// >>> Minimal internal logger. Silent unless explicitly enabled.

abstract final class AnalyticsLogger {
  static bool enabled = false;

  static void debug(String message) {
    if (!enabled) return;
    developer.log(message, name: 'UnifiedAnalytics', level: 500);
  }

  static void error(String message, [Object? error, StackTrace? stackTrace]) {
    if (!enabled) return;
    developer.log(message, name: 'UnifiedAnalytics', level: 1000, error: error, stackTrace: stackTrace,);
  }
}