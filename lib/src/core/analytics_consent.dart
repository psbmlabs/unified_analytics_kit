import 'analytics_provider.dart';

// >>> Per-provider user consent. Everything is denied by default
class AnalyticsConsent {
  const AnalyticsConsent({this.firebase = false, this.facebook = false, this.database = false, this.deviceInfo = true,});

  // >>> Grants consent to every built-in provider.
  const AnalyticsConsent.all(): firebase = true, facebook = true, database = true, deviceInfo = true;

  // >>> Denies consent to every built-in provider.
  const AnalyticsConsent.none(): firebase = false, facebook = false, database = false, deviceInfo = false;

  // >>> Restores consent from [toJson] output. Missing keys mean "denied".
  factory AnalyticsConsent.fromJson(Map<String, dynamic> json) {
    return AnalyticsConsent(
      firebase: json['firebase'] == true,
      facebook: json['facebook'] == true,
      database: json['database'] == true,
      // >>> Old saved data has no `deviceInfo` key: treat it as granted, so nothing changes for existing users.
      deviceInfo: json['deviceInfo'] != false,
    );
  }

  final bool firebase;
  final bool facebook;
  final bool database;

  // >>> Only matters when [database] is granted.
  // >>> true  = the backend gets the device id, device info and user properties.
  // >>> false = anonymous mode: events still go, but with a fixed `anonymous-<platform>` device id
  // >>>         and only the platform. A user id (if the app set one) is still sent.
  final bool deviceInfo;

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

  AnalyticsConsent copyWith({bool? firebase, bool? facebook, bool? database, bool? deviceInfo}) {
    return AnalyticsConsent(
      firebase: firebase ?? this.firebase,
      facebook: facebook ?? this.facebook,
      database: database ?? this.database,
      deviceInfo: deviceInfo ?? this.deviceInfo,
    );
  }

  Map<String, dynamic> toJson() => {'firebase': firebase, 'facebook': facebook, 'database': database, 'deviceInfo': deviceInfo,};

  @override
  bool operator ==(Object other) => other is AnalyticsConsent && other.firebase == firebase && other.facebook == facebook && other.database == database && other.deviceInfo == deviceInfo;

  @override
  int get hashCode => Object.hash(firebase, facebook, database, deviceInfo);

  @override
  String toString() => 'AnalyticsConsent(firebase: $firebase, facebook: $facebook, database: $database, deviceInfo: $deviceInfo)';
}