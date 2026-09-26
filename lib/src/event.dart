import 'package:meta/meta.dart';

/// Internal Meiro event type identifiers.
@internal
enum MeiroEventType {
  /// Screen view event.
  screenView('screen_view'),

  /// Application entered foreground.
  appForeground('app_foreground'),

  /// First launch after install.
  appInstalled('app_installed'),

  /// Application entered background.
  appBackground('app_background'),

  /// Link click event.
  linkClick('link_click'),

  /// Custom event.
  custom('event_custom'),

  /// Firebase registration token was registered.
  fcmTokenRegistered('fcm_registration_token_registered'),

  /// Firebase message was received.
  fcmMessageReceived('fcm_message_received'),

  /// Firebase message was clicked.
  fcmMessageClick('fcm_message_click'),

  /// In-app message events.
  inAppMessageImpression('in_app_message_impression'),
  inAppMessageClick('in_app_message_click'),
  inAppMessageClose('in_app_message_close'),
  inAppMessageSubmit('in_app_message_submit'),
  surveyAnswer('survey_answer'),
  inAppStoryGroupOpen('in_app_story_group_open'),
  inAppStoryView('in_app_story_view'),
  inAppStoryComplete('in_app_story_complete'),
  inAppStoryClick('in_app_story_click'),
  inAppStoryClose('in_app_story_close');

  const MeiroEventType(this.id);

  /// Protocol event identifier.
  final String id;
}

/// Internal SDK event model.
@internal
class MeiroEvent {
  /// Creates an event.
  const MeiroEvent({
    required this.type,
    required this.timestamp,
    required this.app,
    required this.os,
    required this.device,
    required this.firebase,
    required this.user,
    this.properties = const <String, Object?>{},
    this.version = '1.0.0',
  });

  /// Event type.
  final MeiroEventType type;

  /// Event version.
  final String version;

  /// Event properties.
  final Map<String, Object?> properties;

  /// Event timestamp.
  final DateTime timestamp;

  /// App information.
  final MeiroAppInfo app;

  /// Operating system information.
  final MeiroOsInfo os;

  /// Device information.
  final MeiroDeviceInfo? device;

  /// Firebase information.
  final MeiroFirebaseInfo firebase;

  /// User and session information.
  final MeiroUserInfo user;

  /// Converts the event to the Meiro mobile endpoint payload.
  Map<String, Object?> toPayload() {
    return _withoutNulls(<String, Object?>{
      'user_id': user.userId,
      'session_id': user.sessionId,
      'event_type': type.id,
      'event_timestamp': timestamp.toUtc().toIso8601String(),
      'event_data': properties.isEmpty ? null : _jsonSafeMap(properties),
      'version': version,
      'app': app.toJson(),
      'os': os.toJson(),
      'device': device?.toJson(),
      'firebase': firebase.toJson(),
    });
  }
}

/// App information attached to every event.
@internal
class MeiroAppInfo {
  /// Creates app information.
  const MeiroAppInfo({
    required this.id,
    required this.name,
    required this.version,
    required this.language,
    required this.adId,
  });

  /// App id.
  final String? id;

  /// App name.
  final String? name;

  /// App version.
  final String? version;

  /// App language.
  final String? language;

  /// Advertising id.
  final String? adId;

  /// Converts to JSON.
  Map<String, Object?> toJson() {
    return _withoutNulls(<String, Object?>{
      'id': id,
      'name': name,
      'version': version,
      'language': language,
      'ad_id': adId,
    });
  }
}

/// OS information attached to every event.
@internal
class MeiroOsInfo {
  /// Creates OS information.
  const MeiroOsInfo({required this.type, required this.version});

  /// OS type.
  final String type;

  /// OS version.
  final String? version;

  /// Converts to JSON.
  Map<String, Object?> toJson() {
    return _withoutNulls(<String, Object?>{
      'type': type,
      'version': version,
    });
  }
}

/// Device information attached to every event.
@internal
class MeiroDeviceInfo {
  /// Creates device information.
  const MeiroDeviceInfo({required this.manufacturer, required this.model});

  /// Device manufacturer.
  final String manufacturer;

  /// Device model.
  final String model;

  /// Converts to JSON.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'manufacturer': manufacturer,
      'model': model,
    };
  }
}

/// Firebase information attached to every event.
@internal
class MeiroFirebaseInfo {
  /// Creates Firebase information.
  const MeiroFirebaseInfo({required this.projectId, required this.token});

  /// Firebase project id.
  final String? projectId;

  /// Firebase registration token.
  final String? token;

  /// Converts to JSON.
  Map<String, Object?> toJson() {
    return _withoutNulls(<String, Object?>{
      'project_id': projectId,
      'registration_token': token,
    });
  }
}

/// User information attached to every event.
@internal
class MeiroUserInfo {
  /// Creates user information.
  const MeiroUserInfo({required this.userId, required this.sessionId});

  /// User id.
  final String userId;

  /// Session id.
  final String sessionId;
}

Map<String, Object?> _jsonSafeMap(Map<String, Object?> source) {
  return source.map((key, value) => MapEntry(key, _jsonSafeValue(value)));
}

Object? _jsonSafeValue(Object? value) {
  if (value == null ||
      value is String ||
      value is num ||
      value is bool ||
      value is Map ||
      value is Iterable) {
    return value;
  }
  return value.toString();
}

Map<String, Object?> _withoutNulls(Map<String, Object?> source) {
  return {
    for (final entry in source.entries)
      if (entry.value != null) entry.key: entry.value,
  };
}
