import '../entities/schedule.dart';

// Persist schedule configuration; the hub owns timed execution.
abstract class ScheduleRepository {
  Future<Schedule> saveSchedule(Schedule schedule, {required bool isNew});
  Future<void> deleteSchedule(String id);
}
