import 'package:flutter/material.dart';

import '../../../domain/entities/app_settings.dart';
import '../../../domain/entities/home_snapshot.dart';
import '../../common/temperature_scope.dart';

// Edit target values locally; these controls never send device commands.
class SceneActionEditor extends StatelessWidget {
  const SceneActionEditor({
    super.key,
    required this.device,
    required this.action,
    required this.enabled,
    required this.onChanged,
    required this.onRemove,
  });

  final Device? device;
  final SceneAction action;
  final bool enabled;
  final ValueChanged<Map<String, dynamic>> onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final target = action.state;
    final unit = TemperatureScope.of(context);
    final type = device?.type;
    final supported = type != null && type != DeviceType.sensor && type != DeviceType.unknown;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(device?.name ?? action.deviceId, style: Theme.of(context).textTheme.titleMedium)),
                IconButton(
                  tooltip: 'Remove device',
                  onPressed: enabled ? onRemove : null,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            if (device?.online == false) const Text('Offline device · target can still be configured'),
            if (!supported) const Text('Read-only or unsupported device. Remove it before saving.'),
            if (type == DeviceType.light || type == DeviceType.dimmer || type == DeviceType.thermostat)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Power'),
                value: target['on'] as bool? ?? device?.state['on'] == true,
                onChanged: enabled ? (value) => onChanged({...target, 'on': value}) : null,
              ),
            if (type == DeviceType.dimmer || type == DeviceType.blind) ...[
              Text(
                '${type == DeviceType.blind ? 'Position' : 'Brightness'}: ${target[type == DeviceType.blind ? 'position' : 'level'] ?? device?.state[type == DeviceType.blind ? 'position' : 'level'] ?? 0}%',
              ),
              Slider(
                value:
                    ((target[type == DeviceType.blind ? 'position' : 'level'] ??
                                device?.state[type == DeviceType.blind ? 'position' : 'level'] ??
                                0)
                            as num)
                        .toDouble()
                        .clamp(0, 100),
                max: 100,
                divisions: 100,
                onChanged: enabled
                    ? (value) => onChanged({...target, type == DeviceType.blind ? 'position' : 'level': value.round()})
                    : null,
              ),
            ],
            if (type == DeviceType.thermostat) ...[
              DropdownButtonFormField<String>(
                key: ValueKey('${action.deviceId}-${target['mode']}'),
                initialValue: target['mode'] as String? ?? device?.state['mode'] as String? ?? 'auto',
                decoration: const InputDecoration(labelText: 'Mode'),
                items: const ['auto', 'cool'].map((mode) => DropdownMenuItem(value: mode, child: Text(mode))).toList(),
                onChanged: enabled
                    ? (value) {
                        if (value != null) {
                          onChanged({...target, 'mode': value});
                        }
                      }
                    : null,
              ),
              const SizedBox(height: 12),
              Text(
                'Setpoint: ${formatTemperature((target['setpoint'] ?? device?.state['setpoint'] ?? 24) as num, unit)}',
              ),
              Slider(
                value: displayTemperature(
                  ((target['setpoint'] ?? device?.state['setpoint'] ?? 24) as num).clamp(16, 30),
                  unit,
                ),
                min: displayTemperature(16, unit),
                max: displayTemperature(30, unit),
                divisions: 28,
                onChanged: enabled
                    ? (value) => onChanged({...target, 'setpoint': canonicalTemperature(value, unit).clamp(16, 30)})
                    : null,
              ),
            ],
            Text('Target: ${sceneTargetLabel(target, unit: unit)}', style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

// Seed a newly selected device with only fields accepted by its command contract.
Map<String, dynamic> defaultSceneTarget(Device device) => switch (device.type) {
  DeviceType.light => {'on': device.state['on'] == true},
  DeviceType.dimmer => {'on': device.state['on'] == true, 'level': device.state['level'] ?? 50},
  DeviceType.blind => {'position': device.state['position'] ?? 0},
  DeviceType.thermostat => {
    'on': device.state['on'] == true,
    'mode': device.state['mode'] ?? 'auto',
    'setpoint': device.state['setpoint'] ?? 24,
  },
  _ => {},
};

IconData sceneIcon(String icon) => switch (icon) {
  'sunrise' => Icons.wb_twilight,
  'moon' => Icons.bedtime_outlined,
  'movie' => Icons.movie_outlined,
  'lock' => Icons.lock_outline,
  _ => Icons.home_outlined,
};

// Translate stored command fields into readable target descriptions.
String sceneTargetLabel(Map<String, dynamic> target, {TemperatureUnit unit = TemperatureUnit.celsius}) => [
  if (target.containsKey('on')) target['on'] == true ? 'On' : 'Off',
  if (target.containsKey('level')) 'Brightness ${target['level']}%',
  if (target.containsKey('position')) 'Position ${target['position']}%',
  if (target.containsKey('mode')) target['mode'] == 'auto' ? 'Auto' : 'Cool',
  if (target.containsKey('setpoint')) formatTemperature(target['setpoint'] as num, unit),
].join(' · ');
