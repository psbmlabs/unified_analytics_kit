import 'analytics_consent.dart';
import 'analytics_destination.dart';


class AnalyticsConfig {

  AnalyticsConfig({
    this.enableFirebase = true,
    this.enableFacebook = true,
    this.enableDatabase = false,
    this.databaseEndpoint,
    this.apiKey,
    this.allowInsecureHttp = false,
    this.batchSize = 20,
    this.flushInterval = const Duration(seconds: 30),
    this.maxQueueSize = 1000,
    this.maxRetries = 5,
    this.requestTimeout = const Duration(seconds: 15),
    this.debugLogging = false,
    this.defaultConsent = const AnalyticsConsent.none(),
    this.defaultDestinations = AnalyticsDestination.all,
  }) {
    if (defaultDestinations.isEmpty) {
      throw ArgumentError.value(defaultDestinations, 'defaultDestinations', 'Must contain at least one destination.',);
    }
    if (batchSize < 1 || batchSize > 500) {
      throw ArgumentError.value(batchSize, 'batchSize', 'Must be 1-500.');
    }
    if (maxQueueSize < batchSize) {
      throw ArgumentError.value(maxQueueSize, 'maxQueueSize', 'Must be >= batchSize.',);
    }
    if (maxRetries < 0) {
      throw ArgumentError.value(maxRetries, 'maxRetries', 'Must be >= 0.');
    }
    if (flushInterval < const Duration(seconds: 5)) {
      throw ArgumentError.value(flushInterval, 'flushInterval', 'Must be at least 5 seconds.',);
    }
    if (enableDatabase) {
      final uri = databaseEndpoint;
      if (uri == null || !uri.hasAuthority) {
        throw ArgumentError.value(databaseEndpoint, 'databaseEndpoint', 'A valid absolute URL is required when enableDatabase is true.',);
      }
      if (uri.scheme != 'https' && !(allowInsecureHttp && uri.scheme == 'http')) {
        throw ArgumentError.value(databaseEndpoint, 'databaseEndpoint', 'HTTPS is required. Use allowInsecureHttp only for local testing.',);
      }
    }
  }

  final bool enableFirebase;
  final bool enableFacebook;
  final bool enableDatabase;

  // >>>Backend URL that receives event batches.
  final Uri? databaseEndpoint;

  // >>> Sent as `X-Api-Key`. NOT a secret, since it ships inside the app. The backend must still validate and rate limit requests.
  final String? apiKey;

  // >>> Allows `http://` endpoints. For local development only.
  final bool allowInsecureHttp;

  // >>> Events per upload request.
  final int batchSize;

  // >>> How often the queue is flushed automatically.
  final Duration flushInterval;

  // >>> Oldest events are dropped when the offline queue exceeds this size.
  final int maxQueueSize;

  // >>> Upload attempts before an event batch is retried only on next launch.
  final int maxRetries;

  final Duration requestTimeout;

  final bool debugLogging;

  // >>> Consent used before the user makes a choice.
  final AnalyticsConsent defaultConsent;

  // >>> Destinations used when a call does not name its own.
  final Set<AnalyticsDestination> defaultDestinations;
}