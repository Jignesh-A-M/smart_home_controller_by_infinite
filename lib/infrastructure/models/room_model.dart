import '../../domain/entities/room.dart';
import 'model.dart';

// Follow the shared model pattern while fulfilling the domain room contract.
class RoomModel extends Model implements Room {
  // Create a model with defaults so RoomModel().fromJson(json) can be used.
  const RoomModel({
    this.id = '',
    this.name = '',
    this.icon = '',
    this.order = 0,
  });

  // Store the room's unique backend ID.
  @override
  final String id;

  // Store the room's display name.
  @override
  final String name;

  // Store the icon identifier supplied by the backend.
  @override
  final String icon;

  // Store the room's display order.
  @override
  final int order;

  // Return a validated model parsed with the shared JSON helpers.
  RoomModel fromJson(Map<String, dynamic> json) {
    final id = stringFromJson(json, 'id');
    final name = stringFromJson(json, 'name');
    final icon = stringFromJson(json, 'icon');
    final order = intFromJson(json, 'order');

    // Reject missing or incorrectly typed fields with a readable error.
    if (id == null ||
        id.isEmpty ||
        name == null ||
        name.isEmpty ||
        icon == null ||
        order == null) {
      throw const FormatException('Invalid room data received.');
    }

    return RoomModel(id: id, name: name, icon: icon, order: order);
  }

  // Convert the room back into the JSON structure used by the backend.
  @override
  Map<String, dynamic> toJson() {
    return {'id': id, 'name': name, 'icon': icon, 'order': order};
  }
}
