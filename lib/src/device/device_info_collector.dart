import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../core/analytics_logger.dart';

// >>> Non-sensitive device and app information attached to every upload.
@immutable
class AnalyticsDeviceInfo {
  const AnalyticsDeviceInfo({
    required this.platform,
    this.osVersion,
    this.model,
    this.manufacturer,
    this.isPhysicalDevice,
    this.appVersion,
    this.buildNumber,
    this.packageName,
    this.locale,
    this.timezone,
    this.timezoneOffsetMinutes,
  });

  // >>> `android` or `ios`.
  final String platform;
  final String? osVersion;
  final String? model;
  final String? manufacturer;
  final bool? isPhysicalDevice;
  final String? appVersion;
  final String? buildNumber;
  final String? packageName;

  // >>> BCP 47 language tag, for example `bn-BD`.
  final String? locale;
  final String? timezone;
  final int? timezoneOffsetMinutes;

  // >>> Null values are omitted.
  Map<String, dynamic> toJson() => {
    'platform': platform,
    if (osVersion != null) 'os_version': osVersion,
    if (model != null) 'model': model,
    if (manufacturer != null) 'manufacturer': manufacturer,
    if (isPhysicalDevice != null) 'is_physical_device': isPhysicalDevice,
    if (appVersion != null) 'app_version': appVersion,
    if (buildNumber != null) 'build_number': buildNumber,
    if (packageName != null) 'package_name': packageName,
    if (locale != null) 'locale': locale,
    if (timezone != null) 'timezone': timezone,
    if (timezoneOffsetMinutes != null) 'timezone_offset_minutes': timezoneOffsetMinutes,
  };
}

// >>> Collects [AnalyticsDeviceInfo]. Never throws.
class DeviceInfoCollector {
  DeviceInfoCollector({DeviceInfoPlugin? deviceInfo, Future<PackageInfo> Function()? packageInfoLoader, TargetPlatform? platform,})  : _deviceInfo = deviceInfo ?? DeviceInfoPlugin(), _packageInfoLoader = packageInfoLoader ?? PackageInfo.fromPlatform, _platform = platform ?? defaultTargetPlatform;

  final DeviceInfoPlugin _deviceInfo;
  final Future<PackageInfo> Function() _packageInfoLoader;
  final TargetPlatform _platform;

  Future<AnalyticsDeviceInfo>? _static;

  /// >>> Hardware, OS and app data never change while the app runs, so it is
  /// >>> loaded once. Locale and timezone can change, so they are read each time.
  Future<AnalyticsDeviceInfo> collect() async {
    final base = await (_static ??= _loadStatic());
    final now = DateTime.now();
    return AnalyticsDeviceInfo(
      platform: base.platform,
      osVersion: base.osVersion,
      model: base.model,
      manufacturer: base.manufacturer,
      isPhysicalDevice: base.isPhysicalDevice,
      appVersion: base.appVersion,
      buildNumber: base.buildNumber,
      packageName: base.packageName,
      locale: PlatformDispatcher.instance.locale.toLanguageTag(),
      timezone: now.timeZoneName,
      timezoneOffsetMinutes: now.timeZoneOffset.inMinutes,
    );
  }

  Future<AnalyticsDeviceInfo> _loadStatic() async {
    final platformName = _platform.name.toLowerCase();
    String? osVersion;
    String? model;
    String? manufacturer;
    bool? isPhysical;
    String? appVersion;
    String? buildNumber;
    String? packageName;

    try {
      if (_platform == TargetPlatform.android) {
        final info = await _deviceInfo.androidInfo;
        osVersion = info.version.release;
        model = info.model;
        manufacturer = info.manufacturer;
        isPhysical = info.isPhysicalDevice;
      } else if (_platform == TargetPlatform.iOS) {
        final info = await _deviceInfo.iosInfo;
        osVersion = info.systemVersion;
        model = info.utsname.machine;
        manufacturer = 'Apple';
        isPhysical = info.isPhysicalDevice;
      }
    } catch (error, stackTrace) {
      AnalyticsLogger.error('Could not read device info', error, stackTrace);
    }

    try {
      final package = await _packageInfoLoader();
      appVersion = package.version;
      buildNumber = package.buildNumber;
      packageName = package.packageName;
    } catch (error, stackTrace) {
      AnalyticsLogger.error('Could not read package info', error, stackTrace);
    }

    return AnalyticsDeviceInfo(
      platform: platformName,
      osVersion: osVersion,
      model: model,
      manufacturer: manufacturer,
      isPhysicalDevice: isPhysical,
      appVersion: appVersion,
      buildNumber: buildNumber,
      packageName: packageName,
    );
  }
}