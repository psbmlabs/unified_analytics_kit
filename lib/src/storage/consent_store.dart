import 'dart:convert';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import '../core/analytics_consent.dart';
import '../core/analytics_logger.dart';

/// Remembers the user's consent choice between app launches.
/// Hive is used on purpose instead of secure storage: Keychain data can
/// survive an uninstall on iOS, but a consent decision must not.
class ConsentStore {
  ConsentStore._(this._box);

  /// >>> Opens (or creates) the consent box on disk.
  static Future<ConsentStore> open({String boxName = defaultBoxName}) async {
    await Hive.initFlutter();
    final box = await Hive.openBox<String>(boxName);
    return ConsentStore._(box);
  }

  /// >>> Creates a store on top of an existing box. For tests.
  ConsentStore.forBox(Box<String> box) : _box = box;

  static const String defaultBoxName = 'unified_analytics_kit_consent';
  static const String _key = 'consent';
  final Box<String> _box;

  /// >>> Returns the saved consent, or `null` when the user never made a choice
  /// >>> (or the saved data is unreadable).
  AnalyticsConsent? load() {
    final raw = _box.get(_key);
    if (raw == null) return null;

    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return AnalyticsConsent.fromJson(json);
    } catch (error, stackTrace) {
      AnalyticsLogger.error('Saved consent is unreadable', error, stackTrace);
      return null;
    }
  }

  /// >>> Whether the user already made a choice.
  bool get hasDecision => load() != null;

  Future<void> save(AnalyticsConsent consent) {
    return _box.put(_key, jsonEncode(consent.toJson()));
  }

  /// >>> Forgets the saved choice, so the user is asked again.
  Future<void> clear() => _box.delete(_key);

  Future<void> close() => _box.close();
}