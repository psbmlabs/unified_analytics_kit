import 'dart:async';
import 'dart:math' as math;
import 'package:connectivity_plus/connectivity_plus.dart';
import '../core/analytics_config.dart';
import '../core/analytics_event.dart';
import '../core/analytics_logger.dart';
import '../core/analytics_provider.dart';
import '../device/device_id_service.dart';
import '../device/device_info_collector.dart';
import '../network/analytics_api_client.dart';
import '../storage/event_queue.dart';

/// >>> Stores events in an offline queue and uploads them in batches to the

class DatabaseAnalytics implements AnalyticsProvider {
  DatabaseAnalytics({required this._config, DeviceIdService? deviceIdService, DeviceInfoCollector? deviceInfoCollector, AnalyticsApiClient? apiClient, EventQueue? queue, Connectivity? connectivity,})  : _deviceIdService = deviceIdService ?? DeviceIdService(), _deviceInfoCollector = deviceInfoCollector ?? DeviceInfoCollector(), _injectedClient = apiClient, _injectedQueue = queue, _connectivity = connectivity ?? Connectivity();

  static const Duration _baseBackoff = Duration(seconds: 5);
  static const Duration _maxBackoff = Duration(minutes: 5);

  final AnalyticsConfig _config;
  final DeviceIdService _deviceIdService;
  final DeviceInfoCollector _deviceInfoCollector;
  final AnalyticsApiClient? _injectedClient;
  final EventQueue? _injectedQueue;
  final Connectivity _connectivity;

  late final AnalyticsApiClient _client;
  late final EventQueue _queue;

  Timer? _timer;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  bool _initialized = false;
  bool _enabled = true;
  bool _flushing = false;
  bool _disposed = false;

  int _failures = 0;
  DateTime? _nextAttemptAt;

  String? _userId;
  final Map<String, String> _userProperties = <String, String>{};

  @override
  String get id => AnalyticsProviderIds.database;

  // >>> Number of events waiting for upload.
  int get pendingCount => _initialized ? _queue.length : 0;

  @override
  Future<void> initialize() async {
    if (_initialized) return;

    _queue = _injectedQueue ?? await EventQueue.open(maxSize: _config.maxQueueSize);
    _client = _injectedClient ?? AnalyticsApiClient(endpoint: _config.databaseEndpoint!, apiKey: _config.apiKey, timeout: _config.requestTimeout,);
    _initialized = true;
    _timer = Timer.periodic(_config.flushInterval, (_) => unawaited(flush()));
    _connectivitySub = _connectivity.onConnectivityChanged.listen((results) {
        final online = results.any((r) => r != ConnectivityResult.none);
        if (online) {
          // >>> Connection is back, so a previous backoff no longer applies.
          _nextAttemptAt = null;
          unawaited(flush());
        }
      },
      onError: (Object error, StackTrace stackTrace) {AnalyticsLogger.error('Connectivity stream error', error, stackTrace);},
    );
    // >>> Upload anything left over from the previous app run.
    unawaited(flush());
  }

  @override
  Future<void> logEvent(AnalyticsEvent event) async {
    if (!_initialized || !_enabled || _disposed) return;
    try {
      await _queue.enqueue(event);
      if (_queue.length >= _config.batchSize) {
        unawaited(flush());
      }
    } catch (error, stackTrace) {
      AnalyticsLogger.error('Could not queue event', error, stackTrace);
    }
  }

  @override
  Future<void> logScreenView({required String screenName, String? screenClass,}) {
    return logEvent(AnalyticsEvent('screen_view', parameters: <String, Object?>{'screen_name': screenName, 'screen_class': screenClass,},),);
  }

  @override
  Future<void> setUserId(String? userId) async {
    _userId = userId;
  }

  @override
  Future<void> setUserProperty({required String name, required String? value,}) async {
    if (value == null) {
      _userProperties.remove(name);
    } else {
      _userProperties[name] = value;
    }
  }

  @override
  Future<void> setCollectionEnabled(bool enabled) async {
    _enabled = enabled;
    if (!enabled && _initialized) {
      try {
        await _queue.clear();
      } catch (error, stackTrace) {
        AnalyticsLogger.error('Could not clear queue', error, stackTrace);
      }
    }
  }

  @override
  Future<void> reset() async {
    _userId = null;
    _userProperties.clear();
  }

  /// >>> Uploads queued events now. Safe to call at any time.
  /// >>> Returns after the queue is empty, an upload fails, or [maxRetries]
  /// >>> consecutive failures were reached.
  Future<void> flush() async {
    if (!_initialized || !_enabled || _disposed || _flushing) return;

    final nextAttempt = _nextAttemptAt;
    if (nextAttempt != null && DateTime.now().isBefore(nextAttempt)) return;
    if (_failures > _config.maxRetries) return;

    _flushing = true;
    try {
      while (!_disposed && _enabled && !_queue.isEmpty) {
        final batch = await _queue.peek(_config.batchSize);
        if (batch.isEmpty) break;

        final result = await _client.sendBatch(
          deviceId: await _deviceIdService.getDeviceId(),
          deviceInfo: await _deviceInfoCollector.collect(),
          events: batch.map((q) => q.event).toList(growable: false),
          userId: _userId,
          userProperties: Map<String, String>.of(_userProperties),
        );

        switch (result.status) {
          case UploadStatus.success:
          case UploadStatus.drop:
            await _queue.remove(batch.map((q) => q.key));
            _failures = 0;
            _nextAttemptAt = null;
          case UploadStatus.retry:
            _failures++;
            _nextAttemptAt = DateTime.now().add(
              result.retryAfter ?? _backoff(_failures),
            );
            AnalyticsLogger.debug('Upload failed ($_failures). Next attempt at $_nextAttemptAt.',);
            return;
        }
      }
    } catch (error, stackTrace) {
      AnalyticsLogger.error('Flush failed', error, stackTrace);
    } finally {
      _flushing = false;
    }
  }

  /// >>> 5s, 10s, 20s, 40s ... capped at [_maxBackoff].
  Duration _backoff(int failures) {
    final factor = math.pow(2, math.min(failures - 1, 10)).toInt();
    final delay = _baseBackoff * factor;
    return delay > _maxBackoff ? _maxBackoff : delay;
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    await _connectivitySub?.cancel();
    if (_initialized) {
      if (_injectedClient == null) _client.dispose();
      if (_injectedQueue == null) await _queue.close();
    }
  }
}