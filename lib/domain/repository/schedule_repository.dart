import '../entities/schedule.dart';

// List the schedule configuration operations available to Bloc/Cubit.
abstract class ScheduleRepository {
  // Schedules

  // Create or update a schedule for the backend to execute.
  Future<Schedule> saveSchedule(Schedule schedule, {required bool isNew});

  // Delete a schedule without changing its target.
  Future<void> deleteSchedule(String id);
}
