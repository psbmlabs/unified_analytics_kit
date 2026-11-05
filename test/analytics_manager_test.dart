import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:mocktail/mocktail.dart';
import 'package:unified_analytics_kit/src/analytics_manager.dart';
import 'package:unified_analytics_kit/src/core/analytics_config.dart';
import 'package:unified_analytics_kit/src/core/analytics_consent.dart';
import 'package:unified_analytics_kit/src/core/analytics_destination.dart';
import 'package:unified_analytics_kit/src/core/analytics_event.dart';
import 'package:unified_analytics_kit/src/core/analytics_provider.dart';
import 'package:unified_analytics_kit/src/storage/consent_store.dart';

class FakeBox extends Mock implements Box<String> {
  final Map<String, String> data = {};

  @override
  String? get(dynamic key, {String? defaultValue}) => data[key as String] ?? defaultValue;

  @override
  Future<void> put(dynamic key, String value) async {
    data[key as String] = value;
  }

  @override
  Future<void> delete(dynamic key) async {
    data.remove(key as String);
  }
}

class FakeProvider implements AnalyticsProvider {
  FakeProvider(this.id, {this.failOnInit = false, this.failOnLog = false,});

  @override
  final String id;
  final bool failOnInit;
  final bool failOnLog;

  final List<AnalyticsEvent> events = [];
  final List<String?> userIds = [];
  bool? collectionEnabled;
  int resetCount = 0;

  @override
  Future<void> initialize() async {
    if (failOnInit) throw StateError('init failed');
  }

  @override
  Future<void> logEvent(AnalyticsEvent event) async {
    if (failOnLog) throw StateError('log failed');
    events.add(event);
  }

  @override
  Future<void> logScreenView({required String screenName, String? screenClass,}) async {}

  @override
  Future<void> setUserId(String? userId) async => userIds.add(userId);

  @override
  Future<void> setUserProperty({required String name, required String? value,}) async {}

  @override
  Future<void> setCollectionEnabled(bool enabled) async {collectionEnabled = enabled;}

  @override
  Future<void> reset() async => resetCount++;

  @override
  Future<void> dispose() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeBox box;
  late FakeProvider firebase;
  late FakeProvider facebook;
  late AnalyticsManager manager;

  AnalyticsManager build(List<AnalyticsProvider> providers) {return AnalyticsManager.forTesting(providers: providers, consentStore: ConsentStore.forBox(box),);}

  setUp(() {
    box = FakeBox();
    firebase = FakeProvider(AnalyticsProviderIds.firebase);
    facebook = FakeProvider(AnalyticsProviderIds.facebook);
    manager = build([firebase, facebook]);
  });

  tearDown(() => manager.dispose());

  test('nothing is sent before the user gives consent', () async {
    await manager.initialize(AnalyticsConfig());
    await manager.logEvent('app_open');

    expect(firebase.events, isEmpty);
    expect(facebook.events, isEmpty);
    expect(firebase.collectionEnabled, isFalse);
    expect(manager.hasConsentDecision, isFalse);
  });

  test('only providers with consent receive events', () async {
    await manager.initialize(AnalyticsConfig());
    await manager.setConsent(const AnalyticsConsent(firebase: true));
    await manager.logEvent('app_open');

    expect(firebase.events.length, 1);
    expect(facebook.events, isEmpty);
    expect(manager.hasConsentDecision, isTrue);
  });

  test('revoking consent stops events and resets the provider', () async {
    await manager.initialize(AnalyticsConfig());
    await manager.setConsent(const AnalyticsConsent.all());
    await manager.setConsent(const AnalyticsConsent.none());
    await manager.logEvent('app_open');

    expect(firebase.events, isEmpty);
    expect(firebase.collectionEnabled, isFalse);
    expect(firebase.resetCount, 1);
  });

  test('consent is remembered by the next manager', () async {
    await manager.initialize(AnalyticsConfig());
    await manager.setConsent(const AnalyticsConsent(facebook: true));
    await manager.dispose();

    manager = build([firebase, facebook]);
    await manager.initialize(AnalyticsConfig());

    expect(manager.hasConsentDecision, isTrue);
    expect(manager.consent, const AnalyticsConsent(facebook: true));
  });

  test('the decision time and decline count are remembered by the next manager', () async {
    await manager.initialize(AnalyticsConfig());
    expect(manager.consentDecidedAt, isNull);
    expect(manager.consentDeclineCount, 0);

    await manager.setConsent(const AnalyticsConsent.none(), declineCount: 2);
    expect(manager.consentDeclineCount, 2);
    expect(manager.consentDecidedAt, isNotNull);
    await manager.dispose();

    manager = build([firebase, facebook]);
    await manager.initialize(AnalyticsConfig());
    expect(manager.consentDeclineCount, 2);
    expect(manager.consentDecidedAt, isNotNull);
  });

  test('user id is held back until consent is granted', () async {
    await manager.initialize(AnalyticsConfig());
    await manager.setUserId('user_1');
    expect(firebase.userIds, isEmpty);

    await manager.setConsent(const AnalyticsConsent(firebase: true));
    expect(firebase.userIds, ['user_1']);
    expect(facebook.userIds, isEmpty);
  });

  test('a failing provider does not block the others', () async {
    final broken = FakeProvider(AnalyticsProviderIds.firebase, failOnLog: true);
    manager = build([broken, facebook]);
    await manager.initialize(AnalyticsConfig());
    await manager.setConsent(const AnalyticsConsent.all());
    await manager.logEvent('app_open');

    expect(facebook.events.length, 1);
  });

  test('a provider that cannot start is excluded and reported', () async {
    final broken =
    FakeProvider(AnalyticsProviderIds.firebase, failOnInit: true);
    manager = build([broken, facebook]);
    await manager.initialize(AnalyticsConfig());
    await manager.setConsent(const AnalyticsConsent.all());
    await manager.logEvent('app_open');

    expect(manager.failedProviderIds, [AnalyticsProviderIds.firebase]);
    expect(broken.events, isEmpty);
    expect(facebook.events.length, 1);
  });

  test('invalid event names throw in debug builds', () async {
    await manager.initialize(AnalyticsConfig());
    await expectLater(manager.logEvent('bad name'), throwsArgumentError);
  });

  test('calls before initialize are ignored, setConsent throws', () async {
    await manager.logEvent('app_open');
    expect(firebase.events, isEmpty);
    expect(() => manager.setConsent(const AnalyticsConsent.all()), throwsStateError,);
  });

  test('logout clears the user from every provider', () async {
    await manager.initialize(AnalyticsConfig());
    await manager.setConsent(const AnalyticsConsent.all());
    await manager.logout();

    expect(firebase.resetCount, 1);
    expect(facebook.resetCount, 1);
  });

  group('destinations', () {
    late FakeProvider database;

    setUp(() async {
      await manager.dispose();
      database = FakeProvider(AnalyticsProviderIds.database);
      manager = build([firebase, facebook, database]);
      await manager.initialize(AnalyticsConfig());
      await manager.setConsent(const AnalyticsConsent.all());
    });

    test('default sends to every provider', () async {
      await manager.logEvent('app_open');
      expect(firebase.events.length, 1);
      expect(facebook.events.length, 1);
      expect(database.events.length, 1);
    });

    test('a call can target only the database', () async {
      await manager.logEvent('product_viewed', destinations: {AnalyticsDestination.database},);
      expect(database.events.length, 1);
      expect(firebase.events, isEmpty);
      expect(facebook.events, isEmpty);
    });

    test('firebase and database without facebook', () async {
      await manager.logEvent('x', destinations: {AnalyticsDestination.firebase, AnalyticsDestination.database,},);
      expect(firebase.events.length, 1);
      expect(database.events.length, 1);
      expect(facebook.events, isEmpty);
    });

    test('screen scope applies its destinations and adds screen_name', () async {
      final screen = manager.forScreen('Checkout', destinations: {AnalyticsDestination.facebook},);
      await screen.logEvent('pay_tapped');

      expect(facebook.events.single.parameters['screen_name'], 'Checkout');
      expect(firebase.events, isEmpty);
      expect(database.events, isEmpty);
    });

    test('a call overrides the screen scope', () async {
      final screen = manager.forScreen('Checkout', destinations: {AnalyticsDestination.facebook},);
      await screen.logEvent('pay_tapped');
      await manager.logEvent('purchase', destinations: {AnalyticsDestination.database},);

      expect(facebook.events.length, 1);
      expect(database.events.length, 1);
    });

    test('destinations never bypass missing consent', () async {
      await manager.setConsent(const AnalyticsConsent(database: true));
      await manager.logEvent('x', destinations: {AnalyticsDestination.facebook},);
      expect(facebook.events, isEmpty);
    });
  });

  test('app wide default destinations are respected', () async {
    await manager.dispose();
    final database = FakeProvider(AnalyticsProviderIds.database);
    manager = build([firebase, facebook, database]);
    await manager.initialize(AnalyticsConfig(defaultDestinations: {AnalyticsDestination.firebase}),);
    await manager.setConsent(const AnalyticsConsent.all());
    await manager.logEvent('app_open');

    expect(firebase.events.length, 1);
    expect(facebook.events, isEmpty);
    expect(database.events, isEmpty);
  });

  test('empty default destinations are rejected', () {
    expect(() => AnalyticsConfig(defaultDestinations: <AnalyticsDestination>{}), throwsArgumentError,);
  });
}