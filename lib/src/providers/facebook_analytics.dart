import 'package:facebook_app_events/facebook_app_events.dart' as fbe;
import '../core/analytics_event.dart';
import '../core/analytics_logger.dart';
import '../core/analytics_provider.dart';

/// >>> Sends analytics data to Facebook App Events.
/// >>> The host app must add the Facebook App ID and Client Token to its native
/// >>> Android and iOS configuration. This package cannot do that for the app.
class FacebookAnalytics implements AnalyticsProvider {
  FacebookAnalytics({fbe.FacebookAppEvents? client}) : _injected = client;

  final fbe.FacebookAppEvents? _injected;
  fbe.FacebookAppEvents? _client;

  @override
  String get id => AnalyticsProviderIds.facebook;

  fbe.FacebookAppEvents get _facebook => _client ??= _injected ?? fbe.FacebookAppEvents();

  @override
  Future<void> initialize() async {
    try {
      // >>> Nothing is collected until consent is granted.
      await _facebook.setAutoLogAppEventsEnabled(false);
    } catch (error, stackTrace) {
      AnalyticsLogger.error('Facebook initialize failed', error, stackTrace);
    }
  }

  @override
  Future<void> logEvent(AnalyticsEvent event) async {
    try {
      await _facebook.logEvent(name: event.name, parameters: event.parameters.isEmpty ? null : Map<String, dynamic>.of(event.parameters),);
    } catch (error, stackTrace) {
      AnalyticsLogger.error('Facebook logEvent failed', error, stackTrace);
    }
  }

  @override
  Future<void> logScreenView({required String screenName, String? screenClass,}) async {
    try {
      await _facebook.logEvent(name: 'screen_view', parameters: <String, dynamic>{'screen_name': screenName, 'screen_class': ?screenClass,},);
    } catch (error, stackTrace) {
      AnalyticsLogger.error('Facebook logScreenView failed', error, stackTrace);
    }
  }

  @override
  Future<void> setUserId(String? userId) async {
    try {
      if (userId == null) {
        await _facebook.clearUserID();
      } else {
        await _facebook.setUserID(userId);
      }
    } catch (error, stackTrace) {
      AnalyticsLogger.error('Facebook setUserId failed', error, stackTrace);
    }
  }

  @override
  Future<void> setUserProperty({required String name, required String? value,}) async {
    // Facebook App Events has no generic custom user properties API.
    // Its setUserData accepts only fixed personal fields (email, phone...),
    // which this kit deliberately never sends. Firebase and the database
    // provider store custom properties instead.
    AnalyticsLogger.debug('Facebook ignores custom user property: $name');
  }

  @override
  Future<void> setCollectionEnabled(bool enabled) async {
    try {
      await _facebook.setAutoLogAppEventsEnabled(enabled);
      await _facebook.setAdvertiserIdCollectionEnabled(enabled);
    } catch (error, stackTrace) {
      AnalyticsLogger.error('Facebook setCollectionEnabled failed', error, stackTrace,);
    }
  }

  @override
  Future<void> reset() async {
    try {
      await _facebook.clearUserID();
      await _facebook.clearUserData();
    } catch (error, stackTrace) {
      AnalyticsLogger.error('Facebook reset failed', error, stackTrace);
    }
  }

  @override
  Future<void> dispose() async {}
}