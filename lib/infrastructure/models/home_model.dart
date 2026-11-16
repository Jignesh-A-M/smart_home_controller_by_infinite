import '../../domain/entities/home_snapshot.dart';
import 'model.dart';
import 'room_model.dart';
import 'scene_model.dart';
import 'schedule_model.dart';

// Keep REST/cache serialization in the infrastructure layer.
class HomeModel extends Model {
  const HomeModel(this.snapshot);
  final HomeSnapshot snapshot;

  // Validate complete responses before replacing a useful cached snapshot.
  HomeSnapshot fromJson(Map<String, dynamic> json) {
    final hub = Map<String, dynamic>.from(json['hub'] as Map);
    final rooms =
        (json['rooms'] as List)
            .map(
              (r) => const RoomModel().fromJson(
                Map<String, dynamic>.from(r as Map),
              ),
            )
            .toList()
          ..sort((a, b) => a.order.compareTo(b.order));
    final devices = (json['devices'] as List).map((raw) {
      final d = Map<String, dynamic>.from(raw as Map);
      final type =
          DeviceType.values.where((t) => t.name == d['type']).firstOrNull ??
          DeviceType.unknown;
      if (d['id'] is! String ||
          d['name'] is! String ||
          d['roomId'] is! String ||
          d['online'] is! bool ||
          d['favourite'] is! bool ||
          d['state'] is! Map) {
        throw const FormatException('Invalid device data.');
      }
      final state = Map<String, dynamic>.from(d['state'] as Map);
      final complete = switch (type) {
        DeviceType.light => state['on'] is bool,
        DeviceType.dimmer => state['on'] is bool && state['level'] is num,
        DeviceType.blind => state['position'] is num,
        DeviceType.thermostat =>
          state['on'] is bool &&
              state['mode'] is String &&
              state['setpoint'] is num &&
              state['current'] is num,
        DeviceType.sensor =>
          state['motion'] is bool || state['temperature'] is num,
        DeviceType.unknown => true,
      };
      if (!complete || !validState(type, state)) {
        throw const FormatException('Invalid device state.');
      }
      return Device(
        id: d['id'] as String,
        roomId: d['roomId'] as String,
        name: d['name'] as String,
        type: type,
        online: d['online'] as bool,
        favourite: d['favourite'] as bool,
        state: state,
        lastUpdated: DateTime.parse(d['lastUpdated'] as String),
      );
    }).toList();
    final scenes = (json['scenes'] as List)
        .map(
          (raw) => const SceneModel().fromJson(
            Map<String, dynamic>.from(raw as Map),
          ),
        )
        .toList();
    if (rooms.map((r) => r.id).toSet().length != rooms.length ||
        devices.map((d) => d.id).toSet().length != devices.length ||
        devices.any((d) => !rooms.any((r) => r.id == d.roomId)) ||
        scenes.any(
          (s) => s.actions.any((a) => !devices.any((d) => d.id == a.deviceId)),
        )) {
      throw const FormatException('Invalid room/device references.');
    }
    return HomeSnapshot(
      hubName: hub['name'] as String,
      rooms: rooms,
      devices: devices,
      scenes: scenes,
      schedules: (json['schedules'] as List? ?? [])
          .map(
            (raw) => const ScheduleModel().fromJson(
              Map<String, dynamic>.from(raw as Map),
            ),
          )
          .toList(),
      lastSync: DateTime.tryParse(json['lastSync'] as String? ?? ''),
    );
  }

  // Store confirmed data only; pending command previews stay in the Cubit.
  @override
  Map<String, dynamic> toJson() => {
    'hub': {'name': snapshot.hubName},
    'rooms': snapshot.rooms
        .map(
          (r) => {'id': r.id, 'name': r.name, 'icon': r.icon, 'order': r.order},
        )
        .toList(),
    'devices': snapshot.devices
        .map(
          (d) => {
            'id': d.id,
            'roomId': d.roomId,
            'name': d.name,
            'type': d.type.name,
            'online': d.online,
            'favourite': d.favourite,
            'state': d.state,
            'lastUpdated': d.lastUpdated.toUtc().toIso8601String(),
          },
        )
        .toList(),
    'scenes': snapshot.scenes
        .map(
          (s) => {
            'id': s.id,
            'name': s.name,
            'icon': s.icon,
            'favourite': s.favourite,
            'actions': s.actions
                .map((a) => {'deviceId': a.deviceId, 'state': a.state})
                .toList(),
          },
        )
        .toList(),
    'schedules': snapshot.schedules
        .map(
          (s) => ScheduleModel(
            id: s.id,
            name: s.name,
            time: s.time,
            target: s.target,
            days: s.days,
            enabled: s.enabled,
          ).toJson(),
        )
        .toList(),
    'lastSync': snapshot.lastSync?.toUtc().toIso8601String(),
  };
}

// Validate known live fields while tolerating unsupported device types.
bool validState(DeviceType type, Map<String, dynamic> state) {
  const fields = {
    DeviceType.light: ['on'],
    DeviceType.dimmer: ['on', 'level'],
    DeviceType.blind: ['position'],
    DeviceType.thermostat: ['on', 'mode', 'setpoint', 'current'],
    DeviceType.sensor: ['motion', 'temperature', 'humidity'],
  };
  if (type != DeviceType.unknown &&
      state.keys.any((key) => !fields[type]!.contains(key))) {
    return false;
  }
  bool range(String key, num min, num max) =>
      !state.containsKey(key) ||
      (state[key] is num &&
          (state[key] as num).isFinite &&
          state[key] >= min &&
          state[key] <= max);
  if (state.containsKey('on') && state['on'] is! bool) return false;
  if (!range('level', 0, 100) ||
      !range('position', 0, 100) ||
      !range('setpoint', 16, 30)) {
    return false;
  }
  if (state.containsKey('mode') && !['cool', 'auto'].contains(state['mode'])) {
    return false;
  }
  if (state.containsKey('motion') && state['motion'] is! bool) return false;
  if (!range('temperature', -100, 100) ||
      !range('current', -100, 100) ||
      !range('humidity', 0, 100)) {
    return false;
  }
  return state.isNotEmpty;
}

// Reuse the same field/range checks for scene targets and live commands.
bool validCommandTarget(DeviceType type, Map<String, dynamic> state) {
  const fields = {
    DeviceType.light: ['on'],
    DeviceType.dimmer: ['on', 'level'],
    DeviceType.blind: ['position'],
    DeviceType.thermostat: ['on', 'mode', 'setpoint'],
  };
  final allowed = fields[type];
  return allowed != null &&
      validState(type, state) &&
      state.keys.every(allowed.contains);
}
