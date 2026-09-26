// ignore_for_file: public_member_api_docs

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// One validated Pipes in-app message.
class MeiroInAppMessage {
  MeiroInAppMessage._(this.data);

  static const int _maxHtmlLength = 512000;
  static const int _maxPriority = 9999;
  static const int _maxTriggerDelaySeconds = 3600;
  static const int _maxCapLimit = 100;
  static const int _maxRequiredAttributes = 100;
  static const int _maxAttributeNameLength = 256;
  static const int _maxStoryGroups = 20;
  static const int _maxStories = 100;
  static const int _maxStoryDurationSeconds = 30;
  static const int _maxStoryActionUrlLength = 2048;

  static final RegExp _uuid = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');

  final Map<String, Object?> data;

  String get id => data['id'] as String;
  int get version => data['version'] as int;
  String get format => data['format'] as String;
  String? get placement => data['placement'] as String?;
  int get priority => data['priority'] as int;
  String get html => data['contentHtml'] as String;
  Map<String, Object?> get trigger =>
      (data['trigger'] as Map).cast<String, Object?>();
  Map<String, Object?> get cap =>
      (data['frequencyCap'] as Map).cast<String, Object?>();
  Map<String, Object?> get conditions =>
      (data['conditions'] as Map).cast<String, Object?>();
  Map<String, Object?>? get stickyBanner =>
      (data['stickyBanner'] as Map?)?.cast<String, Object?>();
  Map<String, Object?>? get survey =>
      (data['survey'] as Map?)?.cast<String, Object?>();
  Map<String, Object?>? get storyCollection =>
      (data['storyCollection'] as Map?)?.cast<String, Object?>();
  List<String> get requiredProfileAttributes =>
      (data['requiredProfileAttributes'] as List).cast<String>();
  bool get needsProfile =>
      data['usesProfile'] == true ||
      requiredProfileAttributes.isNotEmpty ||
      MeiroInAppRules.hasAudience(conditions);

  static MeiroInAppMessage? parse(Object? value) {
    if (value is! Map) return null;
    try {
      final data = value.cast<String, Object?>();
      final id = data['id'];
      final version = data['version'];
      final format = data['format'];
      final html = data['contentHtml'];
      final priority = data['priority'];
      final trigger = (data['trigger'] as Map).cast<String, Object?>();
      final cap = (data['frequencyCap'] as Map).cast<String, Object?>();
      final conditions = (data['conditions'] as Map).cast<String, Object?>();
      final required =
          (data['requiredProfileAttributes'] as List).cast<String>();
      final placement = data['placement'];
      final survey = data['survey'];
      final stories = data['storyCollection'];
      final sticky = data['stickyBanner'];
      final delay = trigger['delaySeconds'];
      if (data['isEnabled'] != true ||
          id is! String ||
          !_uuid.hasMatch(id) ||
          version is! int ||
          version <= 0 ||
          !['modal', 'inline', 'sticky'].contains(format) ||
          html is! String ||
          html.length > _maxHtmlLength ||
          priority is! int ||
          priority < 0 ||
          priority > _maxPriority ||
          (html.isEmpty && survey == null && stories == null) ||
          (format == 'inline' &&
              (placement is! String ||
                  !RegExp(r'^[A-Za-z][A-Za-z0-9_]{0,99}$')
                      .hasMatch(placement))) ||
          (format != 'inline' && placement != null) ||
          !['session_start', 'screen_view', 'event']
              .contains(trigger['type']) ||
          (trigger['type'] == 'event' &&
              (trigger['name'] is! String ||
                  (trigger['name'] as String).isEmpty)) ||
          (trigger['name'] != null &&
              (trigger['name'] is! String ||
                  (trigger['name'] as String).length > 200)) ||
          delay is! num ||
          !delay.isFinite ||
          delay < 0 ||
          delay > _maxTriggerDelaySeconds ||
          cap['limit'] is! int ||
          (cap['limit'] as int) < 1 ||
          (cap['limit'] as int) > _maxCapLimit ||
          !['session', 'day', 'lifetime'].contains(cap['period']) ||
          !['all', 'any'].contains(conditions['mode']) ||
          conditions['rules'] is! List ||
          data['usesProfile'] is! bool ||
          required.length > _maxRequiredAttributes ||
          required.any((item) =>
              item.isEmpty || item.length > _maxAttributeNameLength) ||
          (format == 'sticky' &&
              (sticky is! Map || survey != null || stories != null)) ||
          (format != 'sticky' && sticky != null) ||
          (stories != null &&
              (format != 'inline' ||
                  html.isNotEmpty ||
                  survey != null ||
                  !_validStories(stories)))) {
        return null;
      }
      if (sticky is Map &&
          (!['top', 'bottom'].contains(sticky['position']) ||
              sticky['maxHeightPercent'] is! num ||
              !(sticky['maxHeightPercent'] as num).isFinite ||
              (sticky['maxHeightPercent'] as num) <= 0 ||
              (sticky['maxHeightPercent'] as num) > 100)) {
        return null;
      }
      return MeiroInAppMessage._(data);
    } catch (_) {
      return null;
    }
  }

  static bool _validStories(Object? value) {
    if (value is! Map || value['groups'] is! List) return false;
    final groups = value['groups'] as List;
    if (groups.isEmpty || groups.length > _maxStoryGroups) return false;
    final scheme = value['appLinkScheme'];
    if (scheme != null &&
        (scheme is! String ||
            !RegExp(r'^[a-z][a-z0-9+.-]*$').hasMatch(scheme) ||
            const {
              'http',
              'https',
              'javascript',
              'data',
              'file',
              'about',
              'vbscript',
              'blob'
            }.contains(scheme))) {
      return false;
    }
    var storyCount = 0;
    for (final group in groups) {
      if (group is! Map ||
          group['id'] is! String ||
          !_uuid.hasMatch(group['id'] as String) ||
          group['title'] is! String ||
          (group['title'] as String).isEmpty ||
          (group['title'] as String).length > 100 ||
          !_validAsset(group['cover']) ||
          group['stories'] is! List) {
        return false;
      }
      final stories = group['stories'] as List;
      if (stories.isEmpty || stories.length > _maxStories) return false;
      storyCount += stories.length;
      for (final story in stories) {
        if (story is! Map ||
            story['id'] is! String ||
            !_uuid.hasMatch(story['id'] as String) ||
            !_validAsset(story['image']) ||
            story['durationSeconds'] is! int ||
            (story['durationSeconds'] as int) < 1 ||
            (story['durationSeconds'] as int) > _maxStoryDurationSeconds ||
            story['accessibilityLabel'] is! String ||
            (story['accessibilityLabel'] as String).isEmpty ||
            (story['accessibilityLabel'] as String).length > 300) {
          return false;
        }
        final action = story['action'];
        if (action != null) {
          if (action is! Map ||
              action['label'] is! String ||
              (action['label'] as String).isEmpty ||
              (action['label'] as String).length > 100 ||
              action['url'] is! String ||
              (action['url'] as String).length > _maxStoryActionUrlLength) {
            return false;
          }
          final url = Uri.tryParse(action['url'] as String);
          if (url == null ||
              url.scheme.isEmpty ||
              const {
                'http',
                'javascript',
                'data',
                'file',
                'about',
                'vbscript',
                'blob'
              }.contains(url.scheme) ||
              (url.scheme == 'https' && url.host.isEmpty)) {
            return false;
          }
        }
      }
    }
    return storyCount <= _maxStories;
  }

  static bool _validAsset(Object? value) {
    if (value is! Map ||
        value['assetId'] is! String ||
        !_uuid.hasMatch(value['assetId'] as String) ||
        value['version'] is! int ||
        (value['version'] as int) < 1 ||
        value['url'] is! String) {
      return false;
    }
    final url = Uri.tryParse(value['url'] as String);
    return url != null &&
        {'http', 'https'}.contains(url.scheme) &&
        url.host.isNotEmpty;
  }
}

/// Evaluates the same bounded condition tree used by the native SDKs.
class MeiroInAppRules {
  static final Object _missing = Object();
  static const int _maxDepth = 5;
  static const int _maxRules = 100;

  static bool hasAudience(Map<String, Object?> rule, [int depth = 0]) {
    if (depth > _maxDepth) return false;
    if (rule['field'] == 'audience') return true;
    final children = rule['rules'];
    return children is List &&
        children.any((item) =>
            item is Map &&
            hasAudience(item.cast<String, Object?>(), depth + 1));
  }

  static bool matches(Map<String, Object?> rule, Map<String, Object?> context,
      Map<String, Object?>? profile,
      [int depth = 0]) {
    if (depth > _maxDepth) return false;
    final mode = rule['mode'];
    if (mode != null) {
      final children = rule['rules'];
      if (!['all', 'any'].contains(mode) ||
          children is! List ||
          children.length > _maxRules) {
        return false;
      }
      final results = children.map((item) =>
          item is Map &&
          matches(item.cast<String, Object?>(), context, profile, depth + 1));
      return mode == 'all'
          ? results.every((value) => value)
          : results.any((value) => value);
    }
    final field = rule['field'];
    final operator = rule['operator'];
    if (field == 'audience') {
      final audiences = profile?['audiences'];
      if (audiences is! List || rule['audienceId'] is! String) return false;
      final contains = audiences.contains(rule['audienceId']);
      return operator == 'in' ? contains : operator == 'not_in' && !contains;
    }
    Object? actual = context.containsKey(field) ? context[field] : _missing;
    if (field == 'event') {
      actual = context.containsKey('event') ? context['event'] : _missing;
      for (final part in (rule['key'] as String? ?? '').split('.')) {
        if (['__proto__', 'prototype', 'constructor'].contains(part)) {
          return false;
        }
        if (actual is Map) {
          actual = actual.containsKey(part) ? actual[part] : _missing;
        } else if (actual is List) {
          final index = int.tryParse(part);
          actual = index != null && index >= 0 && index < actual.length
              ? actual[index]
              : _missing;
        } else {
          actual = _missing;
        }
      }
    }
    if (operator == 'exists') return actual != null && actual != _missing;
    if (actual == _missing) return false;
    final expected = rule['value'];
    switch (operator) {
      case 'equals':
        return actual == expected;
      case 'not_equals':
        return actual != expected;
      case 'contains':
        return actual is String &&
            expected is String &&
            actual.contains(expected);
      case 'starts_with':
        return actual is String &&
            expected is String &&
            actual.startsWith(expected);
      case 'greater_than':
      case 'less_than':
        final comparison = actual is num && expected is num
            ? actual.compareTo(expected)
            : field == 'app_version' && actual is String && expected is String
                ? _compareVersion(actual, expected)
                : null;
        return comparison != null &&
            (operator == 'greater_than' ? comparison > 0 : comparison < 0);
      default:
        return false;
    }
  }

  static int _compareVersion(String first, String second) {
    final pattern = RegExp(r'[0-9]+|[^0-9]+');
    final left =
        pattern.allMatches(first).map((match) => match.group(0)!).toList();
    final right =
        pattern.allMatches(second).map((match) => match.group(0)!).toList();
    for (var index = 0; index < left.length && index < right.length; index++) {
      final a = int.tryParse(left[index]);
      final b = int.tryParse(right[index]);
      final comparison = a != null && b != null
          ? a.compareTo(b)
          : left[index].compareTo(right[index]);
      if (comparison != 0) return comparison;
    }
    return left.length.compareTo(right.length);
  }
}

/// Fetches and persists the v2 configuration and per-installation caps.
class MeiroInAppStore {
  static const int _maxConfigMessages = 1000;
  static const int _maxResponseBytes = 4000000;
  static const Duration _cacheLifetime = Duration(hours: 24);
  static const Duration _requestTimeout = Duration(seconds: 10);
  MeiroInAppStore(
      {required Uri endpoint,
      required SharedPreferences preferences,
      required http.Client client})
      : _endpoint = endpoint,
        _preferences = preferences,
        _client = client,
        _prefix = 'io.meiro.in-app.$endpoint.' {
    final segments =
        endpoint.pathSegments.where((item) => item.isNotEmpty).toList();
    if (segments.length != 2 ||
        segments.first != 'collect' ||
        !endpoint.hasScheme ||
        endpoint.host.isEmpty) {
      throw ArgumentError.value(
          endpoint, 'endpoint', 'Use a complete Pipes /collect/<source> URL');
    }
    _slug = segments.last;
  }

  final Uri _endpoint;
  final SharedPreferences _preferences;
  final http.Client _client;
  final String _prefix;
  late final String _slug;
  List<MeiroInAppMessage> messages = [];
  DateTime? fetchedAt;

  bool get isFresh {
    final age =
        fetchedAt == null ? null : DateTime.now().difference(fetchedAt!);
    return age != null && !age.isNegative && age < _cacheLifetime;
  }

  void loadCache() {
    final raw = _preferences.getString('${_prefix}config');
    final time = _preferences.getInt('${_prefix}fetchedAt');
    if (raw == null || time == null) return;
    try {
      accept(jsonDecode(raw), DateTime.fromMillisecondsSinceEpoch(time), false);
    } catch (_) {/* Cache is optional. */}
  }

  Future<void> refresh() async {
    final url = _endpoint.replace(
        path: '/in-app-messaging/$_slug.json', query: null, fragment: null);
    final data = await _getObject(url);
    accept(data);
  }

  void accept(Object? value, [DateTime? time, bool persist = true]) {
    if (value is! Map ||
        value['schemaVersion'] != 2 ||
        value['messages'] is! List ||
        (value['messages'] as List).length > _maxConfigMessages) {
      throw const FormatException('Unsupported in-app message configuration');
    }
    messages = (value['messages'] as List)
        .map(MeiroInAppMessage.parse)
        .whereType<MeiroInAppMessage>()
        .toList();
    fetchedAt = time ?? DateTime.now();
    if (persist) {
      _preferences.setString('${_prefix}config', jsonEncode(value));
      _preferences.setInt(
          '${_prefix}fetchedAt', fetchedAt!.millisecondsSinceEpoch);
    }
  }

  Future<Map<String, Object?>> profile(String userId) {
    final url = _endpoint.replace(
        path: '/profile-api/system-in-app-messaging',
        queryParameters: {
          'identifier_type': 'mobile_user_id',
          'identifier_value': userId,
        },
        fragment: null);
    return _getObject(url);
  }

  Future<Map<String, Object?>> frequency(MeiroInAppMessage message,
      String displayId, String userId, String operation,
      [String? token]) async {
    final url = _endpoint.replace(
        path: '/in-app-messaging/$_slug/frequency',
        query: null,
        fragment: null);
    final response = await _client
        .post(url,
            headers: const {'content-type': 'application/json'},
            body: jsonEncode({
              'operation': operation,
              'messageId': message.id,
              'messageVersion': message.version,
              'displayId': displayId,
              'userId': userId,
              if (token != null) 'reservationToken': token,
            }))
        .timeout(_requestTimeout);
    return _decode(response);
  }

  int shown(MeiroInAppMessage message) =>
      _preferences.getInt('$_prefix${message.id}.total') ?? 0;

  bool eligible(MeiroInAppMessage message, String sessionId) {
    final period = message.cap['period'];
    if (period == 'lifetime') {
      return shown(message) < (message.cap['limit'] as int);
    }
    final key = '$_prefix${message.id}.$period';
    final token = period == 'day' ? _dayToken : sessionId;
    return _preferences.getString('$key.period') != token ||
        (_preferences.getInt('$key.count') ?? 0) <
            (message.cap['limit'] as int);
  }

  void impression(MeiroInAppMessage message, String sessionId) {
    _preferences.setInt('$_prefix${message.id}.total', shown(message) + 1);
    for (final period in ['session', 'day']) {
      final key = '$_prefix${message.id}.$period';
      final token = period == 'day' ? _dayToken : sessionId;
      final count = _preferences.getString('$key.period') == token
          ? (_preferences.getInt('$key.count') ?? 0)
          : 0;
      _preferences.setString('$key.period', token);
      _preferences.setInt('$key.count', count + 1);
    }
  }

  void dispose() => _client.close();

  String get _dayToken => (DateTime.now().toUtc().millisecondsSinceEpoch ~/
          Duration.millisecondsPerDay)
      .toString();

  Future<Map<String, Object?>> _getObject(Uri url) async =>
      _decode(await _client.get(url, headers: const {
        'cache-control': 'no-cache'
      }).timeout(_requestTimeout));

  Map<String, Object?> _decode(http.Response response) {
    if (response.statusCode < HttpStatus.ok ||
        response.statusCode >= HttpStatus.multipleChoices ||
        response.bodyBytes.length > _maxResponseBytes) {
      throw FormatException('In-app request failed: ${response.statusCode}');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) throw const FormatException('Invalid in-app response');
    return decoded.cast<String, Object?>();
  }
}
