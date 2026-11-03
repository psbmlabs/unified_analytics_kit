import 'analytics_provider.dart';

// >>> Where an event may be sent.
enum AnalyticsDestination {
  firebase(AnalyticsProviderIds.firebase),
  facebook(AnalyticsProviderIds.facebook),
  database(AnalyticsProviderIds.database);

  const AnalyticsDestination(this.providerId);

  // >>> Id of the matching [AnalyticsProvider].
  final String providerId;

  // >>> Every destination. This is the default.
  static const Set<AnalyticsDestination> all = {firebase, facebook, database};
}