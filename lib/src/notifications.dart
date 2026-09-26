import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'configuration.dart';
import 'event.dart';
import 'meiro_sdk.dart';

/// Push notification action.
sealed class MeiroNotificationAction {
  const MeiroNotificationAction();

  /// Opens the app.
  const factory MeiroNotificationAction.app() = MeiroNotificationAppAction;

  /// Opens a deeplink.
  const factory MeiroNotificationAction.deepLink(Uri url) =
      MeiroNotificationDeepLinkAction;

  /// Opens a browser URL.
  const factory MeiroNotificationAction.browser(Uri url) =
      MeiroNotificationBrowserAction;

  /// Action identifier sent to the event API.
  String get eventValue {
    return switch (this) {
      MeiroNotificationAppAction() => 'app',
      MeiroNotificationDeepLinkAction() => 'deeplink',
      MeiroNotificationBrowserAction() => 'browser',
    };
  }

  /// URL associated with the action.
  Uri? get url {
    return switch (this) {
      MeiroNotificationAppAction() => null,
      MeiroNotificationDeepLinkAction(:final url) => url,
      MeiroNotificationBrowserAction(:final url) => url,
    };
  }
}

/// App notification action.
final class MeiroNotificationAppAction extends MeiroNotificationAction {
  /// Creates an app action.
  const MeiroNotificationAppAction();
}

/// Deeplink notification action.
final class MeiroNotificationDeepLinkAction extends MeiroNotificationAction {
  /// Creates a deeplink action.
  const MeiroNotificationDeepLinkAction(this.url);

  /// Deeplink URL.
  @override
  final Uri url;
}

/// Browser notification action.
final class MeiroNotificationBrowserAction extends MeiroNotificationAction {
  /// Creates a browser action.
  const MeiroNotificationBrowserAction(this.url);

  /// Browser URL.
  @override
  final Uri url;
}

/// Parsed Meiro notification payload.
class MeiroNotificationData {
  /// Creates notification data.
  const MeiroNotificationData({
    required this.id,
    required this.googleMessageId,
    required this.title,
    required this.body,
    required this.action,
    this.imageUrl,
    this.payload = const <String, String>{},
  });

  /// Creates notification data from an FCM remote message.
  factory MeiroNotificationData.fromRemoteMessage(RemoteMessage message) {
    return MeiroNotificationData.fromMap(
      message.data,
      googleMessageId: message.messageId ?? '',
    );
  }

  /// Creates notification data from a map.
  factory MeiroNotificationData.fromMap(
    Map<String, dynamic> data, {
    String googleMessageId = '',
  }) {
    final actionText = data[_actionKey]?.toString();
    final urlText = data[_urlKey]?.toString();
    final url =
        urlText == null || urlText.isEmpty ? null : Uri.tryParse(urlText);
    final action = switch (actionText) {
      _deeplinkAction when url != null => MeiroNotificationAction.deepLink(url),
      _browserAction when url != null => MeiroNotificationAction.browser(url),
      _ => const MeiroNotificationAction.app(),
    };

    return MeiroNotificationData(
      id: data[_messageIdKey]?.toString() ?? '',
      googleMessageId: googleMessageId,
      title: data[_titleKey]?.toString() ?? '',
      body: data[_bodyKey]?.toString() ?? '',
      imageUrl: (data[_androidImageKey] ?? data[_imageKey])?.toString(),
      action: action,
      payload: {
        for (final entry in data.entries)
          if (!_reservedKeys.contains(entry.key))
            entry.key: entry.value.toString(),
      },
    );
  }

  /// Message id.
  final String id;

  /// Google message id.
  final String googleMessageId;

  /// Notification title.
  final String title;

  /// Notification body.
  final String body;

  /// Optional image URL.
  final String? imageUrl;

  /// Click action.
  final MeiroNotificationAction action;

  /// Additional custom payload.
  final Map<String, String> payload;

  /// Converts notification data to event properties.
  Map<String, Object?> toEventProperties() {
    return <String, Object?>{
      _messageIdKey: id,
      _titleKey: title,
      _bodyKey: body,
      _actionKey: action.eventValue,
      _urlKey: action.url?.toString() ?? '',
      _imageKey: imageUrl ?? '',
      ...payload.map((key, value) {
        try {
          return MapEntry(key, jsonDecode(value) as Object?);
        } catch (_) {
          return MapEntry(key, value);
        }
      }),
    };
  }

  /// Converts notification data to a JSON map.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      _messageIdKey: id,
      'google_message_id': googleMessageId,
      _titleKey: title,
      _bodyKey: body,
      _imageKey: imageUrl,
      _actionKey: action.eventValue,
      _urlKey: action.url?.toString(),
      'payload': payload,
    };
  }

  /// Creates notification data from JSON.
  static MeiroNotificationData fromJson(Map<String, Object?> json) {
    final payload = ((json['payload'] as Map?) ?? const {}).map<String, String>(
      (key, value) => MapEntry(key.toString(), value.toString()),
    );
    return MeiroNotificationData.fromMap(
      <String, dynamic>{
        _messageIdKey: json[_messageIdKey],
        _titleKey: json[_titleKey],
        _bodyKey: json[_bodyKey],
        _imageKey: json[_imageKey],
        _actionKey: json[_actionKey],
        _urlKey: json[_urlKey],
        ...payload,
      },
      googleMessageId: json['google_message_id']?.toString() ?? '',
    );
  }

  static const _messageIdKey = 'message_id';
  static const _titleKey = 'title';
  static const _bodyKey = 'body';
  static const _imageKey = 'image';
  static const _androidImageKey = 'image_url';
  static const _actionKey = 'action';
  static const _urlKey = 'url';
  static const _browserAction = 'browser';
  static const _deeplinkAction = 'deeplink';

  /// Data payload key used to identify Meiro FCM messages.
  static const isMeiroMessageKey = 'is_meiro_message';

  static const _reservedKeys = {
    _messageIdKey,
    _titleKey,
    _bodyKey,
    _imageKey,
    _androidImageKey,
    _actionKey,
    _urlKey,
    isMeiroMessageKey,
  };
}

/// Meiro push notification handling.
class MeiroNotifications {
  /// Creates Meiro notification handling.
  MeiroNotifications({
    required MeiroPushNotificationsConfiguration configuration,
    required MeiroLogger logger,
    FlutterLocalNotificationsPlugin? localNotifications,
    FirebaseMessaging? firebaseMessaging,
    http.Client? httpClient,
    Future<void> Function(MeiroEventType, Map<String, Object?>)? eventTracker,
  })  : _configuration = configuration,
        _logger = logger,
        _localNotifications =
            localNotifications ?? FlutterLocalNotificationsPlugin(),
        _firebaseMessaging = firebaseMessaging ?? FirebaseMessaging.instance,
        _httpClient = httpClient ?? http.Client(),
        _eventTracker = eventTracker ?? MeiroSdk.trackInternal;

  final MeiroPushNotificationsConfiguration _configuration;
  final MeiroLogger _logger;
  final FlutterLocalNotificationsPlugin _localNotifications;
  final FirebaseMessaging _firebaseMessaging;
  final http.Client _httpClient;
  final Future<void> Function(MeiroEventType, Map<String, Object?>)
      _eventTracker;
  bool _background = false;

  StreamSubscription<RemoteMessage>? _messageSubscription;
  StreamSubscription<String>? _tokenSubscription;
  StreamSubscription<RemoteMessage>? _openedSubscription;

  /// Checks whether a remote message is sent by Meiro.
  static bool isMeiroMessage(RemoteMessage message) {
    return message.data.containsKey(MeiroNotificationData.isMeiroMessageKey);
  }

  /// Initializes Firebase and local notification hooks.
  Future<void> init({bool background = false}) async {
    if (!_configuration.pushEnabled) {
      return;
    }

    _background = background;
    await _localNotifications.initialize(
      InitializationSettings(
        android: AndroidInitializationSettings(
          _configuration.androidSmallIcon ?? '@mipmap/ic_launcher',
        ),
        iOS: const DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: _handleLocalNotificationResponse,
    );

    if (background) {
      return;
    }

    final launch = await _localNotifications.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp ?? false) {
      await _trackLocalNotificationPayload(
          launch?.notificationResponse?.payload);
    }

    _messageSubscription = FirebaseMessaging.onMessage.listen((message) {
      if (isMeiroMessage(message)) {
        unawaited(show(message));
      }
    });
    _openedSubscription =
        FirebaseMessaging.onMessageOpenedApp.listen((message) {
      if (isMeiroMessage(message)) {
        unawaited(trackClick(MeiroNotificationData.fromRemoteMessage(message)));
      }
    });
    _tokenSubscription = _firebaseMessaging.onTokenRefresh.listen((token) {
      unawaited(MeiroSdk.setFcmToken(token));
    });

    final initialToken = await _firebaseMessaging.getToken();
    if (initialToken != null) {
      await MeiroSdk.setFcmToken(initialToken);
    }

    final initialMessage = await _firebaseMessaging.getInitialMessage();
    if (initialMessage != null && isMeiroMessage(initialMessage)) {
      await trackClick(MeiroNotificationData.fromRemoteMessage(initialMessage));
    }
  }

  /// Disposes notification subscriptions.
  Future<void> dispose() async {
    await _messageSubscription?.cancel();
    await _tokenSubscription?.cancel();
    await _openedSubscription?.cancel();
  }

  /// Displays and tracks a Meiro remote message.
  Future<void> show(RemoteMessage message) async {
    if (!_configuration.pushEnabled || !isMeiroMessage(message)) {
      return;
    }
    final data = MeiroNotificationData.fromRemoteMessage(message);
    try {
      // FCM/APNs already displays notification payloads in the background.
      if (!_background || message.notification == null) {
        await _display(data);
      }
    } finally {
      await _eventTracker(
        MeiroEventType.fcmMessageReceived,
        data.toEventProperties(),
      );
    }
  }

  /// Tracks a notification click and performs the configured action.
  Future<void> trackClick(MeiroNotificationData data) async {
    await _eventTracker(
      MeiroEventType.fcmMessageClick,
      data.toEventProperties(),
    );

    final url = data.action.url;
    if (url == null) {
      return;
    }
    try {
      await launchUrl(
        url,
        mode: data.action is MeiroNotificationBrowserAction
            ? LaunchMode.externalApplication
            : LaunchMode.platformDefault,
      );
    } catch (error, stackTrace) {
      _logger.log('Failed to open push notification action', error, stackTrace);
    }
  }

  Future<void> _display(MeiroNotificationData data) async {
    final imagePath = await _downloadImage(data.imageUrl);
    await _localNotifications.show(
      data.id.hashCode,
      data.title,
      data.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _configuration.channelId,
          _configuration.channelName,
          channelDescription: _configuration.channelDescription,
          color: _configuration.accentColor,
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          styleInformation: imagePath == null
              ? BigTextStyleInformation(data.body)
              : BigPictureStyleInformation(
                  FilePathAndroidBitmap(imagePath),
                  contentTitle: data.title,
                  summaryText: data.body,
                ),
        ),
        iOS: DarwinNotificationDetails(
          attachments: imagePath == null
              ? null
              : [DarwinNotificationAttachment(imagePath)],
        ),
      ),
      payload: jsonEncode(data.toJson()),
    );
  }

  void _handleLocalNotificationResponse(NotificationResponse response) {
    unawaited(_trackLocalNotificationPayload(response.payload));
  }

  Future<void> _trackLocalNotificationPayload(String? payload) async {
    if (payload == null) {
      return;
    }
    try {
      final decoded = (jsonDecode(payload) as Map).cast<String, Object?>();
      await trackClick(MeiroNotificationData.fromJson(decoded));
    } catch (error, stackTrace) {
      _logger.log('Failed to process notification click', error, stackTrace);
    }
  }

  Future<String?> _downloadImage(String? imageUrl) async {
    if (imageUrl == null || imageUrl.isEmpty) {
      return null;
    }
    try {
      final uri = Uri.parse(imageUrl);
      final response =
          await _httpClient.get(uri).timeout(_imageDownloadTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }
      final directory = await getTemporaryDirectory();
      final extension =
          p.extension(uri.path).isEmpty ? '.jpg' : p.extension(uri.path);
      final file = File(
        p.join(directory.path,
            'meiro_push_${DateTime.now().microsecondsSinceEpoch}$extension'),
      );
      await file.writeAsBytes(response.bodyBytes);
      return file.path;
    } catch (error, stackTrace) {
      _logger.log('Failed to download notification image', error, stackTrace);
      return null;
    }
  }

  static const _imageDownloadTimeout = Duration(seconds: 5);
}
