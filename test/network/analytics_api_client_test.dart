import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:unified_analytics_kit/src/core/analytics_event.dart';
import 'package:unified_analytics_kit/src/device/device_info_collector.dart';
import 'package:unified_analytics_kit/src/network/analytics_api_client.dart';

void main() {
  const deviceInfo = AnalyticsDeviceInfo(platform: 'android', model: 'Pixel');
  final events = [AnalyticsEvent('app_open', parameters: {'count': 1}),];

  AnalyticsApiClient build(MockClient mock, {String? apiKey = 'key-123', Duration timeout = const Duration(seconds: 1),}) {return AnalyticsApiClient(endpoint: Uri.parse('https://example.com/v1/events'), apiKey: apiKey, timeout: timeout, client: mock,);}

  Future<UploadResult> send(AnalyticsApiClient client) {return client.sendBatch(deviceId: 'device-1', deviceInfo: deviceInfo, events: events,);}

  test('sends the expected request and succeeds on 202', () async {
    late http.Request captured;
    final client = build(MockClient((request) async {captured = request;return http.Response('', 202);}));

    final result = await send(client);

    expect(result.status, UploadStatus.success);
    expect(captured.method, 'POST');
    expect(captured.headers['Authorization'], 'Bearer key-123');
    expect(captured.headers['Content-Type'], contains('application/json'));

    final body = jsonDecode(captured.body) as Map<String, dynamic>;
    expect(body['schema_version'], 1);
    expect(body['device_id'], 'device-1');
    expect(body.containsKey('user_id'), isFalse);
    expect((body['events'] as List).length, 1);
    expect((body['device'] as Map)['platform'], 'android');
  });

  test('omits the api key header when no key is configured', () async {
    late http.Request captured;
    final client = build(MockClient((request) async {captured = request;return http.Response('', 200);}), apiKey: null,);
    await send(client);
    expect(captured.headers.containsKey('Authorization'), isFalse);
  });

  test('5xx means retry', () async {
    final client = build(MockClient((_) async => http.Response('', 503)));
    final result = await send(client);
    expect(result.status, UploadStatus.retry);
    expect(result.statusCode, 503);
  });

  test('429 reads Retry-After and caps it at one hour', () async {
    final normal = build(MockClient((_) async => http.Response('', 429, headers: {'retry-after': '120'}),));
    expect((await send(normal)).retryAfter, const Duration(minutes: 2));
    final huge = build(MockClient((_) async => http.Response('', 429, headers: {'retry-after': '999999'}),));
    expect((await send(huge)).retryAfter, AnalyticsApiClient.maxRetryAfter);
  });

  test('400, 413 and 422 mean drop', () async {
    for (final code in [400, 413, 422]) {
      final client = build(MockClient((_) async => http.Response('', code)));
      expect((await send(client)).status, UploadStatus.drop, reason: '$code');
    }
  });

  test('401 and 403 keep the events (retry)', () async {
    for (final code in [401, 403]) {
      final client = build(MockClient((_) async => http.Response('', code)));
      expect((await send(client)).status, UploadStatus.retry, reason: '$code');
    }
  });

  test('network errors never throw and mean retry', () async {
    final client = build(MockClient((_) async => throw http.ClientException('no network')),);
    final result = await send(client);
    expect(result.status, UploadStatus.retry);
    expect(result.statusCode, isNull);
  });

  test('timeout means retry', () async {
    final client = build(MockClient((_) async {await Future<void>.delayed(const Duration(milliseconds: 300));return http.Response('', 200);}), timeout: const Duration(milliseconds: 50),);
    expect((await send(client)).status, UploadStatus.retry);
  });
}