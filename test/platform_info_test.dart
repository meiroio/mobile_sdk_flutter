import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meiro_sdk/meiro_sdk.dart';
import 'package:meiro_sdk/src/platform_info.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('advertising_id');
  final requests = <bool>[];

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      requests.add(call.arguments as bool);
      return null;
    });
  });

  tearDown(() {
    requests.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('advertising ID resolution requests tracking unless opted out',
      () async {
    final configuration = MeiroConfiguration(
      endpoint: Uri.parse('https://example.com/collect'),
      appId: 'app',
    );
    await MeiroPlatformInfo().warm(configuration);
    await MeiroPlatformInfo().warm(configuration.copyWith(
      automaticTrackingOptions: const MeiroAutomaticTrackingOptions(
        requestTrackingAuthorization: false,
      ),
    ));

    expect(requests, [true, false]);
  });
}
