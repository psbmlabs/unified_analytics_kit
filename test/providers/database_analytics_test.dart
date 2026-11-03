import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:unified_analytics_kit/src/core/analytics_config.dart';
import 'package:unified_analytics_kit/src/core/analytics_event.dart';
import 'package:unified_analytics_kit/src/device/device_id_service.dart';
import 'package:unified_analytics_kit/src/device/device_info_collector.dart';
import 'package:unified_analytics_kit/src/network/analytics_api_client.dart';
import 'package:unified_analytics_kit/src/providers/database_analytics.dart';
import 'package:unified_analytics_kit/src/storage/event_queue.dart';

class FakeQueue extends Mock implements EventQueue {
  final List<QueuedEvent> items = [];
  int _next = 0;

  @override
  int get length => items.length;

  @override
  bool get isEmpty => items.isEmpty;

  @override
  Future<void> enqueue(AnalyticsEvent event) async {items.add(QueuedEvent(_next++, event));}

  @override
  Future<List<QueuedEvent>> peek(int count) async => items.take(count).toList();

  @override
  Future<void> remove(Iterable<int> keys) async {
    final set = keys.toSet();
    items.removeWhere((q) => set.contains(q.key));
  }

  @override
  Future<void> clear() async => items.clear();

  @override
  Future<void> close() async {}
}

class MockClient extends Mock implements AnalyticsApiClient {}

class MockIdService extends Mock implements DeviceIdService {}

class MockInfoCollector extends Mock implements DeviceInfoCollector {}

class MockConnectivity extends Mock implements Connectivity {}

void main() {
  late FakeQueue queue;
  late MockClient client;
  late MockConnectivity connectivity;
  late StreamController<List<ConnectivityResult>> network;
  late DatabaseAnalytics provider;

  setUpAll(() {
    registerFallbackValue(const AnalyticsDeviceInfo(platform: 'android'));
    registerFallbackValue(<AnalyticsEvent>[]);
  });

  setUp(() async {
    queue = FakeQueue();
    client = MockClient();
    connectivity = MockConnectivity();
    network = StreamController<List<ConnectivityResult>>.broadcast();
    when(() => connectivity.onConnectivityChanged).thenAnswer((_) => network.stream);

    final idService = MockIdService();
    when(idService.getDeviceId).thenAnswer((_) async => 'device-1');
    final info = MockInfoCollector();
    when(info.collect).thenAnswer((_) async => const AnalyticsDeviceInfo(platform: 'android'));

    provider = DatabaseAnalytics(
      config: AnalyticsConfig(enableDatabase: true, databaseEndpoint: Uri.parse('https://example.com/e'), batchSize: 2, maxQueueSize: 10,),
      deviceIdService: idService,
      deviceInfoCollector: info,
      apiClient: client,
      queue: queue,
      connectivity: connectivity,
    );
  });

  tearDown(() async {
    await provider.dispose();
    await network.close();
  });

  void stubUpload(UploadResult result) {
    when(() => client.sendBatch(
        deviceId: any(named: 'deviceId'),
        deviceInfo: any(named: 'deviceInfo'),
        events: any(named: 'events'),
        userId: any(named: 'userId'),
        userProperties: any(named: 'userProperties'),
      ),
    ).thenAnswer((_) async => result);
  }

  AnalyticsEvent event(String name) => AnalyticsEvent(name);

  test('flush uploads and removes events on success', () async {
    stubUpload(const UploadResult(UploadStatus.success, statusCode: 202));
    await provider.initialize();
    await provider.logEvent(event('a'));
    await provider.flush();

    expect(queue.items, isEmpty);
  });

  test('events stay in the queue when the upload must be retried', () async {
    stubUpload(const UploadResult(UploadStatus.retry));
    await provider.initialize();
    await provider.logEvent(event('a'));
    await provider.flush();
    expect(queue.items.length, 1);
  });

  test('events are removed when the server rejects them (drop)', () async {
    stubUpload(const UploadResult(UploadStatus.drop, statusCode: 400));
    await provider.initialize();
    await provider.logEvent(event('a'));
    await provider.flush();

    expect(queue.items, isEmpty);
  });

  test('backoff blocks a second flush right after a failure', () async {
    stubUpload(const UploadResult(UploadStatus.retry));
    await provider.initialize();
    await provider.logEvent(event('a'));
    await provider.flush();
    await provider.flush();

    verify(() => client.sendBatch(
        deviceId: any(named: 'deviceId'),
        deviceInfo: any(named: 'deviceInfo'),
        events: any(named: 'events'),
        userId: any(named: 'userId'),
        userProperties: any(named: 'userProperties'),
      ),
    ).called(1);
  });

  test('coming back online clears the backoff and flushes', () async {
    stubUpload(const UploadResult(UploadStatus.retry));
    await provider.initialize();
    await provider.logEvent(event('a'));
    await provider.flush();

    stubUpload(const UploadResult(UploadStatus.success, statusCode: 202));
    network.add([ConnectivityResult.wifi]);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(queue.items, isEmpty);
  });

  test('disabling collection clears the queue and stops new events', () async {
    stubUpload(const UploadResult(UploadStatus.retry));
    await provider.initialize();
    await provider.logEvent(event('a'));
    await provider.setCollectionEnabled(false);
    await provider.logEvent(event('b'));

    expect(queue.items, isEmpty);
  });

  test('user id and properties are sent with the batch', () async {
    stubUpload(const UploadResult(UploadStatus.success, statusCode: 200));
    await provider.initialize();
    await provider.setUserId('user_1');
    await provider.setUserProperty(name: 'plan', value: 'pro');
    await provider.logEvent(event('a'));
    await provider.flush();

    verify(() => client.sendBatch(
        deviceId: 'device-1',
        deviceInfo: any(named: 'deviceInfo'),
        events: any(named: 'events'),
        userId: 'user_1',
        userProperties: {'plan': 'pro'},
      ),
    ).called(greaterThanOrEqualTo(1));
  });

  test('logEvent before initialize is ignored safely', () async {
    await provider.logEvent(event('a'));
    expect(queue.items, isEmpty);
  });
}