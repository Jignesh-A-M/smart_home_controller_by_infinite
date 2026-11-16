import '../../room_screen/presentation/room_screen.dart';
import '../widgets/device_grid.dart';
import '../../history_screen/presentation/history_screen.dart';
import '../../common/connection_status_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../domain/entities/home_snapshot.dart';
import '../../../domain/entities/room.dart';
import '../bloc/home_cubit.dart';
import '../bloc/home_state.dart';
import '../widgets/device_card.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  // Build the dashboard from one shared Cubit state.
  @override
  Widget build(BuildContext context) {
    return BlocConsumer<HomeCubit, HomeState>(
      listenWhen: (previous, current) {
        return previous.feedbackId != current.feedbackId;
      },
      listener: (context, state) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(state.feedback ?? ''),
              duration: const Duration(seconds: 5),
              action: switch (state.feedbackAction) {
                FeedbackAction.refresh => SnackBarAction(
                  label: 'Refresh',
                  onPressed: context.read<HomeCubit>().refresh,
                ),
                FeedbackAction.retry when state.retryActions.isNotEmpty => SnackBarAction(
                  label: 'Retry',
                  onPressed: () => context.read<HomeCubit>().runActions(state.retryActions, 'Retry'),
                ),
                _ => null,
              },
            ),
          );
      },
      builder: (context, state) {
        final cubit = context.read<HomeCubit>();
        final data = state.snapshot;
        final connected = state.connection == HubConnection.connected;
        final query = state.query.trim().toLowerCase();
        final devices = data.devices.where((d) {
          final roomName = data.rooms.where((r) => r.id == d.roomId).firstOrNull?.name ?? '';
          if (query.isNotEmpty) {
            return d.name.toLowerCase().contains(query) || roomName.toLowerCase().contains(query);
          }
          return cubit.favourite(d.id, d.favourite);
        }).toList();
        final scenes = data.scenes.where((s) => state.showAllScenes || cubit.favourite(s.id, s.favourite, scene: true));
        return Scaffold(
          appBar: AppBar(
            title: const Row(
              children: [
                Icon(Icons.home_work_outlined),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Infinite Home',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            actions: [
              IconButton(
                tooltip: 'Refresh dashboard',
                onPressed: state.refreshing ? null : cubit.refresh,
                icon: state.refreshing
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.refresh),
              ),
            ],
          ),
          body: ConnectionStatusBody(
            child: SafeArea(
              child: RefreshIndicator(
                onRefresh: cubit.refresh,
                child: ListView(
                  key: const PageStorageKey('home-dashboard'),
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(20),
                  children: [
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1000),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Your home, at a glance',
                              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 5),
                            Text(data.hubName, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                            if (data.lastSync != null) ...[
                              Padding(
                                padding: const EdgeInsets.only(top: 5),
                                child: Text(
                                  'Last synced ${data.lastSync!.toLocal().toString().substring(0, 16)}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                            ],
                            if (!connected) ...[
                              _notice('Showing last confirmed values. Controls are disabled until the hub reconnects.'),
                            ],
                            if (state.error != null) ...[_notice(state.error!, retry: cubit.refresh)],
                            const SizedBox(height: 20),
                            Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primary,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceAround,
                                children: [
                                  _metric('${data.rooms.length}', 'Rooms'),
                                  _metric(
                                    '${data.devices.where((d) => d.online).length}/${data.devices.length}',
                                    'Devices online',
                                  ),
                                  _metric(
                                    '${data.devices.where((d) => d.isLight && d.state['on'] == true).length}',
                                    'Lights on',
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),
                            TextField(
                              controller: _search,
                              onChanged: cubit.search,
                              decoration: InputDecoration(
                                labelText: 'Search devices or rooms',
                                prefixIcon: const Icon(Icons.search),
                                suffixIcon: query.isEmpty
                                    ? null
                                    : IconButton(
                                        tooltip: 'Clear search',
                                        icon: const Icon(Icons.close),
                                        onPressed: () {
                                          _search.clear();
                                          cubit.search('');
                                        },
                                      ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            FilledButton.icon(
                              onPressed: connected && !state.batchRunning && state.pending.isEmpty
                                  ? cubit.allLightsOff
                                  : null,
                              icon: state.batchRunning
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Icon(Icons.lightbulb_outline),
                              label: Text(state.batchRunning ? 'Waiting for confirmations…' : 'All lights off'),
                            ),
                            if (state.retryActions.isNotEmpty) ...[
                              TextButton.icon(
                                onPressed: connected && !state.batchRunning
                                    ? () => cubit.runActions(state.retryActions, 'Retry')
                                    : null,
                                icon: const Icon(Icons.replay),
                                label: Text('Retry ${state.retryActions.length} failed action(s)'),
                              ),
                            ],
                            const SizedBox(height: 24),
                            if (state.loading && data.rooms.isEmpty) ...[
                              const Padding(
                                padding: EdgeInsets.all(24),
                                child: Center(
                                  child: Column(
                                    children: [
                                      CircularProgressIndicator(),
                                      SizedBox(height: 12),
                                      Text('Loading your home…'),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                            if (!state.loading && data.rooms.isEmpty && state.error == null) ...[
                              _notice('No rooms yet. Pull to refresh after the hub is configured.'),
                            ],
                            if (query.isEmpty) ...[
                              _heading('Rooms'),
                              LayoutBuilder(
                                builder: (context, constraints) {
                                  final columns = constraints.maxWidth >= 700 ? 3 : 2;
                                  final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
                                  return Wrap(
                                    spacing: 12,
                                    runSpacing: 12,
                                    children: data.rooms
                                        .map(
                                          (r) => SizedBox(
                                            width: width,
                                            child: _roomCard(
                                              r,
                                              state,
                                              () => Navigator.of(
                                                context,
                                              ).push(MaterialPageRoute<void>(builder: (_) => RoomScreen(room: r))),
                                            ),
                                          ),
                                        )
                                        .toList(),
                                  );
                                },
                              ),
                              const SizedBox(height: 24),
                              _heading(
                                'Favourite scenes',
                                trailing: TextButton(
                                  onPressed: cubit.toggleSceneFilter,
                                  child: Text(state.showAllScenes ? 'Favourites only' : 'All scenes'),
                                ),
                              ),
                              if (scenes.isEmpty) ...[
                                const Text('No favourite scenes. Choose All scenes to add a star.'),
                              ],
                              ...scenes.map(
                                (s) => Card(
                                  child: ListTile(
                                    leading: Icon(_sceneIcon(s.icon)),
                                    title: Text(s.name),
                                    subtitle: Text('${s.actions.length} device actions'),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          tooltip: 'Favourite ${s.name}',
                                          onPressed: () => cubit.toggleFavourite(s.id, s.favourite, scene: true),
                                          icon: Icon(
                                            cubit.favourite(s.id, s.favourite, scene: true)
                                                ? Icons.star_rounded
                                                : Icons.star_outline_rounded,
                                            color: Theme.of(context).colorScheme.primary,
                                          ),
                                        ),
                                        TextButton(
                                          onPressed: connected && !state.batchRunning && state.pending.isEmpty
                                              ? () => cubit.runActions(s.actions, s.name)
                                              : null,
                                          child: const Text('Run'),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 24),
                            ],
                            _heading(query.isNotEmpty ? 'Search results (${devices.length})' : 'Favourite devices'),
                            if (devices.isEmpty && !state.loading) ...[
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 24),
                                child: Text(
                                  query.isNotEmpty
                                      ? 'No matching devices. Try a device or room name.'
                                      : 'No favourite devices. Open a room and tap a star.',
                                ),
                              ),
                            ],
                            DeviceGrid(
                              children: devices
                                  .map(
                                    (d) => DeviceCard(
                                      key: ValueKey(d.id),
                                      device: d,
                                      roomName:
                                          data.rooms.where((r) => r.id == d.roomId).firstOrNull?.name ?? 'Unknown room',
                                      favourite: cubit.favourite(d.id, d.favourite),
                                      connected: connected && !state.batchRunning,
                                      pending: state.pending[d.id],
                                      onFavourite: () => cubit.toggleFavourite(d.id, d.favourite),
                                      onHistory: d.type == DeviceType.sensor && d.state['temperature'] is num
                                          ? () => Navigator.push(
                                              context,
                                              MaterialPageRoute<void>(builder: (_) => HistoryScreen(deviceId: d.id)),
                                            )
                                          : null,
                                      onControl: (patch) => cubit.control(d, patch),
                                    ),
                                  )
                                  .toList(),
                            ),
                            const SizedBox(height: 24),
                          ],
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

  Widget _heading(String text, {Widget? trailing}) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      children: [
        Expanded(
          child: Text(text, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
        ),
        ?trailing,
      ],
    ),
  );

  Widget _metric(String value, String label) => Expanded(
    child: Column(
      children: [
        Text(
          value,
          style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 2,
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
      ],
    ),
  );

  Widget _notice(String text, {VoidCallback? retry}) => Container(
    margin: const EdgeInsets.only(top: 12),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.secondaryContainer,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        Icon(Icons.info_outline, size: 20, color: Theme.of(context).colorScheme.onSecondaryContainer),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text, style: TextStyle(color: Theme.of(context).colorScheme.onSecondaryContainer)),
        ),
        if (retry != null)
          TextButton(
            onPressed: retry,
            style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.primary),
            child: const Text('Retry'),
          ),
      ],
    ),
  );

  Widget _roomCard(Room room, HomeState state, VoidCallback onTap) {
    final devices = state.snapshot.devices.where((d) => d.roomId == room.id).toList();
    return Material(
      key: ValueKey('room-card-${room.id}'),
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(_roomIcon(room.icon), color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 12),
              Text(room.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(height: 5),
              Text(
                '${devices.length} devices',
                style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              Text(
                '${devices.where((d) => d.isLight && d.state['on'] == true).length} lights on',
                style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.primary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

IconData _roomIcon(String icon) => switch (icon) {
  'sofa' => Icons.weekend_outlined,
  'kitchen' => Icons.kitchen_outlined,
  'bed' => Icons.bed_outlined,
  'desk' => Icons.desk_outlined,
  'tree' => Icons.yard_outlined,
  _ => Icons.meeting_room_outlined,
};

IconData _sceneIcon(String icon) => switch (icon) {
  'sunrise' => Icons.wb_twilight,
  'moon' => Icons.bedtime_outlined,
  'movie' => Icons.movie_outlined,
  'lock' => Icons.lock_outline,
  _ => Icons.auto_awesome_outlined,
};
