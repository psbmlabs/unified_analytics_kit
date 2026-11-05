import 'package:flutter_test/flutter_test.dart';
import 'package:unified_analytics_kit/unified_analytics_kit.dart';

void main() {
  group('AnalyticsEvent', () {
    test('creates a valid event and drops null params', () {
      final event = AnalyticsEvent('purchase', parameters: {'price': 9.5, 'coupon': null},);
      expect(event.parameters, {'price': 9.5});
      expect(event.timestamp.isUtc, isTrue);
    });

    test('rejects invalid names', () {
      expect(() => AnalyticsEvent(''), throwsArgumentError);
      expect(() => AnalyticsEvent('1abc'), throwsArgumentError);
      expect(() => AnalyticsEvent('my event'), throwsArgumentError);
      expect(() => AnalyticsEvent('firebase_x'), throwsArgumentError);
      expect(() => AnalyticsEvent('a' * 41), throwsArgumentError);
    });

    test('rejects unsupported and non-finite values', () {
      expect(() => AnalyticsEvent('e', parameters: {'k': [1]}), throwsArgumentError,);
      expect(() => AnalyticsEvent('e', parameters: {'k': double.nan}), throwsArgumentError,);
    });

    test('truncates long strings to 100 characters', () {
      final event = AnalyticsEvent('e', parameters: {'k': 'a' * 300});
      expect((event.parameters['k']! as String).length, 100);
    });

    test('json round trip keeps data', () {
      final event = AnalyticsEvent('open', parameters: {'a': 1, 'b': true, 'c': 'x'},);
      final restored = AnalyticsEvent.fromJson(event.toJson());
      expect(restored.id, event.id);
      expect(restored.parameters, event.parameters);
      expect(restored.timestamp, event.timestamp);
    });
  });

  group('AnalyticsConsent', () {
    test('everything is denied by default', () {
      const consent = AnalyticsConsent();
      expect(consent.isGrantedFor(AnalyticsProviderIds.firebase), isFalse);
      expect(consent.isGrantedFor(AnalyticsProviderIds.facebook), isFalse);
      expect(consent.isGrantedFor(AnalyticsProviderIds.database), isFalse);
      expect(consent.isGrantedFor('custom'), isFalse);
    });

    test('copyWith and json round trip', () {
      final consent = const AnalyticsConsent.none().copyWith(database: true);
      expect(AnalyticsConsent.fromJson(consent.toJson()), consent);
      expect(consent.isGrantedFor(AnalyticsProviderIds.database), isTrue);
    });

    test('deviceInfo: old saved data means granted, none means off, and it round trips', () {
      expect(AnalyticsConsent.fromJson(const {'firebase': true, 'database': true}).deviceInfo, isTrue);
      expect(const AnalyticsConsent.none().deviceInfo, isFalse);
      const anonymous = AnalyticsConsent(database: true, deviceInfo: false);
      expect(AnalyticsConsent.fromJson(anonymous.toJson()), anonymous);
    });
  });

  group('AnalyticsConfig', () {
    test('database needs an https endpoint', () {
      expect(() => AnalyticsConfig(enableDatabase: true), throwsArgumentError);
      expect(() => AnalyticsConfig(enableDatabase: true, databaseEndpoint: Uri.parse('http://example.com/events'),), throwsArgumentError,);
      expect(AnalyticsConfig(enableDatabase: true, databaseEndpoint: Uri.parse('https://example.com/events'),).enableDatabase, isTrue,);
    });

    test('http is allowed only with allowInsecureHttp', () {
      final config = AnalyticsConfig(enableDatabase: true, databaseEndpoint: Uri.parse('http://10.0.2.2:8080/events'), allowInsecureHttp: true,);
      expect(config.allowInsecureHttp, isTrue);
    });

    test('rejects invalid numbers', () {
      expect(() => AnalyticsConfig(batchSize: 0), throwsArgumentError);
      expect(() => AnalyticsConfig(batchSize: 50, maxQueueSize: 10), throwsArgumentError,);
      expect(() => AnalyticsConfig(flushInterval: const Duration(seconds: 1)), throwsArgumentError,);
    });
  });
}