import '../../quick_tile/bloc/quick_tile_cubit.dart';
import '../../common/connection_status_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../domain/entities/home_snapshot.dart';
import '../../common/temperature_scope.dart';
import '../bloc/scene_bloc.dart';
import '../bloc/scene_events.dart';
import '../bloc/scene_state.dart';
import '../widgets/scene_action_editor.dart';
import 'scene_editor.dart';

class ScenesScreen extends StatelessWidget {
  const ScenesScreen({super.key});

  // Open a separate draft while preserving the list and any run results.
  void _edit(BuildContext context, [Scene? scene]) {
    context.read<SceneBloc>().add(SceneEditorOpened(scene));
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SceneEditor()));
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<SceneBloc, SceneState>(
      listenWhen: (previous, current) => previous.messageId != current.messageId,
      listener: (context, state) {
        if (ModalRoute.of(context)?.isCurrent == true) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(state.message)));
        }
      },
      builder: (context, state) {
        final bloc = context.read<SceneBloc>();
        final connected = state.connection == HubConnection.connected;
        final editable = state.restAvailable && !state.saving && state.deletingId.isEmpty && !state.running;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Scenes'),
            actions: [
              IconButton(
                tooltip: 'Refresh scenes',
                onPressed: state.refreshing ? null : () => bloc.add(ScenesRefreshRequested()),
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          body: ConnectionStatusBody(
            child: SafeArea(
              child: RefreshIndicator(
                onRefresh: () async {
                  final complete = bloc.stream.firstWhere((s) => !s.refreshing);
                  bloc.add(ScenesRefreshRequested());
                  await complete;
                },
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    Text(
                      'Set the mood in one tap',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      connected
                          ? 'Hub connected · device commands available'
                          : 'Hub offline · saved scenes are available to view',
                    ),
                    if (state.refreshing) ...[
                      const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: LinearProgressIndicator()),
                    ],
                    if (!state.restAvailable && !state.refreshing) ...[
                      const Padding(
                        padding: EdgeInsets.only(top: 12),
                        child: Text('REST hub unavailable. Refresh to create, edit or delete scenes.'),
                      ),
                    ],
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: editable ? () => _edit(context) : null,
                      icon: const Icon(Icons.add),
                      label: const Text('Create scene'),
                    ),
                    const SizedBox(height: 16),
                    if (state.snapshot.scenes.isEmpty && !state.refreshing) ...[const Text('No saved scenes yet.')],
                    if (state.runScene != null) ...[_results(context, state)],
                    ...state.snapshot.scenes.map(
                      (scene) => Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(sceneIcon(scene.icon)),
                                  const SizedBox(width: 12),
                                  Expanded(child: Text(scene.name, style: Theme.of(context).textTheme.titleLarge)),
                                  IconButton(
                                    tooltip: 'Favourite ${scene.name}',
                                    onPressed: () => bloc.add(SceneFavouriteToggled(scene)),
                                    icon: Icon(
                                      (state.favourites[scene.id] ?? scene.favourite) ? Icons.star : Icons.star_border,
                                    ),
                                  ),
                                  PopupMenuButton<String>(
                                    tooltip: 'Manage ${scene.name}',
                                    enabled: editable,
                                    onSelected: (value) async {
                                      if (value == 'edit') {
                                        _edit(context, scene);
                                        return;
                                      }
                                      final confirmed = await showDialog<bool>(
                                        context: context,
                                        builder: (context) => AlertDialog(
                                          title: Text('Delete ${scene.name}?'),
                                          content: const Text(
                                            'Scenes used by schedules must be retargeted before deletion.',
                                          ),
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
                                        bloc.add(SceneDeleteRequested(scene));
                                      }
                                    },
                                    itemBuilder: (_) => const [
                                      PopupMenuItem(value: 'edit', child: Text('Edit')),
                                      PopupMenuItem(value: 'delete', child: Text('Delete')),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              ...scene.actions.map((action) {
                                final device = state.snapshot.devices.where((d) => d.id == action.deviceId).firstOrNull;
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: Text(
                                    '${device?.name ?? action.deviceId}${device?.online == false ? ' (offline)' : ''}: ${sceneTargetLabel(action.state, unit: TemperatureScope.of(context))}',
                                  ),
                                );
                              }),
                              if (state.favourites[scene.id] ?? scene.favourite)
                                TextButton.icon(
                                  onPressed: () => context.read<QuickTileCubit>().select(scene),
                                  icon: const Icon(Icons.dashboard_customize_outlined),
                                  label: const Text('Use for quick tile'),
                                ),
                              const SizedBox(height: 12),
                              OutlinedButton.icon(
                                onPressed: connected && !state.running && state.deletingId.isEmpty
                                    ? () => bloc.add(SceneRunRequested(scene))
                                    : null,
                                icon: const Icon(Icons.play_arrow),
                                label: Text(state.running && state.runScene?.id == scene.id ? 'Running…' : 'Run scene'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // Show individual confirmations and keep successful actions intact on partial failure.
  Widget _results(BuildContext context, SceneState state) {
    final failed = state.results.values.where((result) => result == SceneActionStatus.failed).length;
    final confirmed = state.results.values.where((result) => result == SceneActionStatus.confirmed).length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${state.runScene!.name} results', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text('$confirmed/${state.results.length} confirmed${failed > 0 ? ' · $failed failed' : ''}'),
            ...state.results.entries.map((entry) {
              final name = state.snapshot.devices.where((d) => d.id == entry.key).firstOrNull?.name ?? entry.key;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(name),
                subtitle: Text(state.failures[entry.key] ?? entry.value.name),
                leading: Icon(switch (entry.value) {
                  SceneActionStatus.pending => Icons.hourglass_top,
                  SceneActionStatus.confirmed => Icons.check_circle_outline,
                  SceneActionStatus.failed => Icons.error_outline,
                }),
              );
            }),
            if (failed > 0)
              OutlinedButton(
                onPressed: !state.running && state.connection == HubConnection.connected
                    ? () => context.read<SceneBloc>().add(SceneRunRequested(state.runScene!, retry: true))
                    : null,
                child: const Text('Retry failed actions'),
              ),
          ],
        ),
      ),
    );
  }
}
