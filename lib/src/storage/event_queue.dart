import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import '../core/analytics_event.dart';
import '../core/analytics_logger.dart';

// >>> An event waiting in the [EventQueue], together with its storage key.
@immutable
class QueuedEvent {
  const QueuedEvent(this.key, this.event);

  // >>> Hive key, used to remove the event after a successful upload.
  final int key;
  final AnalyticsEvent event;
}

/// >>> Persistent FIFO queue of analytics events, backed by Hive.
/// >>> Events survive app restarts. When the queue grows past [maxSize], the
/// >>> oldest events are dropped first.
class EventQueue {
  EventQueue._(this._box, this.maxSize);


  static Future<EventQueue> open({required int maxSize, String boxName = defaultBoxName,}) async {
    await Hive.initFlutter();
    final box = await Hive.openBox<String>(boxName);
    return EventQueue._(box, maxSize);
  }

  // >>> Creates a queue on top of an existing box. For tests.
  @visibleForTesting
  factory EventQueue.forBox(Box<String> box, {required int maxSize}) {return EventQueue._(box, maxSize);}

  static const String defaultBoxName = 'unified_analytics_kit_queue';

  final Box<String> _box;

  // >>> Maximum number of stored events.
  final int maxSize;

  // >>> Number of events currently waiting.
  int get length => _box.length;

  bool get isEmpty => _box.isEmpty;

  // >>> Adds [event] to the end of the queue and trims the oldest events if the
  // >>> queue is larger than [maxSize].
  Future<void> enqueue(AnalyticsEvent event) async {
    await _box.add(jsonEncode(event.toJson()));
    await _trim();
  }

  // >>> Returns up to [count] of the oldest events without removing them.
  // >>> Unreadable entries are deleted and skipped.
  Future<List<QueuedEvent>> peek(int count) async {
    final result = <QueuedEvent>[];
    final corruptKeys = <dynamic>[];

    for (final key in _box.keys) {
      if (result.length >= count) break;

      final raw = _box.get(key);
      if (key is! int || raw == null) {
        corruptKeys.add(key);
        continue;
      }

      try {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        result.add(QueuedEvent(key, AnalyticsEvent.fromJson(json)));
      } catch (error, stackTrace) {
        AnalyticsLogger.error('Dropping unreadable queued event', error, stackTrace);
        corruptKeys.add(key);
      }
    }

    if (corruptKeys.isNotEmpty) {
      await _box.deleteAll(corruptKeys);
    }
    return result;
  }

  // >>> Removes events by their [keys], normally after a successful upload.
  Future<void> remove(Iterable<int> keys) => _box.deleteAll(keys);

  // >>> Deletes every queued event (for example when the user revokes consent).
  Future<void> clear() async {
    await _box.clear();
  }

  // >>> Closes the underlying box.
  Future<void> close() => _box.close();

  Future<void> _trim() async {
    final overflow = _box.length - maxSize;
    if (overflow <= 0) return;

    final oldest = _box.keys.take(overflow).toList();
    await _box.deleteAll(oldest);
    AnalyticsLogger.debug('Queue full, dropped $overflow oldest event(s).');
  }
}