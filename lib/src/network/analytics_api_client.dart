import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../core/analytics_event.dart';
import '../core/analytics_logger.dart';
import '../device/device_info_collector.dart';


enum UploadStatus { success, retry, drop, }

@immutable
class UploadResult {
  const UploadResult(this.status, {this.statusCode, this.retryAfter});
  final UploadStatus status;

  // >>> HTTP status code, or null when no response was received.
  final int? statusCode;

  // >>> Server requested delay before the next attempt (from `Retry-After`).
  final Duration? retryAfter;

  @override
  String toString() => 'UploadResult($status, code: $statusCode)';
}

// >>> Uploads event batches to the developer's backend.
class AnalyticsApiClient {
  AnalyticsApiClient({required this.endpoint, this.apiKey, this.timeout = const Duration(seconds: 15), http.Client? client,})  : _client = client ?? http.Client(), _ownsClient = client == null;

  // >>> Version of the JSON format. Increase when the format changes.
  static const int schemaVersion = 1;

  // >>> Upper limit for a server provided `Retry-After`.
  static const Duration maxRetryAfter = Duration(hours: 1);

  // >>> HTTP statuses that mean the batch itself is invalid.
  static const Set<int> _permanentFailures = {400, 413, 422};

  final Uri endpoint;
  final String? apiKey;
  final Duration timeout;

  final http.Client _client;
  final bool _ownsClient;

  /// Builds the JSON body. Public so the backend contract can be tested.
  static Map<String, dynamic> buildPayload({required String deviceId, required AnalyticsDeviceInfo deviceInfo, required List<AnalyticsEvent> events, String? userId, Map<String, String> userProperties = const {},}) {
    return <String, dynamic>{
      'schema_version': schemaVersion,
      'sent_at': DateTime.now().toUtc().toIso8601String(),
      'device_id': deviceId,
      'user_id': ?userId,
      if (userProperties.isNotEmpty) 'user_properties': userProperties,
      'device': deviceInfo.toJson(),
      'events': events.map((e) => e.toJson()).toList(growable: false),
    };
  }

  // >>> Sends one batch. Never throws.
  Future<UploadResult> sendBatch({required String deviceId, required AnalyticsDeviceInfo deviceInfo, required List<AnalyticsEvent> events, String? userId, Map<String, String> userProperties = const {},}) async {
    final body = jsonEncode(buildPayload(deviceId: deviceId, deviceInfo: deviceInfo, events: events, userId: userId, userProperties: userProperties,),);

    try {
      //final response = await _client.post(endpoint, headers: <String, String>{'Content-Type': 'application/json; charset=utf-8', 'Accept': 'application/json', 'X-Api-Key': ?apiKey,}, body: body,).timeout(timeout);
      final response = await _client.post(endpoint, headers: <String, String>{'Content-Type': 'application/json; charset=utf-8', 'Accept': 'application/json', if (apiKey != null && apiKey!.isNotEmpty) 'Authorization': 'Bearer $apiKey',}, body: body,).timeout(timeout);

      return _classify(response);
    } catch (error, stackTrace) {
      // >>> Timeout, no connection, DNS or TLS failure: all are temporary.
      AnalyticsLogger.error('Upload failed', error, stackTrace);
      return const UploadResult(UploadStatus.retry);
    }
  }

  UploadResult _classify(http.Response response) {
    final code = response.statusCode;

    if (code >= 200 && code < 300) {
      return UploadResult(UploadStatus.success, statusCode: code);
    }
    if (_permanentFailures.contains(code)) {
      AnalyticsLogger.debug('Server rejected the batch with status $code.');
      return UploadResult(UploadStatus.drop, statusCode: code);
    }

    return UploadResult(UploadStatus.retry, statusCode: code, retryAfter: _parseRetryAfter(response.headers['retry-after']),);
  }

  // >>> Supports the "seconds" form of `Retry-After`. Anything else is ignored.
  static Duration? _parseRetryAfter(String? value) {
    final seconds = int.tryParse(value?.trim() ?? '');
    if (seconds == null || seconds <= 0) return null;
    final delay = Duration(seconds: seconds);
    return delay > maxRetryAfter ? maxRetryAfter : delay;
  }

  // >>> Closes the HTTP client if this object created it.
  void dispose() {
    if (_ownsClient) _client.close();
  }
}