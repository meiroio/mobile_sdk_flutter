import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:meiro_sdk/meiro_sdk.dart';

final appNavigatorKey = GlobalKey<NavigatorState>();

MeiroConfiguration sdkConfiguration(FirebaseApp? app) => MeiroConfiguration(
      endpoint: Uri.parse(
        const String.fromEnvironment(
          'PIPES_COLLECTION_URL',
          defaultValue:
              'https://flutter-sdk-test.dev.pipes.meiro.io/collect/mobile-sdk',
        ),
      ),
      appId: app?.options.appId ??
          const String.fromEnvironment('MEIRO_APP_ID',
              defaultValue: 'io.meiro.meiroSdkExample'),
      firebaseProjectId: app?.options.projectId,
      pushNotifications: MeiroPushNotificationsConfiguration(
        pushEnabled: app != null,
      ),
      debugMode: true,
      inAppMessagingEnabled: true,
      navigatorKey: appNavigatorKey,
    );

@pragma('vm:entry-point')
Future<void> firebaseBackgroundMessage(RemoteMessage message) async {
  final app = await Firebase.initializeApp();
  await MeiroSdk.handleBackgroundMessage(
    message,
    configuration: sdkConfiguration(app),
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FirebaseApp? firebaseApp;
  try {
    firebaseApp = await Firebase.initializeApp();
  } catch (error) {
    debugPrint('Firebase is unavailable; push demo disabled: $error');
  }
  if (firebaseApp != null) {
    FirebaseMessaging.onBackgroundMessage(firebaseBackgroundMessage);
    await FirebaseMessaging.instance.requestPermission();
  }

  await MeiroSdk.init(
    configuration: sdkConfiguration(firebaseApp),
  );
  MeiroSdk.inAppMessaging?.onDiagnostic =
      (message) => debugPrint('[MeiroInApp] $message');

  if (firebaseApp != null) {
    debugPrint('FCM token: ${await FirebaseMessaging.instance.getToken()}');
  }

  await MeiroSdk.trackCustomEvent({'name': 'App opened'});

  runApp(const ExampleApp());
}

/// Example application.
class ExampleApp extends StatelessWidget {
  /// Creates the example application.
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: appNavigatorKey,
      navigatorObservers: [MeiroNavigatorObserver()],
      routes: {
        '/': (_) => const FirstScreen(),
        '/second': (_) => const SecondScreen(),
      },
    );
  }
}

/// First example screen.
class FirstScreen extends StatelessWidget {
  /// Creates the first example screen.
  const FirstScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('First screen')),
      body: ListView(
        children: [
          MeiroInAppMessageView(
            placement: 'home_promotion',
            messaging: MeiroSdk.inAppMessaging,
          ),
          MeiroInAppMessageView(
            placement: 'home_stories',
            messaging: MeiroSdk.inAppMessaging,
          ),
          FilledButton(
            onPressed: () => MeiroSdk.trackCustomEvent({'name': 'show_offer'}),
            child: const Text('Trigger in-app offer'),
          ),
          FilledButton(
            onPressed: () => MeiroSdk.trackCustomEvent({'name': 'show_image'}),
            child: const Text('Trigger in-app image'),
          ),
          FilledButton(
            onPressed: () => MeiroSdk.trackCustomEvent({'name': 'show_survey'}),
            child: const Text('Trigger in-app survey'),
          ),
          FilledButton(
            onPressed: MeiroSdk.resetIdentity,
            child: const Text('Reset test identity'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pushNamed('/second'),
            child: const Text('Go to second screen'),
          ),
        ],
      ),
    );
  }
}

/// Second example screen.
class SecondScreen extends StatelessWidget {
  /// Creates the second example screen.
  const SecondScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: Text('Second screen')),
    );
  }
}
