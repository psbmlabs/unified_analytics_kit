import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'core/analytics_config.dart';
import 'core/analytics_consent.dart';
import 'core/analytics_destination.dart';
import 'core/analytics_event.dart';
import 'core/analytics_logger.dart';
import 'core/analytics_provider.dart';
import 'device/device_id_service.dart';
import 'providers/database_analytics.dart';
import 'providers/facebook_analytics.dart';
import 'providers/firebase_analytics_provider.dart';
import 'storage/consent_store.dart';



class AnalyticsManager with WidgetsBindingObserver {
  AnalyticsManager() : this._(null, null, null);

  // >>>Lets tests inject fakes.
  @visibleForTesting
  AnalyticsManager.forTesting({List<AnalyticsProvider>? providers, ConsentStore? consentStore, DeviceIdService? deviceIdService,}) : this._(providers, consentStore, deviceIdService);

  AnalyticsManager._(this._injectedProviders, this._injectedConsentStore, DeviceIdService? deviceIdService,) : _deviceIdService = deviceIdService ?? DeviceIdService();

  // >>> Shared instance for normal app use.
  static final AnalyticsManager instance = AnalyticsManager();

  final List<AnalyticsProvider>? _injectedProviders;
  final ConsentStore? _injectedConsentStore;
  final DeviceIdService _deviceIdService;

  final List<AnalyticsProvider> _active = <AnalyticsProvider>[];
  final List<String> _failedProviderIds = <String>[];

  ConsentStore? _consentStore;
  Future<void>? _initFuture;
  bool _ready = false;
  bool _decided = false;
  AnalyticsConsent _consent = const AnalyticsConsent.none();
  Set<AnalyticsDestination> _defaultDestinations = AnalyticsDestination.all;

  String? _userId;
  final Map<String, String> _userProperties = <String, String>{};

  // >>> Whether [initialize] has finished.
  bool get isInitialized => _ready;

  // >>> The consent currently in effect.
  AnalyticsConsent get consent => _consent;

  bool get hasConsentDecision => _decided;

  // >>> Providers that could not start (for example Firebase not initialized).
  List<String> get failedProviderIds => List<String>.unmodifiable(_failedProviderIds);


  Future<void> initialize(AnalyticsConfig config) {
    return _initFuture ??= _initialize(config);
  }

  Future<void> _initialize(AnalyticsConfig config) async {
    AnalyticsLogger.enabled = config.debugLogging;
    _defaultDestinations = config.defaultDestinations;
    WidgetsFlutterBinding.ensureInitialized();
    WidgetsBinding.instance.addObserver(this);

    _consentStore = _injectedConsentStore;
    if (_consentStore == null) {
      try {
        _consentStore = await ConsentStore.open();
      } catch (error, stackTrace) {
        // >>> Consent still works for this session, it just is not remembered.
        AnalyticsLogger.error('Consent store unavailable', error, stackTrace);
      }
    }

    final saved = _consentStore?.load();
    _decided = saved != null;
    _consent = saved ?? config.defaultConsent;

    final candidates = _injectedProviders ?? _buildProviders(config);
    final started = await Future.wait(candidates.map(_start));
    _active.addAll(started.whereType<AnalyticsProvider>());
    _ready = true;
  }

  List<AnalyticsProvider> _buildProviders(AnalyticsConfig config) {
    return <AnalyticsProvider>[
      if (config.enableFirebase) FirebaseAnalyticsProvider(),
      if (config.enableFacebook) FacebookAnalytics(),
      if (config.enableDatabase) DatabaseAnalytics(config: config, deviceIdService: _deviceIdService),
    ];
  }

  Future<AnalyticsProvider?> _start(AnalyticsProvider provider) async {
    final granted = _consent.isGrantedFor(provider.id);
    try {
      // >>> Without consent, collection must be off before the provider starts,
      // >>> otherwise it could upload leftovers while initializing.
      if (!granted) await provider.setCollectionEnabled(false);
      await provider.initialize();
      await provider.setCollectionEnabled(granted);
      return provider;
    } catch (error, stackTrace) {
      _failedProviderIds.add(provider.id);
      AnalyticsLogger.error('Provider "${provider.id}" failed to start', error, stackTrace,);
      if (kDebugMode) {
        debugPrint('[unified_analytics_kit] Provider "${provider.id}" is disabled: $error',);
      }
      return null;
    }
  }


  Future<bool> _awaitReady() async {
    if (_ready) return true;
    final init = _initFuture;
    if (init == null) return false;
    try {
      await init;
    } catch (_) {
      return false;
    }
    return _ready;
  }

  Future<void> setConsent(AnalyticsConsent consent) async {
    final init = _initFuture;
    if (init == null) {
      throw StateError('Call AnalyticsManager.initialize() first.');
    }
    await init;

    final previous = _consent;
    _consent = consent;
    _decided = true;

    try {
      await _consentStore?.save(consent);
    } catch (error, stackTrace) {
      AnalyticsLogger.error('Could not save consent', error, stackTrace);
    }

    await _forEachActive((provider) async {
      final was = previous.isGrantedFor(provider.id);
      final now = consent.isGrantedFor(provider.id);
      if (was == now) return;

      await provider.setCollectionEnabled(now);
      if (now) {
        await _syncUser(provider);
      } else {
        await provider.reset();
      }
    });
  }

  Future<void> _syncUser(AnalyticsProvider provider) async {
    final userId = _userId;
    if (userId != null) await provider.setUserId(userId);
    for (final entry in _userProperties.entries) {
      await provider.setUserProperty(name: entry.key, value: entry.value);
    }
  }


  Future<void> logEvent(String name, {Map<String, Object?>? parameters, Set<AnalyticsDestination>? destinations,}) async {
    if (!await _awaitReady()) return;

    final AnalyticsEvent event;
    try {
      event = AnalyticsEvent(name, parameters: parameters);
    } on ArgumentError catch (error, stackTrace) {
      if (kDebugMode) rethrow;
      AnalyticsLogger.error('Invalid event dropped', error, stackTrace);
      return;
    }

    await _forEachGranted((provider) => provider.logEvent(event), destinations: destinations,);
  }

  // >>> Logs a screen view. [destinations] works like in [logEvent].
  Future<void> logScreenView({required String screenName, String? screenClass, Set<AnalyticsDestination>? destinations,}) async {
    if (!await _awaitReady()) return;
    await _forEachGranted((provider) => provider.logScreenView(screenName: screenName, screenClass: screenClass,), destinations: destinations,);
  }


  ScreenAnalytics forScreen(String screenName, {Set<AnalyticsDestination>? destinations,}) {
    return ScreenAnalytics._(this, screenName, destinations);
  }

  Future<void> setUserId(String? userId) async {
    if (!await _awaitReady()) return;
    _userId = userId;
    await _forEachConsented((provider) => provider.setUserId(userId));
  }

  // >>> Sets a user property. Pass a `null` [value] to remove it.
  Future<void> setUserProperty({required String name, required String? value,}) async {
    if (!await _awaitReady()) return;

    try {
      AnalyticsEvent.validateName(name);
    } on ArgumentError catch (error, stackTrace) {
      if (kDebugMode) rethrow;
      AnalyticsLogger.error('Invalid property dropped', error, stackTrace);
      return;
    }

    if (value == null) {
      _userProperties.remove(name);
    } else {
      _userProperties[name] = value;
    }
    await _forEachConsented((provider) => provider.setUserProperty(name: name, value: value),);
  }


  Future<void> logout() async {
    if (!await _awaitReady()) return;
    await flush();
    _userId = null;
    _userProperties.clear();
    await _forEachActive((provider) => provider.reset());
  }


  // >>> Uploads queued events to your backend now.
  Future<void> flush() async {
    if (!await _awaitReady()) return;
    for (final database in _active.whereType<DatabaseAnalytics>()) {
      try {
        await database.flush();
      } catch (error, stackTrace) {
        AnalyticsLogger.error('Flush failed', error, stackTrace);
      }
    }
  }

  // >>> The persistent device id also sent to your backend.
  Future<String> getDeviceId() => _deviceIdService.getDeviceId();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      unawaited(flush());
    }
  }

  // >>> Stops all providers. Normally not needed, because the kit lives as long

  Future<void> dispose() async {
    final wasStarted = _initFuture != null;
    _ready = false;
    _initFuture = null;

    if (wasStarted) WidgetsBinding.instance.removeObserver(this);

    await _forEachActive((provider) => provider.dispose());
    _active.clear();
    _failedProviderIds.clear();

    if (_injectedConsentStore == null) {
      try {
        await _consentStore?.close();
      } catch (error, stackTrace) {
        AnalyticsLogger.error('Could not close consent store', error, stackTrace,);
      }
    }
    _consentStore = null;
  }



  // >>> Providers with consent AND listed in [destinations] (or the default).
  Future<void> _forEachGranted(Future<void> Function(AnalyticsProvider provider) action, {Set<AnalyticsDestination>? destinations,}) {
    final allowed = (destinations ?? _defaultDestinations).map((destination) => destination.providerId).toSet();
    final targets = _active.where((p) => allowed.contains(p.id) && _consent.isGrantedFor(p.id),);
    return _run(targets.toList(), action);
  }

  // >>> Providers with consent, ignoring destinations (used for user data).
  Future<void> _forEachConsented(Future<void> Function(AnalyticsProvider provider) action,) {
    final targets = _active.where((p) => _consent.isGrantedFor(p.id));
    return _run(targets.toList(), action);
  }

  Future<void> _forEachActive(Future<void> Function(AnalyticsProvider provider) action,) {
    return _run(List<AnalyticsProvider>.of(_active), action);
  }

  Future<void> _run(Iterable<AnalyticsProvider> providers, Future<void> Function(AnalyticsProvider provider) action,) {
    return Future.wait(
      providers.map((provider) async {
        try {
          await action(provider);
        } catch (error, stackTrace) {
          AnalyticsLogger.error('Provider "${provider.id}" failed', error, stackTrace,);
        }
      }),
    );
  }
}

/// >>> Logs events for one screen with a fixed set of destinations.
/// >>> Every event automatically gets a `screen_name` parameter.
class ScreenAnalytics {
  ScreenAnalytics._(this._manager, this.screenName, this.destinations);

  final AnalyticsManager _manager;
  final String screenName;

  /// >>> `null` means the app wide default.
  final Set<AnalyticsDestination>? destinations;

  Future<void> logView({String? screenClass}) {
    return _manager.logScreenView(screenName: screenName, screenClass: screenClass, destinations: destinations,);
  }

  Future<void> logEvent(String name, {Map<String, Object?>? parameters}) {
    return _manager.logEvent(name, parameters: <String, Object?>{'screen_name': screenName, ...?parameters,}, destinations: destinations,);
  }
}