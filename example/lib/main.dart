import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:meiro_sdk/meiro_sdk.dart';

MeiroConfiguration sdkConfiguration(FirebaseApp app) => MeiroConfiguration(
      endpoint: Uri.parse(
        const String.fromEnvironment(
          'PIPES_COLLECTION_URL',
          defaultValue:
              'https://flutter-sdk-test.dev.pipes.meiro.io/collect/mobile-sdk',
        ),
      ),
      appId: app.options.appId,
      firebaseProjectId: app.options.projectId,
      debugMode: true,
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
  final FirebaseApp firebaseApp = await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(firebaseBackgroundMessage);
  await FirebaseMessaging.instance.requestPermission();

  await MeiroSdk.init(
    configuration: sdkConfiguration(firebaseApp),
  );

  debugPrint('FCM token: ${await FirebaseMessaging.instance.getToken()}');

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
      body: Center(
        child: FilledButton(
          onPressed: () => Navigator.of(context).pushNamed('/second'),
          child: const Text('Go to second screen'),
        ),
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
