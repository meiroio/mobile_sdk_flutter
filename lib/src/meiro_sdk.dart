import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

import 'audience.dart';
import 'configuration.dart';
import 'event.dart';
import 'events_api.dart';
import 'notifications.dart';
import 'platform_info.dart';
import 'preferences.dart';
import 'session_manager.dart';
import 'sync_manager.dart';

/// Singleton object for interacting with the Meiro Flutter SDK.
class MeiroSdk {
  const MeiroSdk._();

  static _MeiroSdkImpl? _impl;

  /// Whether the SDK has been initialized.
  static bool get isInitialized => _impl != null;

  /// Current configuration.
  static MeiroConfiguration get configuration => _requireImpl().configuration;

  /// User id of the current user.
  static String get userId => _requireImpl().userId;

  /// Current session id.
  static String get sessionId => _requireImpl().sessionId;

  /// Audience API client.
  static MeiroAudience get audience => _requireImpl().audience;

  /// Initializes the SDK. This must be called once, usually before `runApp`.
  static Future<void> init({
    required MeiroConfiguration configuration,
    MeiroLogger? logger,
  }) async {
    if (_impl != null) {
      throw StateError('MeiroSdk.init must be called only once');
    }
    WidgetsFlutterBinding.ensureInitialized();
    final resolvedLogger =
        logger ?? MeiroConsoleLogger(enabled: configuration.debugMode);
    final impl = _MeiroSdkImpl(configuration, resolvedLogger);
    _impl = impl;
    await impl.init();
  }

  /// Enables or disables event tracking.
  static Future<void> setEnabled(bool enabled) =>
      _requireImpl().setEnabled(enabled);

  /// Tracks a custom event.
  static Future<void> trackCustomEvent(Map<String, Object?> properties) {
    return _requireImpl().trackCustomEvent(properties);
  }

  /// Resets the anonymous identity and current session.
  static Future<void> resetIdentity() => _requireImpl().resetIdentity();

  /// Tracks a link click.
  static Future<void> trackLinkClick(Uri url) {
    return _requireImpl().trackLinkClick(url);
  }

  /// Tracks a screen view.
  static Future<void> trackScreenView(
    String name, {
    Map<String, Object?> properties = const <String, Object?>{},
  }) {
    return _requireImpl().trackScreenView(name, properties);
  }

  /// Sets a Firebase Cloud Messaging token.
  static Future<void> setFcmToken(String token) =>
      _requireImpl().setFcmToken(token);

  /// Displays and tracks a Meiro Firebase message.
  static Future<void> showRemoteMessage(RemoteMessage message) {
    return _requireImpl().showRemoteMessage(message);
  }

  /// Handles Meiro messages from the app's Firebase background callback.
  ///
  /// Initialize Firebase in that callback and pass the same configuration as
  /// [init]. This does not initialize the foreground SDK, track lifecycle events,
  /// register Firebase listeners, or replace the application's callback.
  static Future<void> handleBackgroundMessage(
    RemoteMessage message, {
    required MeiroConfiguration configuration,
    MeiroLogger? logger,
  }) async {
    if (!configuration.pushNotifications.pushEnabled ||
        !MeiroNotifications.isMeiroMessage(message)) {
      return;
    }
    WidgetsFlutterBinding.ensureInitialized();
    final preferences = await MeiroPreferences.create();
    if (!preferences.hasIdentity) {
      return;
    }
    final resolvedLogger =
        logger ?? MeiroConsoleLogger(enabled: configuration.debugMode);
    final platformInfo = MeiroPlatformInfo();
    final sessionManager = MeiroSessionManager();
    final client = http.Client();
    final api =
        MeiroEventsApi(endpoint: configuration.endpoint, client: client);
    final syncManager = MeiroSyncManager(api: api, logger: resolvedLogger);
    final notifications = MeiroNotifications(
      configuration: configuration.pushNotifications,
      logger: resolvedLogger,
      httpClient: client,
      eventTracker: (type, properties) async {
        if (!preferences.enabled) {
          return;
        }
        await platformInfo.warm(configuration, includeAdvertisingId: false);
        final event = MeiroEvent(
          type: type,
          properties: properties,
          timestamp: DateTime.now(),
          app: platformInfo.appInfo(configuration),
          os: platformInfo.osInfo(),
          device: platformInfo.deviceInfo(),
          firebase: MeiroFirebaseInfo(
            projectId: configuration.firebaseProjectId,
            token: preferences.fcmToken,
          ),
          user: MeiroUserInfo(
            userId: preferences.userId,
            sessionId: sessionManager.getSessionId(),
          ),
        );
        try {
          await api.sendEvent(event).timeout(_backgroundRequestTimeout);
          resolvedLogger.log('Background event ${type.id} sent');
        } catch (error, stackTrace) {
          resolvedLogger.log(
            'Background event ${type.id} send failed; saving offline',
            error,
            stackTrace,
          );
          await syncManager.savePayload(event.toPayload());
        }
      },
    );
    try {
      await notifications.init(background: true);
      await notifications.show(message);
    } finally {
      await notifications.dispose();
      await syncManager.dispose();
      client.close();
    }
  }

  /// Internal event tracking used by notification helpers.
  static Future<void> trackInternal(
    MeiroEventType type,
    Map<String, Object?> properties,
  ) {
    return _requireImpl().trackEventInternal(type, properties);
  }

  /// Performs queued event sync.
  static Future<void> performSync() => _requireImpl().performSync();

  /// Disposes resources. Intended for tests and controlled app shutdown.
  static Future<void> dispose() async {
    final impl = _impl;
    _impl = null;
    await impl?.dispose();
  }

  static _MeiroSdkImpl _requireImpl() {
    final impl = _impl;
    if (impl == null) {
      throw StateError('MeiroSdk.init must be called before using the SDK');
    }
    return impl;
  }

  static const _backgroundRequestTimeout = Duration(seconds: 5);
}

class _MeiroSdkImpl with WidgetsBindingObserver {
  _MeiroSdkImpl(this.configuration, this.logger);

  final MeiroConfiguration configuration;
  final MeiroLogger logger;

  late final MeiroPreferences _preferences;
  late final MeiroSessionManager _sessionManager;
  late final MeiroPlatformInfo _platformInfo;
  late final MeiroEventsApi _api;
  late final MeiroSyncManager _syncManager;
  late final MeiroAudience _audience;
  late final MeiroNotifications _notifications;

  bool _enabled = true;
  AppLifecycleState? _lastLifecycleState;

  String get userId => _preferences.userId;
  String get sessionId => _sessionManager.getSessionId();
  MeiroAudience get audience => _audience;

  Future<void> init() async {
    _preferences = await MeiroPreferences.create();
    await _preferences.ensureIdentity();
    _enabled = _preferences.enabled;
    _sessionManager = MeiroSessionManager();
    _platformInfo = MeiroPlatformInfo();
    _api = MeiroEventsApi(endpoint: configuration.endpoint);
    _syncManager = MeiroSyncManager(api: _api, logger: logger);
    _audience = MeiroAudienceImpl(userIdProvider: () => userId);
    _notifications = MeiroNotifications(
      configuration: configuration.pushNotifications,
      logger: logger,
    );

    await _platformInfo.warm(configuration);
    await _syncManager.init();
    await _syncManager.sync();

    if (configuration.automaticTrackingOptions.lifecycleEventsTracking) {
      WidgetsBinding.instance.addObserver(this);
      await _trackAppInstalledIfNecessary();
    }

    await _notifications.init();
  }

  Future<void> dispose() async {
    WidgetsBinding.instance.removeObserver(this);
    await _notifications.dispose();
    await _syncManager.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!configuration.automaticTrackingOptions.lifecycleEventsTracking) {
      return;
    }
    if (_lastLifecycleState == state) {
      return;
    }
    _lastLifecycleState = state;
    switch (state) {
      case AppLifecycleState.resumed:
        _sessionManager.appForegrounded();
        unawaited(trackEventInternal(MeiroEventType.appForeground));
        unawaited(_syncManager.sync());
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _sessionManager.appBackgrounded();
        unawaited(trackEventInternal(MeiroEventType.appBackground));
        break;
    }
  }

  Future<void> setEnabled(bool enabled) async {
    final shouldUpdateToken =
        !_enabled && enabled && _preferences.fcmToken != null;
    _enabled = enabled;
    await _preferences.setEnabled(enabled);
    if (shouldUpdateToken) {
      await trackEventInternal(MeiroEventType.fcmTokenRegistered);
    }
  }

  Future<void> trackCustomEvent(Map<String, Object?> properties) {
    return trackEventInternal(MeiroEventType.custom, properties);
  }

  Future<void> resetIdentity() async {
    if (!_enabled) {
      return;
    }
    await _preferences.resetIdentity();
    _sessionManager.clear();
  }

  Future<void> trackLinkClick(Uri url) {
    return trackEventInternal(
      MeiroEventType.linkClick,
      <String, Object?>{'url': url.toString()},
    );
  }

  Future<void> trackScreenView(
    String name,
    Map<String, Object?> properties,
  ) {
    return trackEventInternal(
      MeiroEventType.screenView,
      <String, Object?>{...properties, 'name': name},
    );
  }

  Future<void> setFcmToken(String token) async {
    final currentToken = _preferences.fcmToken;
    _preferences.fcmToken = token;
    if (currentToken != token && _enabled) {
      await trackEventInternal(MeiroEventType.fcmTokenRegistered);
    }
  }

  Future<void> showRemoteMessage(RemoteMessage message) {
    return _notifications.show(message);
  }

  Future<void> performSync() => _syncManager.sync();

  Future<void> trackEventInternal(
    MeiroEventType type, [
    Map<String, Object?> properties = const <String, Object?>{},
  ]) async {
    if (!_enabled) {
      return;
    }

    final event = MeiroEvent(
      type: type,
      properties: properties,
      timestamp: DateTime.now(),
      app: _platformInfo.appInfo(configuration),
      os: _platformInfo.osInfo(),
      device: _platformInfo.deviceInfo(),
      firebase: MeiroFirebaseInfo(
        projectId: configuration.firebaseProjectId,
        token: _preferences.fcmToken,
      ),
      user: MeiroUserInfo(userId: userId, sessionId: sessionId),
    );

    try {
      await _api.sendEvent(event);
      logger.log('Event ${type.id} sent');
    } catch (error, stackTrace) {
      logger.log(
          'Event ${type.id} send failed; saving offline', error, stackTrace);
      await _syncManager.savePayload(event.toPayload());
    } finally {
      _sessionManager.eventSent();
    }
  }

  Future<void> _trackAppInstalledIfNecessary() async {
    if (!_preferences.freshInstall) {
      return;
    }
    await trackEventInternal(MeiroEventType.appInstalled);
    _preferences.freshInstall = false;
  }
}
