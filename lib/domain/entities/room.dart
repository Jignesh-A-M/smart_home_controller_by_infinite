// Represent a room used by the application.
class Room {
  // Create an immutable room with its required properties.
  const Room({
    required this.id,
    required this.name,
    required this.icon,
    required this.order,
  });

  // Store the room's unique backend ID.
  final String id;

  // Store the room's display name.
  final String name;

  // Store the icon identifier supplied by the backend.
  final String icon;

  // Store the room's display order.
  final int order;
}
