import '../../common/connection_status_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../common/bloc/editor_navigation_cubit.dart';

import '../../../domain/entities/home_snapshot.dart';
import '../bloc/scene_bloc.dart';
import '../bloc/device_selection_cubit.dart';
import '../bloc/scene_events.dart';
import '../bloc/scene_state.dart';
import '../widgets/scene_action_editor.dart';

class SceneEditor extends StatefulWidget {
  const SceneEditor({super.key});

  @override
  State<SceneEditor> createState() => _SceneEditorState();
}

class _SceneEditorState extends State<SceneEditor> {
  final _navigation = EditorNavigationCubit();

  @override
  void dispose() {
    _navigation.close();
    super.dispose();
  }

  // Ask before discarding an edited draft, while blocking navigation during save.
  Future<void> _leave() async {
    final state = context.read<SceneBloc>().state;
    if (state.saving || _navigation.state.asking) return;
    _navigation.asking(true);
    final discard =
        !state.dirty ||
        await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Discard changes?'),
                content: const Text('Your scene changes have not been saved.'),
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

  // Allow the route to pop only after save or an explicit discard decision.
  void _finish() {
    _navigation.finish();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pop(context);
    });
  }

  @override
  Widget build(BuildContext context) => BlocBuilder<EditorNavigationCubit, EditorNavigationState>(
    bloc: _navigation,
    builder: (context, navigation) => BlocConsumer<SceneBloc, SceneState>(
      listenWhen: (previous, current) =>
          previous.savedVersion != current.savedVersion || previous.messageId != current.messageId,
      listener: (context, state) {
        if (!state.dirty && !state.saving && state.message == 'Scene saved.') {
          _finish();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(state.message)));
        }
      },
      builder: (context, state) {
        final bloc = context.read<SceneBloc>();
        final draft = state.draft;
        if (draft == null) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final canEdit = !state.saving;
        return PopScope(
          canPop: navigation.allowPop,
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop) _leave();
          },
          child: Scaffold(
            appBar: AppBar(
              title: Text(state.isNew ? 'Create scene' : 'Edit scene'),
              leading: IconButton(
                tooltip: 'Back',
                onPressed: canEdit ? _leave : null,
                icon: const Icon(Icons.arrow_back),
              ),
            ),
            body: ConnectionStatusBody(
              maxContentWidth: 760,
              child: SafeArea(
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    const Text('Choose target values for each device. Saving does not run the scene.'),
                    const SizedBox(height: 20),
                    TextFormField(
                      key: ValueKey('name-${draft.id}'),
                      initialValue: draft.name,
                      enabled: canEdit,
                      maxLength: 60,
                      decoration: InputDecoration(
                        labelText: 'Scene name',
                        errorText: state.validation && draft.name.trim().isEmpty ? 'Enter a scene name.' : null,
                      ),
                      onChanged: (value) => bloc.add(SceneDraftChanged(name: value)),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      key: ValueKey('icon-${draft.id}'),
                      initialValue: draft.icon,
                      decoration: const InputDecoration(labelText: 'Icon'),
                      items:
                          {
                                ...['home', 'sunrise', 'moon', 'movie', 'lock'],
                                draft.icon,
                              }
                              .map(
                                (icon) => DropdownMenuItem(
                                  value: icon,
                                  child: Row(children: [Icon(sceneIcon(icon)), const SizedBox(width: 12), Text(icon)]),
                                ),
                              )
                              .toList(),
                      onChanged: canEdit ? (value) => bloc.add(SceneDraftChanged(icon: value)) : null,
                    ),
                    const SizedBox(height: 24),
                    Text('Devices (${draft.actions.length})', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: canEdit ? () => _selectDevices(state) : null,
                      icon: const Icon(Icons.add),
                      label: const Text('Choose devices'),
                    ),
                    if (state.validation && draft.actions.isEmpty) ...[
                      Text('Choose at least one device.', style: TextStyle(color: Theme.of(context).colorScheme.error)),
                    ],
                    ...draft.actions.map(
                      (action) => SceneActionEditor(
                        key: ValueKey(action.deviceId),
                        action: action,
                        enabled: canEdit,
                        device: state.snapshot.devices.where((d) => d.id == action.deviceId).firstOrNull,
                        onChanged: (target) => bloc.add(
                          SceneDraftChanged(
                            actions: draft.actions
                                .map((a) => a.deviceId == action.deviceId ? SceneAction(a.deviceId, target) : a)
                                .toList(),
                          ),
                        ),
                        onRemove: () => bloc.add(
                          SceneDraftChanged(
                            actions: draft.actions.where((a) => a.deviceId != action.deviceId).toList(),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    if (!state.restAvailable) ...[
                      const Text('REST hub unavailable. Your draft is preserved; reconnect before saving.'),
                      TextButton(
                        onPressed: state.refreshing ? null : () => bloc.add(ScenesRefreshRequested()),
                        child: const Text('Retry connection'),
                      ),
                    ],
                    FilledButton(
                      onPressed: canEdit && state.restAvailable ? () => bloc.add(SceneSaveRequested()) : null,
                      child: Text(state.saving ? 'Saving…' : 'Save scene'),
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

  // Return a chosen device list without changing existing targets or running actions.
  Future<void> _selectDevices(SceneState state) async {
    final initial = state.draft!.actions.map((a) => a.deviceId).toSet();
    final chosen = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      builder: (context) => BlocProvider(
        create: (_) => DeviceSelectionCubit(initial),
        child: BlocBuilder<DeviceSelectionCubit, Set<String>>(
          builder: (context, selected) => SafeArea(
            child: SizedBox(
              height: MediaQuery.sizeOf(context).height * .8,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text('Choose devices', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                        ),
                        TextButton(onPressed: () => Navigator.pop(context, selected), child: const Text('Done')),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      children: state.snapshot.devices.map((device) {
                        final supported = device.type != DeviceType.sensor && device.type != DeviceType.unknown;
                        final room = state.snapshot.rooms.where((r) => r.id == device.roomId).firstOrNull?.name ?? '';
                        return CheckboxListTile(
                          title: Text(device.name),
                          subtitle: Text(
                            '$room${!supported
                                ? ' · Read-only / unsupported'
                                : !device.online
                                ? ' · Offline'
                                : ''}',
                          ),
                          value: selected.contains(device.id),
                          onChanged: supported
                              ? (value) => context.read<DeviceSelectionCubit>().select(device.id, value == true)
                              : null,
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (chosen == null || !mounted) return;
    final current = context.read<SceneBloc>().state.draft!;
    final actions = current.actions.where((a) => chosen.contains(a.deviceId)).toList();
    for (final device in state.snapshot.devices.where((d) => chosen.contains(d.id))) {
      if (!actions.any((a) => a.deviceId == device.id)) {
        actions.add(SceneAction(device.id, defaultSceneTarget(device)));
      }
    }
    context.read<SceneBloc>().add(SceneDraftChanged(actions: actions));
  }
}
