import 'room.dart';
import 'schedule.dart';

enum HubConnection { connected, reconnecting, offline }

// Keep unsupported devices readable without inventing controls.
enum DeviceType { light, dimmer, blind, thermostat, sensor, unknown }

class Device {
  const Device({
    required this.id,
    required this.roomId,
    required this.name,
    required this.type,
    required this.online,
    required this.favourite,
    required this.state,
    required this.lastUpdated,
  });

  final String id, roomId, name;
  final DeviceType type;
  final bool online, favourite;
  final Map<String, dynamic> state;
  final DateTime lastUpdated;

  bool get isLight => type == DeviceType.light || type == DeviceType.dimmer;

  bool get controllable => online && type != DeviceType.sensor && type != DeviceType.unknown;

  // Replace only confirmed state fields received from the hub.
  Device confirmed(Map<String, dynamic> patch, DateTime timestamp) => Device(
    id: id,
    roomId: roomId,
    name: name,
    type: type,
    online: online,
    favourite: favourite,
    state: {...state, ...patch},
    lastUpdated: timestamp,
  );
}

class SceneAction {
  const SceneAction(this.deviceId, this.state);

  final String deviceId;
  final Map<String, dynamic> state;
}

class Scene {
  const Scene({
    required this.id,
    required this.name,
    required this.icon,
    required this.favourite,
    required this.actions,
  });

  final String id;
  final String name;
  final String icon;
  final bool favourite;
  final List<SceneAction> actions;
}

// Share one confirmed snapshot between the dashboard, search and room views.
class HomeSnapshot {
  const HomeSnapshot({
    this.hubName = 'My home',
    this.rooms = const [],
    this.devices = const [],
    this.scenes = const [],
    this.schedules = const [],
    this.lastSync,
  });

  final String hubName;
  final List<Room> rooms;
  final List<Device> devices;
  final List<Scene> scenes;
  final List<Schedule> schedules;
  final DateTime? lastSync;

  HomeSnapshot withDevices(List<Device> values) => HomeSnapshot(
    hubName: hubName,
    rooms: rooms,
    devices: values,
    scenes: scenes,
    schedules: schedules,
    lastSync: lastSync,
  );
}
