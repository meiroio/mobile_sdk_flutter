# Meiro Flutter SDK

Meiro Flutter SDK collects mobile events from Flutter applications and sends them to Meiro Data Platform.

The SDK supports Android and iOS.

## Installation

Add the package to your app:

```yaml
dependencies:
  meiro_sdk:
    git:
      url: https://github.com/meiroio/mobile_sdk_flutter.git
```

The repository is currently private and `publish_to` is disabled.

## Getting Started

Initialize the SDK before `runApp`:

```dart
import 'package:flutter/material.dart';
import 'package:meiro_sdk/meiro_sdk.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await MeiroSdk.init(
    configuration: MeiroConfiguration(
      endpoint: Uri.parse('https://my.meiro.endpoint/'),
      appId: 'your-app-id',
      firebaseProjectId: 'your-firebase-project-id',
      debugMode: true,
    ),
  );

  runApp(const App());
}
```

## Configuration

```dart
MeiroConfiguration(
  endpoint: Uri.parse('https://my.meiro.endpoint/'),
  appId: 'your-app-id',
  debugMode: false,
  language: 'en',
  firebaseProjectId: 'firebase-project-id',
  automaticTrackingOptions: const MeiroAutomaticTrackingOptions(
    screenViewTracking: true,
    lifecycleEventsTracking: true,
    adIdTracking: true,
  ),
  pushNotifications: const MeiroPushNotificationsConfiguration(
    pushEnabled: true,
    channelId: 'meiro_notifications',
    channelName: 'Meiro',
    channelDescription: 'Notifications',
    androidSmallIcon: '@mipmap/ic_launcher',
  ),
)
```

## Event Tracking

```dart
await MeiroSdk.trackCustomEvent({
  'name': 'App opened',
  'product_id': '123',
});

await MeiroSdk.trackLinkClick(Uri.parse('https://example.com'));

await MeiroSdk.trackScreenView(
  'product_detail',
  properties: {'product_id': '123'},
);
```

The SDK automatically attaches app, OS, device, Firebase, user, and session metadata.

## Screen Tracking

For Flutter navigation, add `MeiroNavigatorObserver`:

```dart
MaterialApp(
  navigatorObservers: [MeiroNavigatorObserver()],
  routes: {
    '/': (_) => const HomeScreen(),
    '/details': (_) => const DetailsScreen(),
  },
)
```

The default observer uses `route.settings.name` as the screen name. For custom routers, provide a custom resolver or call `MeiroSdk.trackScreenView` manually.

## Push Messaging

The SDK integrates with `firebase_messaging` and `flutter_local_notifications`.

When `endpoint` is a Pipes `/collect/:sourceSlug` URL, the SDK automatically
sends Mobile Push reports to `/api/channels/push/events` on the same host.

When `pushEnabled` is true:

- FCM token refreshes are passed to `MeiroSdk.setFcmToken`.
- Meiro foreground messages are displayed locally.
- `fcm_message_received` and `fcm_message_click` events are tracked.
- Click actions support `app`, `browser`, and `deeplink`.

The SDK does not request notification permissions. Your app must request permissions on Android 13+ and iOS.

### Background and closed-app notifications

Register a Firebase background callback before `runApp`. Initialize Firebase
there and pass the same Meiro configuration used by your foreground app:

```dart
@pragma('vm:entry-point')
Future<void> firebaseBackgroundMessage(RemoteMessage message) async {
  await Firebase.initializeApp();
  await MeiroSdk.handleBackgroundMessage(
    message,
    configuration: meiroConfiguration,
  );
}

// In main(), after Firebase.initializeApp() and before runApp():
FirebaseMessaging.onBackgroundMessage(firebaseBackgroundMessage);
```

Import `firebase_core` and `firebase_messaging` in the app. Define
`meiroConfiguration` as a top-level constant, getter, or function result that
can be recreated in the background isolate, not a value assigned only in
`main()`. Use the same Firebase initialization options in both entry points.
Do not call `MeiroSdk.init` in this background callback.

If your app already has a Firebase background callback, call
`MeiroSdk.handleBackgroundMessage` from it instead of registering another one.
Non-Meiro messages are ignored. The SDK displays data-only messages, reports
receipt using the stored user ID and FCM token, and queues failed reports for
the next foreground sync. Messages with a Firebase notification payload are
not displayed a second time. Local notification taps are also reported when
they start the app from a closed state.

The SDK must have been initialized once in the foreground. Tracking disabled
with `MeiroSdk.setEnabled(false)` remains disabled across restarts and background
callbacks; it does not disable notification display. Set `pushEnabled: false`
to disable Meiro push handling. Android Force stop blocks delivery until the
user manually opens the app again. iOS background delivery depends on the app's
capabilities and APNs configuration and is not guaranteed.

For custom FCM handling, check messages with:

```dart
if (MeiroNotifications.isMeiroMessage(message)) {
  await MeiroSdk.showRemoteMessage(message);
}
```

## V1 Audience API

```dart
final result = await MeiroSdk.audience.wbs(
  instanceUrl: Uri.parse('https://cdp.client-instance.meiro.app'),
  segment: 42,
  parameters: {'category_id': '1305'},
);

print(result.returnedAttributes);
print(result.data);
```

## V2 Profile API

Create a Profile API endpoint in V2 Pipes that allows the `mobile_user_id`
identifier type. Pass its complete endpoint URL and use the SDK user ID for the
lookup:

```dart
import 'package:meiro_sdk/meiro_sdk.dart';

final profileApi = MeiroProfile(
  endpoint: Uri.parse(
    'https://pipes.example.com/profile-api/mobile-app',
  ),
  apiKey: 'optional-profile-api-key',
);

final profile = await profileApi.getProfile(
  identifierValue: MeiroSdk.userId,
);

print(profile.profileId);
print(profile.attributes);
print(profile.audiences);
```

Profile API keys embedded in a mobile application can be extracted. Use a
backend proxy when the returned profile data requires real authorization.

## Offline Support

Events are sent immediately. If sending fails, the serialized event payload is stored in a local SQLite queue for up to 24 hours. The SDK retries queued events on app start, foreground, and network connectivity changes.

## Advertising ID

When `adIdTracking` is enabled, the SDK attempts to resolve the advertising ID using the `advertising_id` plugin.

Apps are responsible for platform policy and permission requirements:

- Android apps using advertising ID must satisfy Google Play AD_ID declaration requirements.
- iOS apps must handle App Tracking Transparency before IDFA can be returned.

## Development

Expected checks:

```sh
flutter pub get
flutter analyze
flutter test
```
