import '../entities/home_snapshot.dart';
import '../entities/room.dart';
import '../entities/temperature_reading.dart';
import 'room_repository.dart';
import 'scene_repository.dart';
import 'schedule_repository.dart';
import 'settings_repository.dart';

// List the home data operations available to Bloc/Cubit.
abstract class HomeRepository implements RoomRepository, SceneRepository, ScheduleRepository, SettingsRepository {
  // Setup and shared data

  // Read the latest confirmed home data.
  HomeSnapshot get current;

  // Listen for changes to rooms, devices, scenes or schedules.
  Stream<HomeSnapshot> get changes;

  // Listen for errors that the screen can explain to the user.
  Stream<String> get messages;

  // Load and refresh home data

  // Return rooms from the loaded home data.
  @override
  Future<List<Room>> getRooms();

  // Check whether the REST server is ready for configuration changes.
  bool get restAvailable;

  // Fetch the latest home data from REST.
  Future<void> refresh();

  // Local storage

  // Load previously saved home data for offline use.
  Future<void> loadCache();

  // Read the local favourite choice or use the original value.
  bool isFavourite(String id, bool initial, {bool scene = false});

  // Save a device or scene favourite choice on this phone.
  Future<void> setFavourite(String id, bool value, {bool scene = false});

  // Return the saved temperature readings for one sensor.
  List<TemperatureReading> temperatureHistory(String deviceId);

  // MQTT and device commands

  // Listen for connected, reconnecting and offline status.
  Stream<HubConnection> get connections;

  // Check whether REST and MQTT are ready for device commands.
  bool get connected;

  // Start the device transport connection.
  Future<void> connect();

  // Send a device command and wait for its confirmed state.
  Future<void> command(String id, Map<String, dynamic> state);

  // Cleanup

  // Close the repository's listeners, connections and database.
  Future<void> dispose();
}
