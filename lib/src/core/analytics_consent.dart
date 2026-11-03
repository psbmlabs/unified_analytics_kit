import 'analytics_provider.dart';

// >>> Per-provider user consent. Everything is denied by default
class AnalyticsConsent {
  const AnalyticsConsent({this.firebase = false, this.facebook = false, this.database = false,});

  // >>> Grants consent to every built-in provider.
  const AnalyticsConsent.all(): firebase = true, facebook = true, database = true;

  // >>> Denies consent to every built-in provider.
  const AnalyticsConsent.none(): firebase = false, facebook = false, database = false;

  // >>> Restores consent from [toJson] output. Missing keys mean "denied".
  factory AnalyticsConsent.fromJson(Map<String, dynamic> json) {
    return AnalyticsConsent(
      firebase: json['firebase'] == true,
      facebook: json['facebook'] == true,
      database: json['database'] == true,
    );
  }

  final bool firebase;
  final bool facebook;
  final bool database;

  // >>> Whether the provider with [providerId] may collect data.
  // >>> Unknown (custom) providers are denied.
  bool isGrantedFor(String providerId) {
    switch (providerId) {
      case AnalyticsProviderIds.firebase:
        return firebase;
      case AnalyticsProviderIds.facebook:
        return facebook;
      case AnalyticsProviderIds.database:
        return database;
      default:
        return false;
    }
  }

  AnalyticsConsent copyWith({bool? firebase, bool? facebook, bool? database}) {
    return AnalyticsConsent(
      firebase: firebase ?? this.firebase,
      facebook: facebook ?? this.facebook,
      database: database ?? this.database,
    );
  }

  Map<String, dynamic> toJson() => {'firebase': firebase, 'facebook': facebook, 'database': database,};

  @override
  bool operator ==(Object other) => other is AnalyticsConsent && other.firebase == firebase && other.facebook == facebook && other.database == database;

  @override
  int get hashCode => Object.hash(firebase, facebook, database);

  @override
  String toString() => 'AnalyticsConsent(firebase: $firebase, facebook: $facebook, database: $database)';
}