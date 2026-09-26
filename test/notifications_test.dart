import 'dart:async';
import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meiro_sdk/meiro_sdk.dart';
import 'package:meiro_sdk/src/event.dart';
import 'package:meiro_sdk/src/preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const message = RemoteMessage(
    messageId: 'firebase-message',
    data: {
      'is_meiro_message': 'true',
      'message_id': 'pipes-message',
      'title': 'Background push',
      'body': 'Hello from Pipes',
      'action': 'app',
      'test_send_id': 'test-send',
    },
  );

  late FakeLocalNotifications local;
  late FakeMessaging messaging;
  late List<MeiroEventType> events;
  late List<Map<String, Object?>> properties;
  late MeiroNotifications notifications;

  setUp(() {
    local = FakeLocalNotifications();
    messaging = FakeMessaging();
    events = [];
    properties = [];
    notifications = MeiroNotifications(
      configuration: const MeiroPushNotificationsConfiguration(),
      logger: const MeiroConsoleLogger(enabled: false),
      localNotifications: local,
      firebaseMessaging: messaging,
      eventTracker: (type, data) async {
        events.add(type);
        properties.add(data);
      },
    );
  });

  tearDown(() => notifications.dispose());

  test(
      'background data-only message displays and reports without Firebase hooks',
      () async {
    await notifications.init(background: true);
    await notifications.show(message);

    expect(local.titles, ['Background push']);
    expect(events, [MeiroEventType.fcmMessageReceived]);
    expect(properties.single['message_id'], 'pipes-message');
    expect(properties.single['test_send_id'], 'test-send');
    expect(messaging.calls, isEmpty);
    expect(local.launchReads, 0);
    expect(MeiroSdk.isInitialized, isFalse);
    expect(local.settings!.iOS!.requestAlertPermission, isFalse);
  });

  test('background notification payload is tracked without duplicate display',
      () async {
    await notifications.init(background: true);
    await notifications.show(RemoteMessage(
      data: message.data,
      notification: const RemoteNotification(title: 'System notification'),
    ));
    expect(local.titles, isEmpty);
    expect(events, [MeiroEventType.fcmMessageReceived]);
  });

  test('foreground notification payload still displays locally', () async {
    await notifications.init();
    await notifications.show(RemoteMessage(
      data: message.data,
      notification: const RemoteNotification(title: 'System notification'),
    ));
    expect(local.titles, ['Background push']);
    expect(events, [MeiroEventType.fcmMessageReceived]);
  });

  test('local notification cold-start click preserves the Pipes message ID',
      () async {
    local.launch = NotificationAppLaunchDetails(
      true,
      notificationResponse: NotificationResponse(
        notificationResponseType: NotificationResponseType.selectedNotification,
        payload: jsonEncode(
            MeiroNotificationData.fromRemoteMessage(message).toJson()),
      ),
    );
    await notifications.init();
    expect(events, [MeiroEventType.fcmMessageClick]);
    expect(properties.single['message_id'], 'pipes-message');
    expect(properties.single['test_send_id'], 'test-send');
    expect(local.titles, isEmpty);
  });

  test('a slow receipt report cannot delay displaying the notification',
      () async {
    final report = Completer<void>();
    final handler = MeiroNotifications(
      configuration: const MeiroPushNotificationsConfiguration(),
      logger: const MeiroConsoleLogger(enabled: false),
      localNotifications: local,
      firebaseMessaging: messaging,
      eventTracker: (type, properties) => report.future,
    );
    await handler.init(background: true);
    final processing = handler.show(message);
    await Future<void>.delayed(Duration.zero);
    expect(local.titles, ['Background push']);
    report.complete();
    await processing;
    await handler.dispose();
  });

  test('unrelated FCM messages are not displayed or reported', () async {
    await notifications.init(background: true);
    await notifications
        .show(const RemoteMessage(data: {'title': 'Other app flow'}));
    expect(local.titles, isEmpty);
    expect(events, isEmpty);
  });

  test('disabled push handling does not initialize or display notifications',
      () async {
    final handler = MeiroNotifications(
      configuration:
          const MeiroPushNotificationsConfiguration(pushEnabled: false),
      logger: const MeiroConsoleLogger(enabled: false),
      localNotifications: local,
      firebaseMessaging: messaging,
      eventTracker: (type, _) async => events.add(type),
    );
    await handler.init(background: true);
    await handler.show(message);
    expect(local.settings, isNull);
    expect(local.titles, isEmpty);
    expect(events, isEmpty);
    await handler.dispose();
  });

  test('Android Pipes image_url survives local notification serialization', () {
    final data = MeiroNotificationData.fromMap({
      ...message.data,
      'image_url': 'https://example.com/image.png',
    });
    expect(data.imageUrl, 'https://example.com/image.png');
    expect(
        MeiroNotificationData.fromJson(data.toJson()).imageUrl, data.imageUrl);
  });

  test(
      'background entry point ignores non-Meiro messages before initialization',
      () async {
    await MeiroSdk.handleBackgroundMessage(
      const RemoteMessage(data: {'title': 'Other'}),
      configuration: MeiroConfiguration(
        endpoint: Uri.parse('https://pipes.example/collect/mobile-sdk'),
        appId: 'app',
      ),
    );
    expect(MeiroSdk.isInitialized, isFalse);
  });

  test('background preferences reuse identity, token, and disabled tracking',
      () async {
    SharedPreferences.setMockInitialValues({});
    final foreground = await MeiroPreferences.create();
    await foreground.ensureIdentity();
    final userId = foreground.userId;
    foreground.fcmToken = 'fcm-token';
    await foreground.setEnabled(false);

    final background = await MeiroPreferences.create();
    expect(background.hasIdentity, isTrue);
    expect(background.userId, userId);
    expect(background.fcmToken, 'fcm-token');
    expect(background.enabled, isFalse);

    await foreground.resetIdentity();
    final afterReset = await MeiroPreferences.create();
    expect(afterReset.userId, isNot(userId));
    expect(afterReset.userId, foreground.userId);
  });
}

class FakeMessaging extends Fake implements FirebaseMessaging {
  final List<String> calls = [];

  @override
  Stream<String> get onTokenRefresh {
    calls.add('onTokenRefresh');
    return const Stream.empty();
  }

  @override
  Future<String?> getToken({String? vapidKey}) async {
    calls.add('getToken');
    return null;
  }

  @override
  Future<RemoteMessage?> getInitialMessage() async {
    calls.add('getInitialMessage');
    return null;
  }
}

class FakeLocalNotifications extends Fake
    implements FlutterLocalNotificationsPlugin {
  final List<String?> titles = [];
  InitializationSettings? settings;
  NotificationAppLaunchDetails? launch;
  int launchReads = 0;

  @override
  Future<bool?> initialize(
    InitializationSettings initializationSettings, {
    DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
    DidReceiveBackgroundNotificationResponseCallback?
        onDidReceiveBackgroundNotificationResponse,
  }) async {
    settings = initializationSettings;
    return true;
  }

  @override
  Future<NotificationAppLaunchDetails?>
      getNotificationAppLaunchDetails() async {
    launchReads++;
    return launch;
  }

  @override
  Future<void> show(int id, String? title, String? body,
      NotificationDetails? notificationDetails,
      {String? payload}) async {
    titles.add(title);
  }
}
