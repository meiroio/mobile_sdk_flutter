// Manual device walkthrough of in-app formats. Prints `SHOT:<name>` markers so
// an external watcher can capture simulator screenshots at each step.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:meiro_sdk/meiro_sdk.dart';
// ignore: implementation_imports
import 'package:meiro_sdk/src/in_app_message_view.dart';
import 'package:meiro_sdk_example/main.dart' as app;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  Future<void> wait(WidgetTester tester, int ms) async {
    await tester.runAsync(() => Future<void>.delayed(Duration(milliseconds: ms)));
    await tester.pump();
  }

  Future<void> shot(WidgetTester tester, String name) async {
    await wait(tester, 1500);
    debugPrint('SHOT:$name');
    await wait(tester, 2500);
  }

  List<MeiroInAppContent> contents(WidgetTester tester) => tester
      .widgetList<MeiroInAppContent>(
          find.byType(MeiroInAppContent, skipOffstage: false))
      .toList();

  Future<void> dump(WidgetTester tester, String label) async {
    final all = contents(tester);
    debugPrint('DUMP:$label count=${all.length}');
    for (final c in all) {
      final d = c.display;
      final result = await tester.runAsync(() async {
        try {
          return await d.controller?.runJavaScriptReturningResult(
              'JSON.stringify({w: innerWidth, h: innerHeight, '
              'bg: getComputedStyle(document.body).backgroundColor, '
              'html: document.body.innerHTML.slice(0, 600)})');
        } catch (e) {
          return 'js-error: $e';
        }
      });
      debugPrint('DUMP:$label placement=${d.message.placement} '
          'visible=${d.visible.value} height=${d.height.value} -> $result');
    }
  }

  Future<bool> click(WidgetTester tester, String selector) async {
    for (final c in contents(tester)) {
      final result = await tester.runAsync(() async {
        try {
          return await c.display.controller?.runJavaScriptReturningResult(
              '(function(){var e=document.querySelector(${_q(selector)});'
              'if(!e)return "0";e.click();return "1";})()');
        } catch (e) {
          return 'js-error: $e';
        }
      });
      if ('$result'.contains('1')) {
        debugPrint('CLICK:$selector ok');
        return true;
      }
    }
    debugPrint('CLICK:$selector NOT FOUND');
    return false;
  }

  Future<void> trigger(WidgetTester tester, String event) async {
    await tester.runAsync(MeiroSdk.resetIdentity);
    await wait(tester, 1000);
    await tester.runAsync(() => MeiroSdk.trackCustomEvent({'name': event}));
    await wait(tester, 6000);
  }

  Future<void> tapClose(WidgetTester tester) async {
    final button = find.byTooltip('Close message');
    if (button.evaluate().isEmpty) {
      debugPrint('TAP:close NOT FOUND');
      return;
    }
    await tester.tap(button);
    debugPrint('TAP:close ok');
  }

  testWidgets('in-app walkthrough', (tester) async {
    await app.main();
    // Wait for the stories rail on a fresh install.
    for (var i = 0; i < 20 && contents(tester).isEmpty; i++) {
      await wait(tester, 1000);
    }
    if (contents(tester).isEmpty) {
      debugPrint('RAIL: missing after launch, forcing a new session');
      await tester.runAsync(() async {
        await MeiroSdk.resetIdentity();
        await MeiroSdk.inAppMessaging!.foreground();
      });
      for (var i = 0; i < 15 && contents(tester).isEmpty; i++) {
        await wait(tester, 1000);
      }
    }
    await wait(tester, 3000);
    await dump(tester, 'home');
    await shot(tester, 'home');

    // Stories: rail -> player -> next -> pause -> resume -> close.
    if (await click(tester, '.mpt-story-group')) {
      await wait(tester, 3000);
      await dump(tester, 'story-player');
      await shot(tester, 'story1');
      await click(tester, '.mpt-player-next');
      await shot(tester, 'story2');
      await click(tester, '.mpt-player-pause');
      await shot(tester, 'story-paused');
      await click(tester, '.mpt-player-pause');
      await click(tester, '.mpt-player-close');
      await shot(tester, 'story-closed');
      await dump(tester, 'story-closed');
    }

    // Offer: closed by the creative's own MeiroInApp.close() button.
    await trigger(tester, 'show_offer');
    await shot(tester, 'offer');
    await click(tester, 'button');
    await shot(tester, 'offer-closed');
    await dump(tester, 'offer-closed');

    // Image: closed by the native close button.
    await trigger(tester, 'show_image');
    await shot(tester, 'image');
    await tapClose(tester);
    await shot(tester, 'image-closed');
    await dump(tester, 'image-closed');

    // Survey: fill in, submit, then dismiss by tapping outside.
    await trigger(tester, 'show_survey');
    await shot(tester, 'survey');
    for (final c in contents(tester)) {
      await tester.runAsync(() async => c.display.controller?.runJavaScript(
          "var i=document.querySelector('input,textarea');"
          "if(i){i.focus();i.value='5';"
          "i.dispatchEvent(new Event('input',{bubbles:true}));"
          "i.dispatchEvent(new Event('change',{bubbles:true}));}"));
    }
    await shot(tester, 'survey-filled');
    for (final c in contents(tester)) {
      final html = await tester.runAsync(() async => c.display.controller
          ?.runJavaScriptReturningResult(
              "document.querySelector('[data-mpt-survey-question]').outerHTML"));
      debugPrint('DUMP:survey-question $html');
    }
    await click(tester, 'button[type=submit], [data-mpt-survey-form] button');
    await shot(tester, 'survey-submitted');
    await tester.tapAt(const Offset(20, 800));
    await shot(tester, 'survey-outside-tap');
    await dump(tester, 'survey-closed');

    await tester.runAsync(MeiroSdk.resetIdentity);
    app.appNavigatorKey.currentState!.pushNamed('/second');
    await wait(tester, 6000);
    await dump(tester, 'second');
    await shot(tester, 'second');
    app.appNavigatorKey.currentState!.pop();
    await wait(tester, 4000);
    await shot(tester, 'back-home');
  }, timeout: const Timeout(Duration(minutes: 10)));
}

String _q(String s) => "'${s.replaceAll("'", "\\'")}'";
