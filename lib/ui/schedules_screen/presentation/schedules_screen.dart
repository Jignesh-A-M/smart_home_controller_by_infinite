import '../../common/connection_status_banner.dart';
import '../../common/temperature_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../domain/entities/schedule.dart';
import '../../scenes_screen/widgets/scene_action_editor.dart';
import '../bloc/schedule_bloc.dart';
import '../bloc/schedule_events.dart';
import '../bloc/schedule_state.dart';
import 'schedule_editor.dart';

class SchedulesScreen extends StatelessWidget {
  const SchedulesScreen({super.key});

  // Open an isolated editor while retaining the cached list underneath.
  void _edit(BuildContext context, [Schedule? schedule]) {
    context.read<ScheduleBloc>().add(OpenScheduleEditor(schedule));
    Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const ScheduleEditor()));
  }

  @override
  Widget build(BuildContext context) => BlocConsumer<ScheduleBloc, ScheduleState>(
    listenWhen: (before, after) => before.messageId != after.messageId,
    listener: (context, state) {
      if (ModalRoute.of(context)?.isCurrent == true) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(state.message)));
      }
    },
    builder: (context, state) {
      final bloc = context.read<ScheduleBloc>();
      final editable = state.restAvailable && !state.isSaving && state.busyId.isEmpty;
      return Scaffold(
        appBar: AppBar(
          title: const Text('Schedules'),
          actions: [
            IconButton(
              tooltip: 'Refresh schedules',
              onPressed: state.isLoading ? null : () => bloc.add(RefreshSchedules()),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: ConnectionStatusBody(
          child: SafeArea(
            child: RefreshIndicator(
              onRefresh: () async {
                final complete = bloc.stream.firstWhere((state) => !state.isLoading);
                bloc.add(RefreshSchedules());
                await complete;
              },
              child: ListView(
                padding: const EdgeInsets.all(20),
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  Text(
                    'A routine for your home',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Hub time: Asia/Kolkata (IST). Enabled schedules run on the hub, even with the app closed.',
                  ),
                  if (state.isLoading)
                    const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: LinearProgressIndicator()),
                  if (!state.restAvailable && !state.isLoading)
                    const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: Text(
                        'Showing cached schedules. Refresh to create, edit, delete or change enabled status.',
                      ),
                    ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: editable ? () => _edit(context) : null,
                    icon: const Icon(Icons.add),
                    label: const Text('Create schedule'),
                  ),
                  const SizedBox(height: 16),
                  if (state.snapshot.schedules.isEmpty && !state.isLoading) const Text('No saved schedules yet.'),
                  ...state.snapshot.schedules.map((schedule) {
                    final scene = state.snapshot.scenes.where((scene) => scene.id == schedule.target.id).firstOrNull;
                    final device = state.snapshot.devices
                        .where((device) => device.id == schedule.target.id)
                        .firstOrNull;
                    final target = schedule.target.type == 'scene'
                        ? 'Scene: ${scene?.name ?? 'Missing scene'}'
                        : '${device?.name ?? 'Missing device'}: ${sceneTargetLabel(schedule.target.state, unit: TemperatureScope.of(context))}';
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(child: Text(schedule.name, style: Theme.of(context).textTheme.titleLarge)),
                                Semantics(
                                  label: 'Enable ${schedule.name}',
                                  child: Switch(
                                    value: schedule.enabled,
                                    onChanged: editable
                                        ? (enabled) => bloc.add(ToggleSchedule(schedule, enabled))
                                        : null,
                                  ),
                                ),
                                PopupMenuButton<String>(
                                  tooltip: 'Manage ${schedule.name}',
                                  enabled: editable,
                                  onSelected: (value) async {
                                    if (value == 'edit') {
                                      _edit(context, schedule);
                                      return;
                                    }
                                    final confirmed = await showDialog<bool>(
                                      context: context,
                                      builder: (context) => AlertDialog(
                                        title: Text('Delete ${schedule.name}?'),
                                        content: const Text('The hub will stop running this schedule.'),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.pop(context, false),
                                            child: const Text('Cancel'),
                                          ),
                                          TextButton(
                                            onPressed: () => Navigator.pop(context, true),
                                            child: const Text('Delete'),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (confirmed == true) {
                                      bloc.add(DeleteSchedule(schedule));
                                    }
                                  },
                                  itemBuilder: (_) => const [
                                    PopupMenuItem(value: 'edit', child: Text('Edit')),
                                    PopupMenuItem(value: 'delete', child: Text('Delete')),
                                  ],
                                ),
                              ],
                            ),
                            Text('${schedule.time} IST', style: Theme.of(context).textTheme.headlineSmall),
                            const SizedBox(height: 8),
                            Text(
                              schedule.days.length == 7
                                  ? 'Every day'
                                  : scheduleDays
                                        .where(schedule.days.contains)
                                        .map((day) => '${day[0].toUpperCase()}${day.substring(1)}')
                                        .join(', '),
                            ),
                            const SizedBox(height: 8),
                            Text(target),
                            const SizedBox(height: 8),
                            Text(schedule.enabled ? 'Enabled' : 'Disabled'),
                            if (state.busyId == schedule.id) const LinearProgressIndicator(),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}
