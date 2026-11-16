import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../domain/entities/app_settings.dart';
import '../../../domain/entities/home_snapshot.dart';
import '../../common/temperature_scope.dart';
import '../bloc/device_preview_cubit.dart';

IconData deviceIcon(DeviceType type) => switch (type) {
  DeviceType.light => Icons.lightbulb_outline,
  DeviceType.dimmer => Icons.light_mode_outlined,
  DeviceType.blind => Icons.blinds_outlined,
  DeviceType.thermostat => Icons.thermostat_outlined,
  DeviceType.sensor => Icons.sensors,
  DeviceType.unknown => Icons.device_unknown,
};

// Share one control card between favourites, search and room views.
class DeviceCard extends StatefulWidget {
  const DeviceCard({
    super.key,
    required this.device,
    required this.roomName,
    required this.favourite,
    required this.connected,
    required this.onFavourite,
    required this.onControl,
    this.pending,
    this.onHistory,
  });

  final Device device;
  final String roomName;
  final bool favourite, connected;
  final Map<String, dynamic>? pending;
  final VoidCallback onFavourite;
  final VoidCallback? onHistory;
  final void Function(Map<String, dynamic>) onControl;

  @override
  State<DeviceCard> createState() => _DeviceCardState();
}

class _DeviceCardState extends State<DeviceCard> {
  final _previewCubit = DevicePreviewCubit();

  @override
  void dispose() {
    _previewCubit.close();
    super.dispose();
  }

  TemperatureUnit get unit => TemperatureScope.of(context);

  bool get enabled => widget.connected && widget.device.controllable && widget.pending == null;

  Map<String, dynamic> get value => {...widget.device.state, ...?widget.pending};

  // Reserve space beside each control and show progress only for its pending field.
  Duration get _motionDuration =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 180);

  Widget _pendingIndicator(String field, String label) => SizedBox(
    width: 20,
    height: 20,
    child: AnimatedSwitcher(
      duration: _motionDuration,
      child: widget.pending?.containsKey(field) == true
          ? CircularProgressIndicator(
              key: ValueKey('pending-${widget.device.id}-$field'),
              strokeWidth: 2,
              value: MediaQuery.disableAnimationsOf(context) ? .65 : null,
              semanticsLabel: 'Updating $label for ${widget.device.name}',
            )
          : const SizedBox.shrink(),
    ),
  );

  String get description => switch (widget.device.type) {
    DeviceType.light => value['on'] == true ? 'On' : 'Off',
    DeviceType.dimmer => '${value['on'] == true ? 'On' : 'Off'} · ${value['level']}% brightness',
    DeviceType.blind => '${value['position']}% open',
    DeviceType.thermostat =>
      '${formatTemperature(value['current'] as num, unit)} / target ${formatTemperature(value['setpoint'] as num, unit)}',
    DeviceType.sensor =>
      value.containsKey('motion')
          ? (value['motion'] == true ? 'Motion detected' : 'No motion detected')
          : '${formatTemperature(value['temperature'] as num, unit)} / ${value['humidity']}% humidity',
    DeviceType.unknown => 'Unsupported device · read only',
  };

  // Keep dragging local and send one command on release.
  Widget slider(String field, String label) {
    final current = (value[field] as num?)?.toDouble() ?? 0;
    return BlocBuilder<DevicePreviewCubit, double?>(
      bloc: _previewCubit,
      builder: (context, preview) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(child: Text('$label: ${(preview ?? current).round()}%')),
              const SizedBox(width: 8),
              _pendingIndicator(field, label),
            ],
          ),
          TweenAnimationBuilder<double>(
            tween: Tween(end: (preview ?? current).clamp(0, 100).toDouble()),
            duration: preview != null ? Duration.zero : _motionDuration,
            builder: (context, displayed, _) => Slider(
              value: displayed,
              max: 100,
              divisions: 100,
              semanticFormatterCallback: (v) => '${v.round()} percent',
              onChanged: enabled ? _previewCubit.preview : null,
              onChangeEnd: enabled
                  ? (v) {
                      _previewCubit.clear();
                      widget.onControl({field: v.round()});
                    }
                  : null,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final device = widget.device;
    final color = Theme.of(context).colorScheme.primary;
    return AnimatedSize(
      duration: _motionDuration,
      alignment: Alignment.topCenter,
      child: Card(
        margin: const EdgeInsets.only(bottom: 10),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
          child: Column(
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: color.withValues(alpha: .08),
                    foregroundColor: color,
                    child: Icon(deviceIcon(device.type)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(device.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                        Text(widget.roomName, style: Theme.of(context).textTheme.bodySmall),
                        const SizedBox(height: 3),
                        Text(description, style: const TextStyle(fontSize: 13)),
                        if (!device.online) const Text('Device offline', style: TextStyle(color: Colors.deepOrange)),
                        if (widget.pending != null)
                          const Text('Pending confirmation…', style: TextStyle(color: Colors.deepOrange)),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: widget.favourite ? 'Remove ${device.name} from favourites' : 'Favourite ${device.name}',
                    onPressed: widget.onFavourite,
                    icon: Icon(
                      widget.favourite ? Icons.star_rounded : Icons.star_outline_rounded,
                      color: widget.favourite ? Theme.of(context).colorScheme.primary : null,
                    ),
                  ),
                ],
              ),
              if (device.isLight || device.type == DeviceType.thermostat)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Power'),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _pendingIndicator('on', 'Power'),
                        const SizedBox(width: 8),
                        Switch(
                          value: value['on'] == true,
                          onChanged: enabled ? (on) => widget.onControl({'on': on}) : null,
                        ),
                      ],
                    ),
                  ],
                ),
              if (device.type == DeviceType.dimmer) slider('level', 'Brightness'),
              if (device.type == DeviceType.blind) slider('position', 'Open position'),
              if (device.type == DeviceType.thermostat) ...[
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    IconButton(
                      tooltip: 'Decrease target temperature',
                      onPressed: enabled && (value['setpoint'] as num) > 16
                          ? () => widget.onControl({
                              'setpoint': canonicalTemperature(
                                displayTemperature(value['setpoint'] as num, unit) - 1,
                                unit,
                              ).clamp(16, 30),
                            })
                          : null,
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          formatTemperature(value['setpoint'] as num, unit),
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(width: 8),
                        _pendingIndicator('setpoint', 'Target temperature'),
                      ],
                    ),
                    IconButton(
                      tooltip: 'Increase target temperature',
                      onPressed: enabled && (value['setpoint'] as num) < 30
                          ? () => widget.onControl({
                              'setpoint': canonicalTemperature(
                                displayTemperature(value['setpoint'] as num, unit) + 1,
                                unit,
                              ).clamp(16, 30),
                            })
                          : null,
                      icon: const Icon(Icons.add_circle_outline),
                    ),
                  ],
                ),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    const Text('Mode'),
                    const SizedBox(width: 16),
                    DropdownButton<String>(
                      value: ['cool', 'auto'].contains(value['mode']) ? value['mode'] as String : 'auto',
                      items: const [
                        DropdownMenuItem(value: 'cool', child: Text('Cool')),
                        DropdownMenuItem(value: 'auto', child: Text('Auto')),
                      ],
                      onChanged: enabled
                          ? (mode) {
                              if (mode != null) widget.onControl({'mode': mode});
                            }
                          : null,
                    ),
                    const SizedBox(width: 8),
                    _pendingIndicator('mode', 'Mode'),
                  ],
                ),
              ],
              if (widget.onHistory != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: widget.onHistory,
                    icon: const Icon(Icons.show_chart),
                    label: const Text('Temperature history'),
                  ),
                ),
              if (!widget.connected || !device.online)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Last confirmed: ${device.lastUpdated.toLocal().toString().substring(0, 16)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
