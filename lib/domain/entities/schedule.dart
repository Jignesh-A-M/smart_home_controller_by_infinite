// Store the same scene/device target structure used by the backend scheduler.
class ScheduleTarget {
  const ScheduleTarget({
    required this.type,
    required this.id,
    this.state = const {},
  });
  final String type, id;
  final Map<String, dynamic> state;
}

class Schedule {
  const Schedule({
    required this.id,
    required this.name,
    required this.target,
    required this.time,
    required this.days,
    required this.enabled,
  });
  final String id, name, time;
  final ScheduleTarget target;
  final List<String> days;
  final bool enabled;
}

const scheduleDays = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];
const hubTimezone = 'Asia/Kolkata';
