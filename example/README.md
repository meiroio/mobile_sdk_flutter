# Meiro Flutter SDK example

The app can run without Firebase; push handling is disabled when Firebase has no
platform configuration. To test push, place your Android Firebase
`google-services.json` at `android/app/google-services.json` before building.
The iOS host runs in a simulator without Firebase or an ATT usage description;
push is disabled and no tracking prompt appears in that setup. To try it, run
`flutter run -d <ios-simulator-id>` from `example`.
For a manual in-app walkthrough on iOS, run
`flutter test integration_test/in_app_ios_test.dart -d <ios-simulator-id>`.
It uses the live endpoint and prints `SHOT:` markers for screenshots.
The default in-app endpoint is the Flutter SDK test instance's `mobile-sdk` source:

```sh
cd example
flutter run -d <android-device-id>
```

Use `--dart-define=PIPES_COLLECTION_URL=<url>` to target another collection
endpoint, and `--dart-define=MEIRO_APP_ID=<id>` when Firebase is unavailable.
The offer, image, and survey buttons send `show_offer`, `show_image`, and
`show_survey`. The home screen mounts `home_promotion` and `home_stories`;
navigation to the second screen sends a `/second` screen view. The test
instance allows one in-app display per identity every 12 hours, so use
**Reset test identity** before testing another format. The example registers
`meiro-example` as an app link scheme for story actions.

## Closed-app push test on Android

Run the app once with Firebase configured and copy the `FCM token:` line from
Flutter logs. In Pipes, open a saved Mobile Push campaign's **Review** tab,
enter that token as an Android test recipient, select a realtime profile for
personalization, and send a test push. Put the app in the background and stop
its process before sending if you want to test a cold start:

```sh
adb shell input keyevent KEYCODE_HOME
adb shell am kill io.meiro.testfluttersdk
```

The notification should appear in Android's shade and open the app when
tapped. Android **Force stop** prevents FCM delivery until the app is opened
again, so do not use it for this test.
