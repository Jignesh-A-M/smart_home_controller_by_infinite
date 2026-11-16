import '../entities/room.dart';

// List the room operations available to Bloc/Cubit.
abstract class RoomRepository {
  // Rooms

  // Return the rooms loaded by the repository.
  Future<List<Room>> getRooms();
}
