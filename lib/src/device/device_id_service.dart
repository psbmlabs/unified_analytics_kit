import 'dart:convert';
import 'package:android_id/android_id.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';
import '../core/analytics_logger.dart';

//  >>> Provides a stable, privacy-friendly device identifier.

/// * Android: SHA-256 of `ANDROID_ID`. It survives uninstall/reinstall as long
///   as the app is signed with the same key. It changes on factory reset.
/// * iOS and others: a random UUID kept in the Keychain, which usually
///   survives uninstall (Apple does not guarantee this).

// >>> No IMEI, MAC address or serial number is ever read (Google Play policy).
class DeviceIdService {
  DeviceIdService({FlutterSecureStorage? storage, Future<String?> Function()? androidIdReader, TargetPlatform? platform,})  : _storage = storage ?? _defaultStorage, _androidIdReader = androidIdReader ?? _readAndroidIdFromPlugin, _platform = platform ?? defaultTargetPlatform;

  static const String _storageKey = 'unified_analytics_kit.device_id';
  static const String _hashPrefix = 'unified_analytics_kit:';

  // >>> A known broken value returned by some old Android builds.
  static const Set<String> _invalidAndroidIds = {'9774d56d682e549c'};

  static const FlutterSecureStorage _defaultStorage = FlutterSecureStorage(iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device,),);

  final FlutterSecureStorage _storage;
  final Future<String?> Function() _androidIdReader;
  final TargetPlatform _platform;

  Future<String>? _pending;

  /// >>> Returns the device id. The value is computed once and cached.
  /// >>> Never throws. If secure storage fails, a non-persistent id is returned
  /// >>> so analytics keeps working.
  Future<String> getDeviceId() => _pending ??= _load();

  Future<String> _load() async {
    final stored = await _read();
    if (stored != null && stored.isNotEmpty) return stored;

    final id = await _generate();
    await _write(id);
    return id;
  }

  Future<String> _generate() async {
    if (_platform == TargetPlatform.android) {
      final raw = await _readAndroidId();
      if (raw != null) return _hash(raw);
    }
    return const Uuid().v4();
  }

  Future<String?> _readAndroidId() async {
    try {
      final raw = (await _androidIdReader())?.trim();
      if (raw == null || raw.isEmpty) return null;
      if (_invalidAndroidIds.contains(raw.toLowerCase())) return null;
      return raw;
    } catch (error, stackTrace) {
      AnalyticsLogger.error('Could not read ANDROID_ID', error, stackTrace);
      return null;
    }
  }

  String _hash(String value) {return sha256.convert(utf8.encode('$_hashPrefix$value')).toString();}

  Future<String?> _read() async {
    try {
      return await _storage.read(key: _storageKey);
    } catch (error, stackTrace) {
      AnalyticsLogger.error('Secure storage read failed', error, stackTrace);
      return null;
    }
  }

  Future<void> _write(String id) async {
    try {
      await _storage.write(key: _storageKey, value: id);
    } catch (error, stackTrace) {
      AnalyticsLogger.error('Secure storage write failed', error, stackTrace);
    }
  }

  static Future<String?> _readAndroidIdFromPlugin() {return const AndroidId().getId();}
}