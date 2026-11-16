import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../domain/entities/home_snapshot.dart';
import '../../../domain/entities/room.dart';
import '../../common/connection_status_banner.dart';
import '../../history_screen/presentation/history_screen.dart';
import '../../home_screen/bloc/home_cubit.dart';
import '../../home_screen/bloc/home_state.dart';
import '../../home_screen/widgets/device_card.dart';
import '../../home_screen/widgets/device_grid.dart';

class RoomScreen extends StatelessWidget {
  const RoomScreen({super.key, required this.room});
  final Room room;

  // Read the selected room's live devices from the dashboard's shared state owner.
  @override
  Widget build(BuildContext context) => BlocBuilder<HomeCubit, HomeState>(
    builder: (context, state) {
      final cubit = context.read<HomeCubit>();
      final currentRoom = state.snapshot.rooms.where((value) => value.id == room.id).firstOrNull;
      final devices = state.snapshot.devices.where((device) => device.roomId == room.id).toList();
      final connected = state.connection == HubConnection.connected && !state.batchRunning;
      final name = currentRoom?.name ?? room.name;
      return Scaffold(
        appBar: AppBar(
          title: Text(name),
          actions: [
            IconButton(
              tooltip: 'Refresh room',
              onPressed: state.refreshing ? null : cubit.refresh,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: ConnectionStatusBody(
          child: SafeArea(
            child: RefreshIndicator(
              onRefresh: cubit.refresh,
              child: ListView(
                key: PageStorageKey('room-${room.id}'),
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                children: [
                  Text('${devices.length} devices', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 16),
                  if (state.error != null)
                    Card(
                      child: ListTile(
                        title: Text(state.error!),
                        trailing: TextButton(
                          onPressed: state.refreshing ? null : cubit.refresh,
                          child: const Text('Retry'),
                        ),
                      ),
                    ),
                  if (state.loading && devices.isEmpty)
                    const Center(child: CircularProgressIndicator())
                  else if (devices.isEmpty)
                    const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Text('No devices in this room.')),
                  DeviceGrid(
                    children: [
                      for (final device in devices)
                        DeviceCard(
                          key: ValueKey(device.id),
                          device: device,
                          roomName: name,
                          favourite: cubit.favourite(device.id, device.favourite),
                          connected: connected,
                          pending: state.pending[device.id],
                          onFavourite: () => cubit.toggleFavourite(device.id, device.favourite),
                          onControl: (patch) => cubit.control(device, patch),
                          onHistory: device.type == DeviceType.sensor && device.state['temperature'] is num
                              ? () => Navigator.of(
                                  context,
                                ).push(MaterialPageRoute<void>(builder: (_) => HistoryScreen(deviceId: device.id)))
                              : null,
                        ),
                    ],
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
