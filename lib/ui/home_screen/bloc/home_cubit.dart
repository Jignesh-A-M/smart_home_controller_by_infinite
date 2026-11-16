import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../domain/entities/home_snapshot.dart';
import '../../../domain/repository/home_repository.dart';
import '../../common/feedback_message.dart';
import 'home_state.dart';

class HomeCubit extends Cubit<HomeState> {
  final HomeRepository repository;
  late final StreamSubscription<HomeSnapshot> homeStreamSubscription;
  late final StreamSubscription<HubConnection> hubStreamSubscription;
  Timer? _connectionBannerTimer;
  late final StreamSubscription<String> messageStreamSubscription;

  HomeCubit(this.repository) : super(const HomeState()) {
    init();
  }

  Future<void> init() async {
    homeStreamSubscription = repository.changes.listen((snapshot) {
      if (!isClosed) {
        emit(
          state.copyWith(
            snapshot: snapshot,
            favourites: {
              for (final device in snapshot.devices)
                'device:${device.id}': repository.isFavourite(device.id, device.favourite),
              for (final scene in snapshot.scenes)
                'scene:${scene.id}': repository.isFavourite(scene.id, scene.favourite, scene: true),
            },
            loading: snapshot.lastSync == null && snapshot.rooms.isEmpty ? state.loading : false,
            clearError: repository.restAvailable,
          ),
        );
      }
    });
    hubStreamSubscription = repository.connections.listen(_onConnectionChanged);
    messageStreamSubscription = repository.messages.listen((message) {
      if (!isClosed) {
        emit(state.copyWith(feedback: message, feedbackAction: FeedbackAction.refresh));
      }
    });
  }

  // Hide successful connection status after five seconds; keep unavailable status visible.
  void _onConnectionChanged(HubConnection connection) {
    if (isClosed || connection == state.connection) return;
    _connectionBannerTimer?.cancel();
    emit(state.copyWith(connection: connection, showConnectionBanner: true));
    if (connection == HubConnection.connected) {
      _connectionBannerTimer = Timer(const Duration(seconds: 5), () {
        if (!isClosed) emit(state.copyWith(showConnectionBanner: false));
      });
    }
  }

  // Show cache first, then refresh HTTP and connect MQTT independently.
  Future<void> start() async {
    try {
      await repository.loadCache();
    } catch (_) {
      emit(state.copyWith(loading: false, error: 'Local cache could not be read. Pull to refresh.'));
    }
    if (isClosed) return;
    unawaited(repository.connect().catchError((Object _) {}));
    await refresh();
  }

  Future<void> refresh() async {
    if (state.refreshing) return;
    emit(state.copyWith(refreshing: true, clearError: true));
    try {
      await repository.refresh();
    } catch (_) {
      if (!isClosed) {
        emit(state.copyWith(error: 'Cannot reach the REST hub. Retrying automatically. Check the server address.'));
      }
    } finally {
      if (!isClosed) emit(state.copyWith(refreshing: false, loading: false));
    }
  }

  // Present a local action result without attaching an unrelated command retry.
  void notify(String message) {
    if (!isClosed) emit(state.copyWith(feedback: message));
  }

  // Filter confirmed cached devices without making a network request.
  void search(String query) => emit(state.copyWith(query: query));

  // Switch between favourite scenes and all cached scenes.
  void toggleSceneFilter() => emit(state.copyWith(showAllScenes: !state.showAllScenes));

  // Resolve a locally stored favourite override before the seed value.
  bool favourite(String id, bool initial, {bool scene = false}) => repository.isFavourite(id, initial, scene: scene);

  // Persist favourite changes through the shared repository.
  Future<void> toggleFavourite(String id, bool initial, {bool scene = false}) async {
    try {
      await repository.setFavourite(id, !favourite(id, initial, scene: scene), scene: scene);
    } catch (_) {
      if (!isClosed) {
        emit(state.copyWith(feedback: 'Could not save favourite. Please retry.'));
      }
    }
  }

  // Keep optimistic previews in memory and remove them on confirmation or failure.
  Future<bool> control(Device device, Map<String, dynamic> patch, {bool feedback = true}) async {
    if (state.pending.containsKey(device.id)) return false;
    if (!repository.connected || !device.controllable) {
      if (feedback) {
        emit(state.copyWith(feedback: 'Device unavailable. Reconnect and retry.'));
      }
      return false;
    }
    emit(state.copyWith(pending: {...state.pending, device.id: Map.of(patch)}));
    try {
      await repository.command(device.id, patch);
      if (!isClosed && feedback && state.retryActions.any((action) => action.deviceId == device.id)) {
        emit(
          state.copyWith(
            retryActions: state.retryActions.where((action) => action.deviceId != device.id).toList(),
            feedback: '${device.name} updated.',
          ),
        );
      }
      return true;
    } catch (error) {
      if (!isClosed && feedback) {
        emit(
          state.copyWith(
            feedback: feedbackMessage(error, fallback: 'Could not update ${device.name}. Please retry.'),
            feedbackAction: FeedbackAction.retry,
            retryActions: [
              ...state.retryActions.where((action) => action.deviceId != device.id),
              SceneAction(device.id, patch),
            ],
          ),
        );
      }
      return false;
    } finally {
      if (!isClosed) {
        emit(state.copyWith(pending: {...state.pending}..remove(device.id)));
      }
    }
  }

  // Build the quick action from lights that are currently on.
  Future<void> allLightsOff() => runActions(
    state.snapshot.devices
        .where((d) => d.isLight && d.state['on'] == true)
        .map((d) => SceneAction(d.id, {'on': false}))
        .toList(),
    'All lights off',
  );

  // Preserve successful device changes and offer retries only for failed actions.
  Future<void> runActions(List<SceneAction> actions, String label) async {
    if (state.batchRunning) return;
    if (!repository.connected) {
      emit(state.copyWith(feedback: 'Hub offline. Reconnect and retry.'));
      return;
    }
    if (actions.isEmpty) {
      emit(state.copyWith(feedback: 'All lights are already off.'));
      return;
    }
    emit(state.copyWith(batchRunning: true, retryActions: []));
    final failed = <SceneAction>[];
    await Future.wait(
      actions.map((action) async {
        final device = state.snapshot.devices.where((d) => d.id == action.deviceId).firstOrNull;
        if (device == null || !await control(device, action.state, feedback: false)) {
          failed.add(action);
        }
      }),
    );
    if (!isClosed) {
      emit(
        state.copyWith(
          batchRunning: false,
          retryActions: failed,
          feedbackAction: failed.isEmpty ? FeedbackAction.none : FeedbackAction.retry,
          feedback:
              '$label: ${actions.length - failed.length} confirmed${failed.isEmpty ? '' : ', ${failed.length} failed. Retry available.'}',
        ),
      );
    }
  }

  // Cancel listeners and release resources when the dashboard owner closes.
  @override
  Future<void> close() async {
    await hubStreamSubscription.cancel();
    await messageStreamSubscription.cancel();
    _connectionBannerTimer?.cancel();
    await homeStreamSubscription.cancel();
    await repository.dispose();
    return super.close();
  }
}
