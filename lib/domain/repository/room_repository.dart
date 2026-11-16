import '../entities/room.dart';

// Define how the application requests rooms without depending on a data source.
abstract class RoomRepository {
  // Return rooms asynchronously or report a failure to the caller.
  Future<List<Room>> getRooms();
}
