import 'package:firebase_analytics/firebase_analytics.dart' as fb;
import '../core/analytics_event.dart';
import '../core/analytics_logger.dart';
import '../core/analytics_provider.dart';

// >>> Sends analytics data to Firebase Analytics.
// >>> The host app must call `Firebase.initializeApp()` before
// >>> [initialize] runs. This package never initializes Firebase itself because
// >>> the Firebase config files belong to the app.

class FirebaseAnalyticsProvider implements AnalyticsProvider {
  FirebaseAnalyticsProvider({fb.FirebaseAnalytics? analytics}) : _injected = analytics;

  static const int maxUserPropertyNameLength = 24;
  static const int maxUserPropertyValueLength = 36;
  static const int maxUserIdLength = 256;

  final fb.FirebaseAnalytics? _injected;
  fb.FirebaseAnalytics? _analytics;

  @override
  String get id => AnalyticsProviderIds.firebase;

  fb.FirebaseAnalytics get _client => _analytics ??= _injected ?? fb.FirebaseAnalytics.instance;

  @override
  Future<void> initialize() async {
    // >>> Accessing the instance fails fast with a clear error when the host app
    // >>> forgot to call Firebase.initializeApp().
    _client;
  }

  @override
  Future<void> logEvent(AnalyticsEvent event) async {
    try {
      await _client.logEvent(name: event.name, parameters: event.parameters.isEmpty ? null : event.parameters,);
    } catch (error, stackTrace) {
      AnalyticsLogger.error('Firebase logEvent failed', error, stackTrace);
    }
  }

  @override
  Future<void> logScreenView({required String screenName, String? screenClass,}) async {
    try {
      await _client.logScreenView(screenName: screenName, screenClass: screenClass ?? 'Flutter',);
    } catch (error, stackTrace) {
      AnalyticsLogger.error('Firebase logScreenView failed', error, stackTrace);
    }
  }

  @override
  Future<void> setUserId(String? userId) async {
    try {
      if (userId != null && userId.length > maxUserIdLength) {
        AnalyticsLogger.debug('Firebase user id is too long, ignored.');
        return;
      }
      await _client.setUserId(id: userId);
    } catch (error, stackTrace) {
      AnalyticsLogger.error('Firebase setUserId failed', error, stackTrace);
    }
  }

  @override
  Future<void> setUserProperty({required String name, required String? value,}) async {
    try {
      if (name.length > maxUserPropertyNameLength) {AnalyticsLogger.debug('Firebase property name too long: $name');return;}
      final safeValue = (value != null && value.length > maxUserPropertyValueLength) ? value.substring(0, maxUserPropertyValueLength) : value;
      await _client.setUserProperty(name: name, value: safeValue);
    } catch (error, stackTrace) {
      AnalyticsLogger.error('Firebase setUserProperty failed', error, stackTrace,);
    }
  }

  @override
  Future<void> setCollectionEnabled(bool enabled) async {
    try {
      await _client.setAnalyticsCollectionEnabled(enabled);
    } catch (error, stackTrace) {
      AnalyticsLogger.error('Firebase setCollectionEnabled failed', error, stackTrace,);
    }
  }

  @override
  Future<void> reset() async {
    try {
      await _client.setUserId(id: null);
      await _client.resetAnalyticsData();
    } catch (error, stackTrace) {
      AnalyticsLogger.error('Firebase reset failed', error, stackTrace);
    }
  }

  @override
  Future<void> dispose() async {}
}