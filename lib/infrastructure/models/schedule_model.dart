import '../../domain/entities/schedule.dart';
import 'model.dart';

class ScheduleModel extends Model implements Schedule {
  const ScheduleModel({
    this.id = '',
    this.name = '',
    this.time = '06:30',
    this.target = const ScheduleTarget(type: 'scene', id: ''),
    this.days = const [],
    this.enabled = false,
  });
  @override
  final String id, name, time;
  @override
  final ScheduleTarget target;
  @override
  final List<String> days;
  @override
  final bool enabled;

  // Validate the supplied schedule contract before accepting REST or cached data.
  ScheduleModel fromJson(Map<String, dynamic> json) {
    final rawTarget = json['target'];
    final rawDays = json['days'];
    if (json['id'] is! String ||
        (json['id'] as String).isEmpty ||
        json['name'] is! String ||
        (json['name'] as String).trim().isEmpty ||
        (json['name'] as String).trim().length > 60 ||
        json['enabled'] is! bool ||
        json['time'] is! String ||
        !RegExp(
          r'^([01]\d|2[0-3]):[0-5]\d$',
        ).hasMatch(json['time'] as String) ||
        rawDays is! List ||
        rawDays.isEmpty ||
        rawDays.any((day) => !scheduleDays.contains(day)) ||
        rawDays.toSet().length != rawDays.length ||
        rawTarget is! Map ||
        !['scene', 'device'].contains(rawTarget['type']) ||
        rawTarget['id'] is! String ||
        (rawTarget['id'] as String).isEmpty) {
      throw const FormatException(
        'Invalid schedule name, time, repeat days or target.',
      );
    }
    if (rawTarget['type'] == 'device' &&
        (rawTarget['state'] is! Map || (rawTarget['state'] as Map).isEmpty)) {
      throw const FormatException('Choose a target state for the device.');
    }
    return ScheduleModel(
      id: json['id'] as String,
      name: json['name'] as String,
      time: json['time'] as String,
      enabled: json['enabled'] as bool,
      days: List<String>.from(rawDays),
      target: ScheduleTarget(
        type: rawTarget['type'] as String,
        id: rawTarget['id'] as String,
        state: rawTarget['type'] == 'device'
            ? Map<String, dynamic>.from(rawTarget['state'] as Map)
            : const {},
      ),
    );
  }

  // Keep UI metadata out of the assignment's REST schema.
  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'time': time,
    'days': days,
    'enabled': enabled,
    'target': {
      'type': target.type,
      'id': target.id,
      if (target.type == 'device') 'state': target.state,
    },
  };
}
