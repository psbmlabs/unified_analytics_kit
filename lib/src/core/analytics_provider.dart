import 'analytics_event.dart';

// >>> Stable identifiers of the built-in providers.
abstract final class AnalyticsProviderIds {
  static const String firebase = 'firebase';
  static const String facebook = 'facebook';
  static const String database = 'database';
}

/// >>> Contract every analytics destination must implement.

abstract interface class AnalyticsProvider {

  String get id;

  Future<void> initialize();

  Future<void> logEvent(AnalyticsEvent event);

  Future<void> logScreenView({required String screenName, String? screenClass});

  // >>> Pass `null` to clear the user id.
  Future<void> setUserId(String? userId);

  // >>> Pass a `null` [value] to clear the property.
  Future<void> setUserProperty({required String name, required String? value});

  // >>> Turns data collection on or off (used for consent).
  Future<void> setCollectionEnabled(bool enabled);

  // >>> Clears user specific state, for example on logout.
  Future<void> reset();

  // >>> Releases resources.
  Future<void> dispose();
}