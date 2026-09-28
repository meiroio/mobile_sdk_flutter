import 'dart:io' show Platform;
import 'dart:ui';

import 'package:advertising_id/advertising_id.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'configuration.dart';
import 'event.dart';

/// Resolves platform metadata attached to every event.
class MeiroPlatformInfo {
  /// Creates platform metadata resolver.
  MeiroPlatformInfo({
    DeviceInfoPlugin? deviceInfoPlugin,
    Future<PackageInfo> Function()? packageInfoProvider,
  })  : _deviceInfoPlugin = deviceInfoPlugin ?? DeviceInfoPlugin(),
        _packageInfoProvider = packageInfoProvider ?? PackageInfo.fromPlatform;

  final DeviceInfoPlugin _deviceInfoPlugin;
  final Future<PackageInfo> Function() _packageInfoProvider;

  PackageInfo? _packageInfo;
  MeiroDeviceInfo? _deviceInfo;
  String? _osVersion;
  String? _adId;
  bool _adIdResolved = false;

  /// Warms platform metadata caches.
  Future<void> warm(
    MeiroConfiguration configuration, {
    bool includeAdvertisingId = true,
  }) async {
    await Future.wait([
      _resolvePackageInfo(),
      _resolveDeviceInfo(),
      if (includeAdvertisingId &&
          configuration.automaticTrackingOptions.adIdTracking)
        resolveAdId(
            requestTrackingAuthorization: configuration
                .automaticTrackingOptions.requestTrackingAuthorization),
    ]);
  }

  /// Returns app info.
  MeiroAppInfo appInfo(MeiroConfiguration configuration) {
    final packageInfo = _packageInfo;
    return MeiroAppInfo(
      id: configuration.appId,
      name: packageInfo?.appName,
      version: packageInfo?.version,
      language: configuration.language ??
          PlatformDispatcher.instance.locale.languageCode,
      adId: _adId,
    );
  }

  /// Returns OS info.
  MeiroOsInfo osInfo() {
    return MeiroOsInfo(type: Platform.operatingSystem, version: _osVersion);
  }

  /// Returns device info.
  MeiroDeviceInfo? deviceInfo() => _deviceInfo;

  /// Resolves the advertising id once.
  Future<String?> resolveAdId(
      {bool requestTrackingAuthorization = false}) async {
    if (_adIdResolved) {
      return _adId;
    }
    _adIdResolved = true;
    try {
      _adId = await AdvertisingId.id(requestTrackingAuthorization);
    } on PlatformException {
      _adId = null;
    }
    return _adId;
  }

  Future<void> _resolvePackageInfo() async {
    try {
      _packageInfo = await _packageInfoProvider();
    } catch (_) {
      _packageInfo = null;
    }
  }

  Future<void> _resolveDeviceInfo() async {
    try {
      if (Platform.isAndroid) {
        final info = await _deviceInfoPlugin.androidInfo;
        _osVersion = info.version.release;
        _deviceInfo = MeiroDeviceInfo(
          manufacturer: info.manufacturer,
          model: info.model,
        );
      } else if (Platform.isIOS) {
        final info = await _deviceInfoPlugin.iosInfo;
        _osVersion = info.systemVersion;
        _deviceInfo = MeiroDeviceInfo(
          manufacturer: 'Apple',
          model: info.utsname.machine,
        );
      }
    } catch (_) {
      _deviceInfo = null;
    }
  }
}
