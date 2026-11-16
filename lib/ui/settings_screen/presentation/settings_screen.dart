import '../../common/connection_status_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../domain/entities/app_settings.dart';
import '../bloc/settings_cubit.dart';
import '../bloc/settings_state.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) => BlocConsumer<SettingsCubit, SettingsState>(
    listenWhen: (previous, current) => previous.messageId != current.messageId,
    listener: (context, state) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(state.message))),
    builder: (context, state) {
      final cubit = context.read<SettingsCubit>();
      final enabled = !state.isSaving;
      return Scaffold(
        appBar: AppBar(title: const Text('Settings')),
        body: ConnectionStatusBody(
          maxContentWidth: 760,
          child: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  'Make it yours',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Appearance', style: Theme.of(context).textTheme.titleLarge),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Dark appearance'),
                          value: state.saved.darkMode,
                          onChanged: enabled ? cubit.setDarkMode : null,
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<TemperatureUnit>(
                          key: ValueKey(state.saved.temperatureUnit),
                          initialValue: state.saved.temperatureUnit,
                          decoration: const InputDecoration(labelText: 'Temperature units'),
                          items: const [
                            DropdownMenuItem(value: TemperatureUnit.celsius, child: Text('Celsius (°C)')),
                            DropdownMenuItem(value: TemperatureUnit.fahrenheit, child: Text('Fahrenheit (°F)')),
                          ],
                          onChanged: enabled
                              ? (unit) {
                                  if (unit != null) {
                                    cubit.setTemperatureUnit(unit);
                                  }
                                }
                              : null,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Units change how temperatures are displayed and entered. Device data stays in Celsius.',
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Hub connection', style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 12),
                        const Text('Use the same MQTT broker and unique topic prefix as your simulator.'),
                        const SizedBox(height: 16),
                        TextFormField(
                          initialValue: state.draft.restUrl,
                          enabled: enabled,
                          autocorrect: false,
                          keyboardType: TextInputType.url,
                          decoration: const InputDecoration(
                            labelText: 'REST server URL',
                            hintText: 'http://127.0.0.1:3000',
                          ),
                          onChanged: (value) => cubit.changeConnection(restUrl: value),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          initialValue: state.draft.mqttHost,
                          enabled: enabled,
                          autocorrect: false,
                          decoration: const InputDecoration(labelText: 'MQTT broker hostname'),
                          onChanged: (value) => cubit.changeConnection(mqttHost: value),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          initialValue: state.portText,
                          enabled: enabled,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'MQTT port'),
                          onChanged: (value) => cubit.changeConnection(port: value),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          initialValue: state.draft.topicPrefix,
                          enabled: enabled,
                          autocorrect: false,
                          decoration: const InputDecoration(labelText: 'MQTT topic prefix'),
                          onChanged: (value) => cubit.changeConnection(topicPrefix: value),
                        ),
                        if (state.error.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(state.error, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                          ),
                        const SizedBox(height: 20),
                        FilledButton(
                          onPressed: enabled ? cubit.applyConnection : null,
                          child: Text(state.isSaving ? 'Saving…' : 'Apply connection'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Favourite scene quick tile', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                        SizedBox(height: 8),
                        Text(
                          'Star a scene, choose Use for quick tile in Scenes, then add Favourite scene from the Quick Settings edit menu. Tapping the tile opens the app and runs the selected scene when connected.',
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  icon: const Icon(Icons.cleaning_services_outlined),
                  label: const Text('Clear downloaded cache'),
                  onPressed: enabled
                      ? () async {
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Clear downloaded cache?'),
                              content: const Text(
                                'Removes downloaded rooms, devices, scenes, schedules, sensor history and last-sync data from this phone. Settings and favourite stars stay. The backend database is unchanged.',
                              ),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                                TextButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  child: const Text('Clear cache'),
                                ),
                              ],
                            ),
                          );
                          if (confirmed == true) await cubit.clearCache();
                        }
                      : null,
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
