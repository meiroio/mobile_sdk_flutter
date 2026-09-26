import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:meiro_sdk/src/in_app_message.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final story = <String, Object?>{
    'id': '11111111-1111-4111-8111-111111111111',
    'version': 1,
    'format': 'inline',
    'contentHtml': '',
    'storyCollection': {
      'groups': [
        {
          'id': '22222222-2222-4222-8222-222222222222',
          'title': 'New arrivals',
          'cover': {
            'assetId': '33333333-3333-4333-8333-333333333333',
            'version': 2,
            'url': 'https://pipes.example/cover',
          },
          'stories': [
            {
              'id': '44444444-4444-4444-8444-444444444444',
              'image': {
                'assetId': '55555555-5555-4555-8555-555555555555',
                'version': 3,
                'url': 'https://pipes.example/story',
              },
              'durationSeconds': 5,
              'accessibilityLabel': 'Blue shoe',
              'action': {
                'label': 'Shop',
                'url': 'meiro-example://products/shoe'
              },
            },
          ],
        },
      ],
    },
    'priority': 0,
    'placement': 'home_stories',
    'trigger': {'type': 'session_start', 'delaySeconds': 0},
    'frequencyCap': {'limit': 1, 'period': 'session'},
    'conditions': {'mode': 'all', 'rules': []},
    'requiredProfileAttributes': <String>[],
    'usesProfile': false,
    'isEnabled': true,
  };

  test('accepts v2 story rail and rejects malformed formats', () {
    expect(MeiroInAppMessage.parse(story), isNotNull);
    expect(
        MeiroInAppMessage.parse(
            {...story, 'format': 'modal', 'placement': null}),
        isNull);
    expect(MeiroInAppMessage.parse({...story, 'frequencyCap': null}), isNull);
    expect(
        MeiroInAppMessage.parse({
          ...story,
          'storyCollection': {
            'groups': [
              {
                ...(story['storyCollection'] as Map)['groups'][0],
                'cover': {'url': 'javascript:alert(1)'}
              }
            ]
          }
        }),
        isNull);
  });

  test('matches the shared v2 configuration and rule fixtures', () {
    final configurations = jsonDecode(
            File('test/fixtures/in_app_configurations.json').readAsStringSync())
        as List;
    for (final item in configurations) {
      final fixture = (item as Map).cast<String, Object?>();
      expect(MeiroInAppMessage.parse(fixture['message']) != null,
          fixture['accepted'],
          reason: fixture['name'] as String);
    }
    final rules =
        jsonDecode(File('test/fixtures/in_app_rules.json').readAsStringSync())
            as List;
    for (final item in rules) {
      final fixture = (item as Map).cast<String, Object?>();
      final profile = fixture['profile'];
      expect(
          MeiroInAppRules.matches(
            (fixture['rule'] as Map).cast<String, Object?>(),
            (fixture['context'] as Map).cast<String, Object?>(),
            profile is Map ? profile.cast<String, Object?>() : null,
          ),
          fixture['expected'],
          reason: fixture['name'] as String);
    }
  });

  test('bundles the shared renderer with story support', () async {
    final runtime = await rootBundle
        .loadString('packages/meiro_sdk/assets/in_app_runtime.js');
    expect(runtime, contains('story_open'));
  });

  test('uses typed event conditions and audience membership', () {
    final conditions = <String, Object?>{
      'mode': 'all',
      'rules': [
        {
          'field': 'event',
          'key': 'cart.total',
          'operator': 'greater_than',
          'value': 10
        },
        {'field': 'audience', 'operator': 'in', 'audienceId': 'buyers'},
      ],
    };
    expect(MeiroInAppRules.hasAudience(conditions), isTrue);
    expect(
        MeiroInAppRules.matches(conditions, {
          'event': {
            'cart': {'total': 11}
          }
        }, {
          'audiences': ['buyers']
        }),
        isTrue);
    expect(
        MeiroInAppRules.matches(conditions, {
          'event': {
            'cart': {'total': '11'}
          }
        }, {
          'audiences': ['buyers']
        }),
        isFalse);
  });

  test('fetches Pipes config and reserves before counting impression',
      () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      if (request.method == 'GET') {
        return http.Response(
            jsonEncode({
              'schemaVersion': 2,
              'messages': [story]
            }),
            200);
      }
      return http.Response(
          jsonEncode({'decision': 'reserved', 'reservationToken': 'lease'}),
          200);
    });
    final store = MeiroInAppStore(
      endpoint: Uri.parse('https://pipes.example/collect/mobile'),
      preferences: preferences,
      client: client,
    );
    await store.refresh();
    final message = store.messages.single;
    expect(requests.first.url.path, '/in-app-messaging/mobile.json');
    expect(store.eligible(message, 'session-1'), isTrue);
    final reservation = await store.frequency(
        message, 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'user-1', 'reserve');
    expect(reservation['decision'], 'reserved');
    expect(requests.last.url.path, '/in-app-messaging/mobile/frequency');
    expect(jsonDecode(requests.last.body)['userId'], 'user-1');
    store.impression(message, 'session-1');
    expect(store.eligible(message, 'session-1'), isFalse);
    expect(store.eligible(message, 'session-2'), isTrue);
    client.close();
  });
}
