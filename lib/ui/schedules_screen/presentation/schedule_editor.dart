import '../../common/connection_status_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../common/bloc/editor_navigation_cubit.dart';
import '../../../domain/entities/home_snapshot.dart';
import '../../../domain/entities/schedule.dart';
import '../../scenes_screen/widgets/scene_action_editor.dart';
import '../bloc/schedule_bloc.dart';
import '../bloc/schedule_events.dart';
import '../bloc/schedule_state.dart';

class ScheduleEditor extends StatefulWidget {
  const ScheduleEditor({super.key});
  @override
  State<ScheduleEditor> createState() => _ScheduleEditorState();
}

class _ScheduleEditorState extends State<ScheduleEditor> {
  final _navigation = EditorNavigationCubit();

  @override
  void dispose() {
    _navigation.close();
    super.dispose();
  }

  // Preserve an edited draft until the user saves or explicitly discards it.
  Future<void> _leave() async {
    final state = context.read<ScheduleBloc>().state;
    if (state.isSaving || _navigation.state.asking) return;
    _navigation.asking(true);
    final discard =
        !state.isDirty ||
        await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Discard changes?'),
                content: const Text('Your schedule changes have not been saved.'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep editing')),
                  TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Discard')),
                ],
              ),
            ) ==
            true;
    if (!mounted) return;
    _navigation.asking(false);
    if (discard && mounted) _finish();
  }

  // Permit a route pop only after persistence or an explicit discard decision.
  void _finish() {
    _navigation.finish();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pop(context);
    });
  }

  @override
  Widget build(BuildContext context) => BlocBuilder<EditorNavigationCubit, EditorNavigationState>(
    bloc: _navigation,
    builder: (context, navigation) => BlocConsumer<ScheduleBloc, ScheduleState>(
      listenWhen: (before, after) => before.savedVersion != after.savedVersion || before.messageId != after.messageId,
      listener: (context, state) {
        if (!state.isDirty && !state.isSaving && state.message == 'Schedule saved.') {
          _finish();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(state.message)));
        }
      },
      builder: (context, state) {
        final bloc = context.read<ScheduleBloc>();
        final draft = state.draft;
        if (draft == null) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final enabled = !state.isSaving;
        final isScene = draft.target.type == 'scene';
        final devices = state.snapshot.devices
            .where((device) => device.type != DeviceType.sensor && device.type != DeviceType.unknown)
            .toList();
        final targetIds = isScene
            ? state.snapshot.scenes.map((scene) => scene.id).toSet()
            : devices.map((device) => device.id).toSet();
        return PopScope(
          canPop: navigation.allowPop,
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop) _leave();
          },
          child: Scaffold(
            appBar: AppBar(
              title: Text(state.isNew ? 'Create schedule' : 'Edit schedule'),
              leading: IconButton(
                tooltip: 'Back',
                onPressed: enabled ? _leave : null,
                icon: const Icon(Icons.arrow_back),
              ),
            ),
            body: ConnectionStatusBody(
              maxContentWidth: 760,
              child: SafeArea(
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    const Text(
                      'Times use Asia/Kolkata (IST). The hub runs enabled schedules even when this app is closed.',
                    ),
                    const SizedBox(height: 20),
                    TextFormField(
                      key: ValueKey('name-${draft.id}'),
                      initialValue: draft.name,
                      enabled: enabled,
                      maxLength: 60,
                      decoration: InputDecoration(
                        labelText: 'Schedule name',
                        errorText: state.showValidation && draft.name.trim().isEmpty ? 'Enter a schedule name.' : null,
                      ),
                      onChanged: (value) => bloc.add(ChangeScheduleDraft(name: value)),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      key: ValueKey('time-${draft.id}-${draft.time}'),
                      initialValue: draft.time,
                      readOnly: true,
                      enabled: enabled,
                      decoration: const InputDecoration(labelText: 'Time (IST)', suffixIcon: Icon(Icons.schedule)),
                      onTap: () async {
                        final parts = draft.time.split(':');
                        final time = await showTimePicker(
                          context: context,
                          initialTime: TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1])),
                          builder: (context, child) => MediaQuery(
                            data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
                            child: child!,
                          ),
                        );
                        if (time != null) {
                          bloc.add(
                            ChangeScheduleDraft(
                              time: '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
                            ),
                          );
                        }
                      },
                    ),
                    const SizedBox(height: 20),
                    Text('Repeat days', style: Theme.of(context).textTheme.titleMedium),
                    Wrap(
                      spacing: 8,
                      children: scheduleDays
                          .map(
                            (day) => FilterChip(
                              label: Text('${day[0].toUpperCase()}${day.substring(1)}'),
                              selected: draft.days.contains(day),
                              onSelected: enabled
                                  ? (selected) => bloc.add(
                                      ChangeScheduleDraft(
                                        days: scheduleDays
                                            .where((d) => d == day ? selected : draft.days.contains(d))
                                            .toList(),
                                      ),
                                    )
                                  : null,
                            ),
                          )
                          .toList(),
                    ),
                    if (state.showValidation && draft.days.isEmpty)
                      Text(
                        'Choose at least one repeat day.',
                        style: TextStyle(color: Theme.of(context).colorScheme.error),
                      ),
                    const SizedBox(height: 20),
                    DropdownButtonFormField<String>(
                      key: ValueKey('type-${draft.id}'),
                      initialValue: draft.target.type,
                      decoration: const InputDecoration(labelText: 'Target type'),
                      items: const [
                        DropdownMenuItem(value: 'scene', child: Text('Scene')),
                        DropdownMenuItem(value: 'device', child: Text('Device')),
                      ],
                      onChanged: enabled
                          ? (type) {
                              if (type != null && type != draft.target.type) {
                                bloc.add(
                                  ChangeScheduleDraft(
                                    target: ScheduleTarget(type: type, id: ''),
                                  ),
                                );
                              }
                            }
                          : null,
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      key: ValueKey('target-${draft.id}-${draft.target.type}-${draft.target.id}'),
                      initialValue: targetIds.contains(draft.target.id) ? draft.target.id : null,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: isScene ? 'Scene' : 'Device',
                        errorText: state.showValidation && !targetIds.contains(draft.target.id)
                            ? 'Choose an available target.'
                            : null,
                      ),
                      items: isScene
                          ? state.snapshot.scenes
                                .map(
                                  (scene) => DropdownMenuItem(
                                    value: scene.id,
                                    child: Text(scene.name, overflow: TextOverflow.ellipsis),
                                  ),
                                )
                                .toList()
                          : devices
                                .map(
                                  (device) => DropdownMenuItem(
                                    value: device.id,
                                    child: Text(
                                      '${device.name}${device.online ? '' : ' (offline)'}',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .toList(),
                      onChanged: enabled
                          ? (id) {
                              if (id == null) return;
                              final device = devices.where((device) => device.id == id).firstOrNull;
                              bloc.add(
                                ChangeScheduleDraft(
                                  target: ScheduleTarget(
                                    type: draft.target.type,
                                    id: id,
                                    state: device == null ? const {} : defaultSceneTarget(device),
                                  ),
                                ),
                              );
                            }
                          : null,
                    ),
                    if (!isScene) ...[
                      const SizedBox(height: 8),
                      const Text('Sensors and unsupported devices are read-only.'),
                      if (draft.target.id.isNotEmpty)
                        SceneActionEditor(
                          device: devices.where((device) => device.id == draft.target.id).firstOrNull,
                          action: SceneAction(draft.target.id, draft.target.state),
                          enabled: enabled,
                          onChanged: (target) => bloc.add(
                            ChangeScheduleDraft(
                              target: ScheduleTarget(type: 'device', id: draft.target.id, state: target),
                            ),
                          ),
                          onRemove: () => bloc.add(
                            const ChangeScheduleDraft(
                              target: ScheduleTarget(type: 'device', id: ''),
                            ),
                          ),
                        ),
                    ],
                    const SizedBox(height: 16),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Enabled'),
                      subtitle: const Text('Runs at the chosen time on selected days.'),
                      value: draft.enabled,
                      onChanged: enabled ? (value) => bloc.add(ChangeScheduleDraft(enabled: value)) : null,
                    ),
                    if (!state.restAvailable) ...[
                      const Text('REST hub unavailable. Your draft is preserved.'),
                      TextButton(
                        onPressed: state.isLoading ? null : () => bloc.add(RefreshSchedules()),
                        child: const Text('Retry connection'),
                      ),
                    ],
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: enabled && state.restAvailable ? () => bloc.add(SaveSchedule()) : null,
                      child: Text(state.isSaving ? 'Saving…' : 'Save schedule'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}
