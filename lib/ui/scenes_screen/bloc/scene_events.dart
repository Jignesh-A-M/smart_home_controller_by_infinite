import 'package:equatable/equatable.dart';
import '../../../domain/entities/home_snapshot.dart';

abstract class SceneEvent extends Equatable {
  const SceneEvent();
  @override
  List<Object?> get props => [];
}

class ScenesRefreshRequested extends SceneEvent {}

class ScenesSnapshotChanged extends SceneEvent {
  const ScenesSnapshotChanged(this.snapshot);
  final HomeSnapshot snapshot;
  @override
  List<Object?> get props => [snapshot];
}

class ScenesConnectionChanged extends SceneEvent {
  const ScenesConnectionChanged(this.connection);
  final HubConnection connection;
  @override
  List<Object?> get props => [connection];
}

class SceneEditorOpened extends SceneEvent {
  const SceneEditorOpened([this.scene]);
  final Scene? scene;
  @override
  List<Object?> get props => [scene];
}

class SceneDraftChanged extends SceneEvent {
  const SceneDraftChanged({this.name, this.icon, this.actions});
  final String? name, icon;
  final List<SceneAction>? actions;
  @override
  List<Object?> get props => [name, icon, actions];
}

class SceneSaveRequested extends SceneEvent {}

class SceneDeleteRequested extends SceneEvent {
  const SceneDeleteRequested(this.scene);
  final Scene scene;
  @override
  List<Object?> get props => [scene];
}

class SceneFavouriteToggled extends SceneEvent {
  const SceneFavouriteToggled(this.scene);
  final Scene scene;
  @override
  List<Object?> get props => [scene];
}

class SceneRunRequested extends SceneEvent {
  const SceneRunRequested(this.scene, {this.retry = false});
  final Scene scene;
  final bool retry;
  @override
  List<Object?> get props => [scene, retry];
}
