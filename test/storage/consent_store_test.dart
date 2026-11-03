import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:mocktail/mocktail.dart';
import 'package:unified_analytics_kit/src/core/analytics_consent.dart';
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

void main() {
  late FakeBox box;
  late ConsentStore store;

  setUp(() {box = FakeBox();store = ConsentStore.forBox(box);});

  test('returns null when the user never decided', () {expect(store.load(), isNull);expect(store.hasDecision, isFalse);});

  test('saves and loads a choice', () async {
    const consent = AnalyticsConsent(firebase: true, database: true);
    await store.save(consent);

    expect(store.load(), consent);
    expect(store.hasDecision, isTrue);
  });

  test('a saved "deny all" still counts as a decision', () async {
    await store.save(const AnalyticsConsent.none());

    expect(store.load(), const AnalyticsConsent.none());
    expect(store.hasDecision, isTrue);
  });

  test('unreadable data is treated as no decision', () {
    box.data['consent'] = 'not json {{{';

    expect(store.load(), isNull);
    expect(store.hasDecision, isFalse);
  });

  test('clear forgets the choice', () async {
    await store.save(const AnalyticsConsent.all());
    await store.clear();

    expect(store.load(), isNull);
  });
}