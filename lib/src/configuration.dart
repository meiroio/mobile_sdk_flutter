import 'package:flutter/widgets.dart';

/// Configuration of the Meiro SDK.
class MeiroConfiguration {
  /// Creates a new SDK configuration.
  const MeiroConfiguration({
    required this.endpoint,
    required this.appId,
    this.debugMode = false,
    this.pushNotifications = const MeiroPushNotificationsConfiguration(),
    this.automaticTrackingOptions = const MeiroAutomaticTrackingOptions(),
    this.language,
    this.firebaseProjectId,
    this.inAppMessagingEnabled = false,
    this.navigatorKey,
  });

  /// Meiro Data Platform endpoint.
  final Uri endpoint;

  /// Application ID. When Firebase is used, pass the Firebase app id.
  final String appId;

  /// Enables verbose SDK logging.
  final bool debugMode;

  /// Push notifications configuration.
  final MeiroPushNotificationsConfiguration pushNotifications;

  /// Automatic tracking options.
  final MeiroAutomaticTrackingOptions automaticTrackingOptions;

  /// Application language. If omitted, the device locale language is used.
  final String? language;

  /// Firebase project id.
  final String? firebaseProjectId;

  /// Enables Pipes in-app messages. Requires a complete `/collect/<source>` endpoint.
  final bool inAppMessagingEnabled;

  /// Key supplied to the app Navigator for modal and sticky messages.
  final GlobalKey<NavigatorState>? navigatorKey;

  /// Creates a copy with selected values replaced.
  MeiroConfiguration copyWith({
    Uri? endpoint,
    String? appId,
    bool? debugMode,
    MeiroPushNotificationsConfiguration? pushNotifications,
    MeiroAutomaticTrackingOptions? automaticTrackingOptions,
    String? language,
    String? firebaseProjectId,
    bool? inAppMessagingEnabled,
    GlobalKey<NavigatorState>? navigatorKey,
  }) {
    return MeiroConfiguration(
      endpoint: endpoint ?? this.endpoint,
      appId: appId ?? this.appId,
      debugMode: debugMode ?? this.debugMode,
      pushNotifications: pushNotifications ?? this.pushNotifications,
      automaticTrackingOptions:
          automaticTrackingOptions ?? this.automaticTrackingOptions,
      language: language ?? this.language,
      firebaseProjectId: firebaseProjectId ?? this.firebaseProjectId,
      inAppMessagingEnabled:
          inAppMessagingEnabled ?? this.inAppMessagingEnabled,
      navigatorKey: navigatorKey ?? this.navigatorKey,
    );
  }
}

/// Configuration of automatic tracking options.
class MeiroAutomaticTrackingOptions {
  /// Creates automatic tracking options.
  const MeiroAutomaticTrackingOptions({
    this.screenViewTracking = true,
    this.lifecycleEventsTracking = true,
    this.adIdTracking = true,
  });

  /// Whether screen views are tracked via [MeiroNavigatorObserver].
  final bool screenViewTracking;

  /// Whether app install, foreground, and background events are tracked.
  final bool lifecycleEventsTracking;

  /// Whether advertising identifiers are resolved and attached to events.
  final bool adIdTracking;
}

/// Push notifications configuration.
class MeiroPushNotificationsConfiguration {
  /// Creates push notification configuration.
  const MeiroPushNotificationsConfiguration({
    this.pushEnabled = true,
    this.accentColor,
    this.channelName = 'Meiro',
    this.channelDescription = 'Notifications',
    this.channelId = 'meiro_notifications',
    this.androidSmallIcon,
  });

  /// Whether Meiro push handling is enabled.
  final bool pushEnabled;

  /// Accent color for Android notifications.
  final Color? accentColor;

  /// Android notification channel name.
  final String channelName;

  /// Android notification channel description.
  final String channelDescription;

  /// Android notification channel id.
  final String channelId;

  /// Android small notification icon resource name, for example `ic_stat_meiro`.
  final String? androidSmallIcon;
}

/// Logger used by the SDK.
abstract interface class MeiroLogger {
  /// Logs an SDK message.
  void log(String message, [Object? error, StackTrace? stackTrace]);
}

/// Default logger implementation.
class MeiroConsoleLogger implements MeiroLogger {
  /// Creates a console logger.
  const MeiroConsoleLogger({this.enabled = true});

  /// Whether log output is enabled.
  final bool enabled;

  @override
  void log(String message, [Object? error, StackTrace? stackTrace]) {
    if (!enabled) {
      return;
    }
    // ignore: avoid_print
    print('[MeiroSDK] $message');
    if (error != null) {
      // ignore: avoid_print
      print('[MeiroSDK] $error');
    }
    if (stackTrace != null) {
      // ignore: avoid_print
      print(stackTrace);
    }
  }
}
