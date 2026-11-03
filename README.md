# unified_analytics_kit

A Flutter analytics toolkit that sends events to **Firebase**, **Facebook App Events** and **your own backend** through one API. It adds a persistent device ID, an offline queue and per-provider user consent.

## Features

- One call (`logEvent`) reaches Firebase, Facebook and your backend.
- Choose where data goes: app-wide, per screen, or per call.
- Consent is denied by default and tracked per provider.
- Persistent device ID that survives reinstall where the OS allows it.
- Offline queue (Hive) with batching, retry, backoff and `Retry-After` support.
- One failing provider never affects the others.
- Event name and parameter validation that satisfies Firebase and Facebook rules.

## Installation

Add the package from GitHub. Pin a tag so other projects do not break on updates.

```yaml
dependencies:
  unified_analytics_kit:
    git:
      url: https://github.com/psbmlabs/unified_analytics_kit.git
      ref: v0.0.1
```

Then run `flutter pub get`.

## Platform setup

This package does not configure Firebase or Facebook for you. Those config files belong to your app.

| Provider | What your app must do |
|---|---|
| Firebase | Add `google-services.json` (Android) and `GoogleService-Info.plist` (iOS), then call `Firebase.initializeApp()` before the kit. See the [FlutterFire docs](https://firebase.flutter.dev/docs/overview). |
| Facebook | Add your Facebook App ID and Client Token to the Android manifest and iOS `Info.plist`. See the [facebook_app_events docs](https://pub.dev/packages/facebook_app_events). |
| Database | Nothing native. You only need a backend that accepts the payload described below. |

Disable any provider you do not use in `AnalyticsConfig` and skip its setup.

## Quick start

```dart
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';
import 'package:unified_analytics_kit/unified_analytics_kit.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  await AnalyticsManager.instance.initialize(
    AnalyticsConfig(
      enableFirebase: true,
      enableFacebook: true,
      enableDatabase: true,
      databaseEndpoint: Uri.parse('https://api.example.com/v1/events'),
      apiKey: 'your-public-app-key',
    ),
  );

  runApp(const MyApp());
}
```

Log events:

```dart
AnalyticsManager.instance.logEvent('app_open');

AnalyticsManager.instance.logEvent(
  'product_viewed',
  parameters: {'product_id': 'p_42', 'price': 9.5},
);

AnalyticsManager.instance.logScreenView(screenName: 'Home');
```

## Consent

Nothing is sent until the user grants consent. Consent is stored on the device and restored on the next launch. It is stored in Hive, so it is removed when the app is uninstalled.

```dart
final analytics = AnalyticsManager.instance;

if (!analytics.hasConsentDecision) {
  // Show your own consent dialog, then:
  await analytics.setConsent(const AnalyticsConsent.all());
  // or choose per provider:
  // await analytics.setConsent(const AnalyticsConsent(firebase: true, database: true));
}
```

Revoking consent turns collection off for that provider, clears its user data and, for the database provider, deletes queued events.

## Choosing destinations

An event reaches a provider only when **all three** are true:

1. The provider is enabled in `AnalyticsConfig`.
2. The user granted consent for it.
3. The call (or its scope) allows it as a destination.

Priority, highest first:

| Level | Where | Example |
|---|---|---|
| Call | `destinations:` argument | `logEvent('purchase', destinations: {AnalyticsDestination.facebook})` |
| Screen | `forScreen(...)` | all events of one screen go only to the database |
| App | `AnalyticsConfig.defaultDestinations` | default for everything else |

```dart
// App-wide default: Firebase + database, never Facebook.
AnalyticsConfig(
  defaultDestinations: {
    AnalyticsDestination.firebase,
    AnalyticsDestination.database,
  },
);

// One screen only to the database.
final screen = AnalyticsManager.instance.forScreen(
  'ProductDetails',
  destinations: {AnalyticsDestination.database},
);
screen.logView();
screen.logEvent('product_viewed', parameters: {'product_id': 'p_42'});
```

`ScreenAnalytics.logEvent` adds a `screen_name` parameter automatically. An empty `destinations` set sends nothing.

`setUserId` and `setUserProperty` go to every provider that has consent, regardless of destinations.

## Users

```dart
await AnalyticsManager.instance.setUserId('user_12345');
await AnalyticsManager.instance.setUserProperty(name: 'plan', value: 'pro');

// On logout: uploads pending events first, then clears the user.
await AnalyticsManager.instance.logout();
```

Use your own account ID. Never pass an email address or phone number as a user ID or event parameter. Firebase and Facebook forbid it.

Facebook has no generic custom user properties, so `setUserProperty` is ignored there. Firebase and your backend store them.

## Device ID

```dart
final id = await AnalyticsManager.instance.getDeviceId();
```

| Platform | Source | After uninstall |
|---|---|---|
| Android | SHA-256 of `ANDROID_ID` | Same if the app is signed with the same key. Changes on factory reset. |
| iOS | Random UUID stored in the Keychain | Usually kept, but Apple does not guarantee it. |

Debug, release and Play App Signing builds use different signing keys, so they can produce different IDs on Android. This is Android behavior, not a bug.

No IMEI, MAC address or serial number is ever read.

## Backend contract

The database provider sends `POST` requests with JSON.

Headers:

```
Content-Type: application/json; charset=utf-8
Accept: application/json
X-Api-Key: <apiKey>      (only when configured)
```

Body:

```json
{
  "schema_version": 1,
  "sent_at": "2026-01-01T10:00:00.000Z",
  "device_id": "3f2a...",
  "user_id": "user_12345",
  "user_properties": { "plan": "pro" },
  "device": {
    "platform": "android",
    "os_version": "14",
    "model": "Pixel 8",
    "manufacturer": "Google",
    "is_physical_device": true,
    "app_version": "1.0.0",
    "build_number": "1",
    "package_name": "com.example.app",
    "locale": "bn-BD",
    "timezone": "BDT",
    "timezone_offset_minutes": 360
  },
  "events": [
    {
      "id": "b1c2...",
      "name": "product_viewed",
      "parameters": { "product_id": "p_42" },
      "timestamp": "2026-01-01T09:59:58.000Z"
    }
  ]
}
```

`user_id` and `user_properties` are omitted when empty. `events[].id` is a UUID. Use it to ignore duplicates, because a batch can be delivered more than once.

How the client treats responses:

| Response | Client action |
|---|---|
| `2xx` | Success, events are removed from the queue. |
| `400`, `413`, `422` | Batch is rejected and dropped. Retrying would not help. |
| `429`, `5xx`, `401`, `403`, timeout, no network | Events stay queued and are retried with backoff (5s up to 5 minutes). A `Retry-After` header in seconds is honored, capped at 1 hour. |

HTTPS is required. `allowInsecureHttp: true` allows `http://` for local testing only.

> The `apiKey` ships inside your app, so it is **not a secret**. Your backend must still validate payloads and rate limit requests.

## Configuration

| Option | Default | Description |
|---|---|---|
| `enableFirebase` | `true` | Send to Firebase Analytics. |
| `enableFacebook` | `true` | Send to Facebook App Events. |
| `enableDatabase` | `false` | Send to your backend. Needs `databaseEndpoint`. |
| `databaseEndpoint` | none | Backend URL. |
| `apiKey` | none | Sent as `X-Api-Key`. |
| `allowInsecureHttp` | `false` | Allow `http://` (development only). |
| `batchSize` | `20` | Events per request (1 to 500). |
| `flushInterval` | 30 s | Automatic upload interval (minimum 5 s). |
| `maxQueueSize` | `1000` | Oldest events are dropped beyond this. |
| `maxRetries` | `5` | Consecutive failures before pausing until the next launch. |
| `requestTimeout` | 15 s | Per request timeout. |
| `debugLogging` | `false` | Print internal logs. |
| `defaultConsent` | none granted | Consent used before the user decides. |
| `defaultDestinations` | all | Destinations used when a call names none. |

Invalid settings throw `ArgumentError` at startup.

## Event rules

- Name: 1 to 40 characters, starts with a letter, only letters, digits and `_`.
- Reserved prefixes `firebase_`, `google_` and `ga_` are rejected.
- Up to 25 parameters. Values are `String`, `int`, `double` or `bool`. `null` values are dropped. Strings longer than 100 characters are truncated.
- Invalid input throws `ArgumentError` in debug builds and is silently dropped in release builds.

## Privacy and store policies

- Declare device ID collection in your Google Play **Data safety** form.
- Publish a privacy policy that describes Firebase, Facebook and your backend.
- On iOS, show the App Tracking Transparency prompt yourself (for example with `app_tracking_transparency`) before enabling Facebook tracking.
- Ask for consent where required (GDPR and similar laws).

## Known limitations

- Firebase assigns its own event time, so `event.timestamp` is only kept in your database.
- If a user logs out while offline, queued events are uploaded later without `user_id`.
- Device ID persistence after uninstall cannot be guaranteed on iOS.

## Testing

```bash
flutter test
```

## License

MIT. See [LICENSE](LICENSE).