import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:unified_analytics_kit/src/device/device_id_service.dart';

class MockSecureStorage extends Mock implements FlutterSecureStorage {}

void main() {
  late MockSecureStorage storage;

  setUp(() {
    storage = MockSecureStorage();
    when(() => storage.write(key: any(named: 'key'), value: any(named: 'value'))).thenAnswer((_) async {});
  });

  void stubRead(String? value) {when(() => storage.read(key: any(named: 'key'))).thenAnswer((_) async => value);}

  DeviceIdService build({TargetPlatform platform = TargetPlatform.android, Future<String?> Function()? androidId,}) {return DeviceIdService(storage: storage, platform: platform, androidIdReader: androidId ?? () async => 'abc123',);}

  test('returns the stored id without generating a new one', () async {
    stubRead('stored-id');
    final id = await build().getDeviceId();
    expect(id, 'stored-id');
    verifyNever(() => storage.write(key: any(named: 'key'), value: any(named: 'value')),);
  });

  test('android: hashes ANDROID_ID, never exposes the raw value', () async {
    stubRead(null);
    final id = await build().getDeviceId();
    expect(id, matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(id, isNot(contains('abc123')));
  });

  test('android: same ANDROID_ID gives the same id', () async {
    stubRead(null);
    final first = await build().getDeviceId();
    final second = await build().getDeviceId();
    expect(first, second);
  });

  test('android: broken ANDROID_ID falls back to a random UUID', () async {
    stubRead(null);
    final id = await build(androidId: () async => '9774d56d682e549c').getDeviceId();
    expect(id, matches(RegExp(r'^[0-9a-f-]{36}$')));
  });

  test('ios: generates a UUID and saves it', () async {
    stubRead(null);
    final id = await build(platform: TargetPlatform.iOS).getDeviceId();
    expect(id, matches(RegExp(r'^[0-9a-f-]{36}$')));
    verify(() => storage.write(key: any(named: 'key'), value: id)).called(1);
  });

  test('never throws when secure storage fails', () async {
    when(() => storage.read(key: any(named: 'key'))).thenThrow(Exception('keystore error'));
    when(() => storage.write(key: any(named: 'key'), value: any(named: 'value'))).thenThrow(Exception('keystore error'));
    final id = await build().getDeviceId();
    expect(id, isNotEmpty);
  });

  test('concurrent calls read storage only once', () async {
    stubRead('stored-id');
    final service = build();
    final ids = await Future.wait([service.getDeviceId(), service.getDeviceId(), service.getDeviceId(),]);
    expect(ids.toSet(), {'stored-id'});
    verify(() => storage.read(key: any(named: 'key'))).called(1);
  });
}