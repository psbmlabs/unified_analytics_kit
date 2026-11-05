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
  static const String _decidedAtKey = 'decided_at';
  static const String _declinesKey = 'declines';
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

  /// >>> When the choice was last saved (UTC), or `null` for old data / no decision.
  DateTime? loadDecidedAt() {
    final raw = _box.get(_decidedAtKey);
    if (raw == null) return null;
    return DateTime.tryParse(raw)?.toUtc();
  }

  /// >>> How many times the user declined (0 when unknown). The app decides what "declined" means.
  int loadDeclines() => int.tryParse(_box.get(_declinesKey) ?? '') ?? 0;

  /// >>> Saves the choice together with the time. [declineCount] lets the app remember how often
  /// >>> the user said no, for example to ask again later, but not forever.
  Future<void> save(AnalyticsConsent consent, {int declineCount = 0}) async {
    await _box.put(_key, jsonEncode(consent.toJson()));
    await _box.put(_decidedAtKey, DateTime.now().toUtc().toIso8601String());
    await _box.put(_declinesKey, declineCount.toString());
  }

  /// >>> Forgets the saved choice, so the user is asked again.
  Future<void> clear() async {
    await _box.delete(_key);
    await _box.delete(_decidedAtKey);
    await _box.delete(_declinesKey);
  }

  Future<void> close() => _box.close();
}