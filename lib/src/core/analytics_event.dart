import 'package:uuid/uuid.dart';

const _uuid = Uuid();


// >>> Validation follows the strictest common rules of Firebase and Facebook

class AnalyticsEvent {
  AnalyticsEvent._({required this.id, required this.name, required this.parameters, required this.timestamp,});


  factory AnalyticsEvent(String name, {Map<String, Object?>? parameters, DateTime? timestamp, String? id,}) {
    validateName(name);
    return AnalyticsEvent._(
      id: id ?? _uuid.v4(),
      name: name,
      parameters: Map<String, Object>.unmodifiable(_sanitize(parameters)),
      timestamp: (timestamp ?? DateTime.now()).toUtc(),
    );
  }

  // >>> Restores an event from output.
  factory AnalyticsEvent.fromJson(Map<String, dynamic> json) {
    final rawParams = json['parameters'];
    return AnalyticsEvent(
      json['name'] as String,
      id: json['id'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      parameters: rawParams is Map ? Map<String, Object?>.from(rawParams) : null,
    );
  }

  static const int maxNameLength = 40;
  static const int maxParameters = 25;
  static const int maxStringValueLength = 100;

  static final RegExp _namePattern = RegExp(r'^[a-zA-Z][a-zA-Z0-9_]*$');
  static const List<String> _reservedPrefixes = ['firebase_', 'google_', 'ga_'];

  // >> Unique id, used by the backend to ignore duplicate uploads.
  final String id;
  final String name;

  // >>> Values are only [String], [int], [double] or [bool].
  final Map<String, Object> parameters;

  // >>> Always UTC.
  final DateTime timestamp;

  // >>> Throws [ArgumentError] if [name] is not a valid event or parameter name.
  static void validateName(String name) {
    if (name.isEmpty || name.length > maxNameLength) {throw ArgumentError.value(name, 'name', 'Must be 1-$maxNameLength characters long.',);}
    if (!_namePattern.hasMatch(name)) {throw ArgumentError.value(name, 'name', 'Must start with a letter and contain only letters, digits and underscores.',);}
    final lower = name.toLowerCase();
    if (_reservedPrefixes.any(lower.startsWith)) {throw ArgumentError.value(name, 'name', 'Uses a reserved prefix.');}
  }

  static Map<String, Object> _sanitize(Map<String, Object?>? input) {
    if (input == null || input.isEmpty) return const {};

    final result = <String, Object>{};
    for (final entry in input.entries) {
      final value = entry.value;
      if (value == null) continue;

      validateName(entry.key);

      if (value is String) {
        result[entry.key] = value.length > maxStringValueLength ? value.substring(0, maxStringValueLength) : value;
      } else if (value is bool || value is int) {
        result[entry.key] = value;
      } else if (value is double) {
        if (!value.isFinite) {
          throw ArgumentError.value(value, entry.key, 'Must be a finite number.');
        }
        result[entry.key] = value;
      } else {
        throw ArgumentError.value(value, entry.key, 'Unsupported type ${value.runtimeType}. Use String, int, double or bool.',);
      }
    }

    if (result.length > maxParameters) {throw ArgumentError.value(result.length, 'parameters', 'At most $maxParameters parameters are allowed.',);}
    return result;
  }

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'parameters': parameters, 'timestamp': timestamp.toIso8601String(),};

  @override
  String toString() => 'AnalyticsEvent($name, $parameters)';
}