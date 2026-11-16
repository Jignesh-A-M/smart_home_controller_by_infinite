import '../entities/home_snapshot.dart';
import '../entities/room.dart';
import '../entities/temperature_reading.dart';
import 'room_repository.dart';
import 'scene_repository.dart';
import 'schedule_repository.dart';
import 'settings_repository.dart';

// Expose dashboard behavior without leaking Dio, MQTT or SQLite into widgets.
abstract class HomeRepository implements RoomRepository, SceneRepository, ScheduleRepository, SettingsRepository {
  @override
  Future<List<Room>> getRooms();

  HomeSnapshot get current;

  Stream<HomeSnapshot> get changes;

  Stream<HubConnection> get connections;

  // Share recoverable update feedback without changing hub availability.
  Stream<String> get messages;

  List<TemperatureReading> temperatureHistory(String deviceId);

  bool get connected;

  bool get restAvailable;

  bool isFavourite(String id, bool initial, {bool scene = false});

  Future<void> loadCache();

  Future<void> connect();

  Future<void> refresh();

  Future<void> setFavourite(String id, bool value, {bool scene = false});

  Future<void> command(String id, Map<String, dynamic> state);

  Future<void> dispose();
}
