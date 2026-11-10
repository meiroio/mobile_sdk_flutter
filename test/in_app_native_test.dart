import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meiro_sdk/src/in_app_message.dart';
import 'package:meiro_sdk/src/in_app_message_view.dart';
import 'package:meiro_sdk/src/in_app_messaging.dart';
import 'package:meiro_sdk/src/in_app_native_text.dart';
import 'package:webview_flutter/webview_flutter.dart';

const _block = '22222222-2222-4222-8222-222222222222';
const _button = '33333333-3333-4333-8333-333333333333';

Map<String, Object?> _message(
  List<Map<String, Object?>> blocks, {
  List<String> required = const [],
}) =>
    {
      'id': '11111111-1111-4111-8111-111111111111',
      'version': 1,
      'format': 'modal',
      'contentHtml': '',
      'priority': 0,
      'placement': null,
      'trigger': {'type': 'session_start', 'delaySeconds': 0},
      'frequencyCap': {'limit': 1, 'period': 'session'},
      'conditions': {'mode': 'all', 'rules': []},
      'requiredProfileAttributes': required,
      'usesProfile': false,
      'isEnabled': true,
      'nativeContent': {'backgroundColor': '#FFFFFF', 'blocks': blocks},
    };

final _text = <String, Object?>{
  'id': _block,
  'type': 'text',
  'style': 'title',
  'text': 'Hello {{ attributes.name[0] | default: "guest" }}',
  'color': '#111827',
};

Map<String, Object?> _buttons(Map<String, Object?> action) => {
      'id': '44444444-4444-4444-8444-444444444444',
      'type': 'buttons',
      'buttons': [
        {
          'id': _button,
          'label': 'Continue',
          'backgroundColor': '#2563EB',
          'color': '#FFFFFF',
          'action': action,
        },
      ],
    };

void main() {
  final actions = <String>[];
  final payloads = <String, Map<String, Object?>>{};

  MeiroInAppDisplay display(
    Map<String, Object?> message, {
    Map<String, Object?> profile = const {},
  }) =>
      MeiroInAppDisplay(
        message: MeiroInAppMessage.parse(message)!,
        userId: 'user',
        sessionId: 'session',
        screenName: 'home',
        profile: profile,
        onAction: (_, kind, data) {
          actions.add(kind);
          payloads[kind] = data;
        },
      );

  Widget host(MeiroInAppDisplay value) => MaterialApp(
        home: Scaffold(body: MeiroInAppContent(display: value)),
      );

  setUp(() {
    actions.clear();
    payloads.clear();
  });

  test('matches the shared native text fixtures', () {
    final cases = jsonDecode(
      File('test/fixtures/in_app_native_text.json').readAsStringSync(),
    ) as List;
    for (final item in cases) {
      final fixture = (item as Map).cast<String, Object?>();
      final profile = (fixture['profile'] as Map).cast<String, Object?>();
      final required =
          ((fixture['required'] as List?) ?? const []).cast<String>();
      final actual = MeiroInAppNativeText.hasRequiredValues(required, profile)
          ? MeiroInAppNativeText.render(fixture['text'] as String, profile)
          : null;
      expect(actual, fixture['expected'], reason: fixture['name'] as String);
    }
  });

  test('renders large and non-finite numbers without throwing', () {
    expect(
        MeiroInAppNativeText.render('{{ attributes.a }}', {
          'attributes': {'a': double.infinity}
        }),
        '');
    expect(
        MeiroInAppNativeText.render('{{ attributes.a }}', {
          'attributes': {'a': 1e20}
        }),
        '100000000000000000000');
  });

  testWidgets('renders without a WebView and reports height before ready', (
    tester,
  ) async {
    final value = display(
      _message([
        _text,
        _buttons({'type': 'close'}),
      ]),
      profile: {
        'attributes': {
          'name': ['Alex'],
        },
      },
    );
    await tester.pumpWidget(host(value));
    await tester.pump();
    await tester.pump();
    expect(find.text('Hello Alex'), findsOneWidget);
    expect(find.byType(WebViewWidget), findsNothing);
    expect(actions, ['height', 'ready']);
    expect(payloads['height']!['height'] as double, greaterThan(44));
  });

  testWidgets('Close action sends click, then close', (tester) async {
    final value = display(
      _message([
        _buttons({'type': 'close'}),
      ]),
    );
    await tester.pumpWidget(host(value));
    await tester.pump();
    await tester.pump();
    actions.clear();
    await tester.tap(find.text('Continue'));
    expect(actions, ['click', 'close']);
    expect(payloads['click'], {
      'element': 'button',
      'id': _button,
      'url': null,
    });
  });

  testWidgets('Link action sends click, then navigate', (tester) async {
    const url = 'https://example.com/offer';
    final value = display(
      _message([
        _buttons({'type': 'url', 'url': url}),
      ]),
    );
    await tester.pumpWidget(host(value));
    await tester.pump();
    await tester.pump();
    actions.clear();
    await tester.tap(find.text('Continue'));
    expect(actions, ['click', 'navigate']);
    expect(payloads['navigate'], {'url': url});
  });

  testWidgets('missing required profile data fails the candidate', (
    tester,
  ) async {
    final value = display(_message([_text], required: ['name']));
    await tester.pumpWidget(host(value));
    await tester.pump();
    expect(actions, ['error']);
    expect(payloads['error'], {'reason': 'Missing required profile data'});
  });

  testWidgets('a failed image fails the candidate', (tester) async {
    final value = display(
      _message([
        {
          'id': _block,
          'type': 'image',
          'image': {
            'assetId': _button,
            'version': 1,
            'url': 'https://example.com/missing.png',
          },
          'accessibilityLabel': 'Offer',
        },
      ]),
    );
    await tester.pumpWidget(host(value));
    // Flutter's test HTTP client answers 400, on a real timer.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();
    expect(actions, ['error']);
    expect(payloads['error'], {'reason': 'Native image failed to load'});
  });
}
