import '../../common/feedback_message.dart';
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../domain/entities/home_snapshot.dart';
import '../../../domain/repository/home_repository.dart';
import 'scene_events.dart';
import 'scene_state.dart';

class SceneBloc extends Bloc<SceneEvent, SceneState> {
  final HomeRepository repository;
  late final StreamSubscription<HomeSnapshot> homeStreamSubscription;
  late final StreamSubscription<HubConnection> hubStreamSubscription;

  SceneBloc({required this.repository})
    : super(
        SceneState(
          snapshot: repository.current,
          connection: repository.connected ? HubConnection.connected : HubConnection.offline,
          restAvailable: repository.restAvailable,
        ),
      ) {
    on<ScenesSnapshotChanged>(onSuccessFetchScenes);
    on<ScenesConnectionChanged>(onConnectionChanged);
    on<ScenesRefreshRequested>(onRefreshScenes);
    on<SceneEditorOpened>(onOpenSceneEditor);
    on<SceneDraftChanged>(onChangeSceneDraft);
    on<SceneSaveRequested>(onSaveScene);
    on<SceneDeleteRequested>(onDeleteScene);
    on<SceneFavouriteToggled>(onToggleSceneFavourite);
    on<SceneRunRequested>(onRunScene);
    homeStreamSubscription = repository.changes.listen((value) => add(ScenesSnapshotChanged(value)));
    hubStreamSubscription = repository.connections.listen((value) => add(ScenesConnectionChanged(value)));
  }

  // Apply fetched data through a typed event, including shared local favourites.
  FutureOr<void> onSuccessFetchScenes(ScenesSnapshotChanged event, Emitter<SceneState> emit) {
    emit(
      state.copyWith(
        snapshot: event.snapshot,
        restAvailable: repository.restAvailable,
        favourites: _favourites(event.snapshot),
      ),
    );
  }

  // Update broker readiness independently from REST configuration.
  FutureOr<void> onConnectionChanged(ScenesConnectionChanged event, Emitter<SceneState> emit) {
    emit(state.copyWith(connection: event.connection, restAvailable: repository.restAvailable));
  }

  // Refresh REST configuration independently of the MQTT connection.
  Future<void> onRefreshScenes(ScenesRefreshRequested event, Emitter<SceneState> emit) async {
    if (state.refreshing) return;
    emit(state.copyWith(refreshing: true));
    try {
      await repository.refresh();
      emit(state.copyWith(snapshot: repository.current, refreshing: false, restAvailable: true));
    } catch (_) {
      emit(
        state.copyWith(
          refreshing: false,
          restAvailable: false,
          message: 'Cannot reach the REST hub. Check the server and retry.',
          messageId: state.messageId + 1,
        ),
      );
    }
  }

  // Make an isolated draft so editing never changes saved scenes or physical devices.
  void onOpenSceneEditor(SceneEditorOpened event, Emitter<SceneState> emit) {
    if (state.saving) return;
    final source = event.scene;
    emit(
      state.copyWith(
        draft: Scene(
          id: source?.id ?? 'scene-${DateTime.now().microsecondsSinceEpoch}',
          name: source?.name ?? '',
          icon: source?.icon ?? 'home',
          favourite: source?.favourite ?? false,
          actions: source?.actions.map((a) => SceneAction(a.deviceId, Map.of(a.state))).toList() ?? [],
        ),
        isNew: source == null,
        dirty: false,
        validation: false,
      ),
    );
  }

  // Keep form changes in Bloc state until the user explicitly saves.
  void onChangeSceneDraft(SceneDraftChanged event, Emitter<SceneState> emit) {
    final draft = state.draft;
    if (draft == null || state.saving) return;
    emit(
      state.copyWith(
        draft: Scene(
          id: draft.id,
          name: event.name ?? draft.name,
          icon: event.icon ?? draft.icon,
          favourite: draft.favourite,
          actions: event.actions ?? draft.actions,
        ),
        dirty: true,
      ),
    );
  }

  // Persist the scene definition without executing its target states.
  Future<void> onSaveScene(SceneSaveRequested event, Emitter<SceneState> emit) async {
    final draft = state.draft;
    if (draft == null || state.saving || !state.restAvailable) return;
    if (draft.name.trim().isEmpty || draft.name.trim().length > 60 || draft.actions.isEmpty) {
      emit(state.copyWith(validation: true));
      return;
    }
    emit(state.copyWith(saving: true));
    try {
      await repository.saveScene(draft, isNew: state.isNew);
      emit(
        state.copyWith(
          snapshot: repository.current,
          saving: false,
          dirty: false,
          savedVersion: state.savedVersion + 1,
          message: 'Scene saved.',
          messageId: state.messageId + 1,
        ),
      );
    } catch (error) {
      emit(
        state.copyWith(
          saving: false,
          restAvailable: error is DioException ? false : state.restAvailable,
          message: _error(error),
          messageId: state.messageId + 1,
        ),
      );
    }
  }

  // Delete only after the repository checks for schedules using this scene.
  Future<void> onDeleteScene(SceneDeleteRequested event, Emitter<SceneState> emit) async {
    if (state.deletingId.isNotEmpty || state.saving || state.running || !state.restAvailable) {
      return;
    }
    emit(state.copyWith(deletingId: event.scene.id));
    try {
      await repository.deleteScene(event.scene.id);
      emit(
        state.copyWith(
          snapshot: repository.current,
          deletingId: '',
          clearRun: state.runScene?.id == event.scene.id,
          message: 'Scene deleted.',
          messageId: state.messageId + 1,
        ),
      );
    } catch (error) {
      emit(
        state.copyWith(
          deletingId: '',
          restAvailable: error is DioException ? false : state.restAvailable,
          message: _error(error),
          messageId: state.messageId + 1,
        ),
      );
    }
  }

  // Store favourite overrides locally so stars also work offline.
  Future<void> onToggleSceneFavourite(SceneFavouriteToggled event, Emitter<SceneState> emit) async {
    try {
      await repository.setFavourite(
        event.scene.id,
        !repository.isFavourite(event.scene.id, event.scene.favourite, scene: true),
        scene: true,
      );
      emit(state.copyWith(snapshot: repository.current, favourites: _favourites(repository.current)));
    } catch (_) {
      emit(state.copyWith(message: 'Could not save this favourite. Retry.', messageId: state.messageId + 1));
    }
  }

  // Track every action separately and retry only actions that failed previously.
  Future<void> onRunScene(SceneRunRequested event, Emitter<SceneState> emit) async {
    if (state.running || state.deletingId.isNotEmpty || !repository.connected) {
      return;
    }
    final actions = event.retry
        ? event.scene.actions.where((a) => state.results[a.deviceId] == SceneActionStatus.failed).toList()
        : event.scene.actions;
    if (actions.isEmpty) return;
    final results = event.retry ? Map<String, SceneActionStatus>.of(state.results) : <String, SceneActionStatus>{};
    final failures = event.retry ? Map<String, String>.of(state.failures) : <String, String>{};
    for (final action in actions) {
      results[action.deviceId] = SceneActionStatus.pending;
      failures.remove(action.deviceId);
    }
    emit(state.copyWith(running: true, runScene: event.scene, results: Map.of(results), failures: Map.of(failures)));
    await Future.wait(
      actions.map((action) async {
        try {
          await repository.command(action.deviceId, action.state);
          results[action.deviceId] = SceneActionStatus.confirmed;
        } catch (error) {
          results[action.deviceId] = SceneActionStatus.failed;
          failures[action.deviceId] = _error(error);
        }
        if (!emit.isDone) {
          emit(state.copyWith(results: Map.of(results), failures: Map.of(failures)));
        }
      }),
    );
    if (!emit.isDone) emit(state.copyWith(running: false));
  }

  // Reflect shared local favourites even when the confirmed snapshot is unchanged.
  Map<String, bool> _favourites(HomeSnapshot snapshot) => {
    for (final scene in snapshot.scenes) scene.id: repository.isFavourite(scene.id, scene.favourite, scene: true),
  };

  String _error(Object error) =>
      error is DioException ? 'Cannot reach the REST hub. Your changes are still here. Retry.' : feedbackMessage(error);

  // Cancel listeners without disposing the repository shared with the dashboard.
  @override
  Future<void> close() async {
    await hubStreamSubscription.cancel();
    await homeStreamSubscription.cancel();
    return super.close();
  }
}
