import 'package:equatable/equatable.dart';

import '../../../domain/entities/home_snapshot.dart';

enum SceneActionStatus { pending, confirmed, failed }

class SceneState extends Equatable {
  final HomeSnapshot snapshot;
  final HubConnection connection;
  final bool refreshing, restAvailable, saving, isNew, dirty, validation, running;
  final String deletingId, message;
  final int savedVersion, messageId;
  final Scene? draft, runScene;
  final Map<String, SceneActionStatus> results;
  final Map<String, String> failures;
  final Map<String, bool> favourites;

  const SceneState({
    this.snapshot = const HomeSnapshot(),
    this.connection = HubConnection.offline,
    this.refreshing = false,
    this.restAvailable = false,
    this.saving = false,
    this.deletingId = '',
    this.draft,
    this.isNew = true,
    this.dirty = false,
    this.validation = false,
    this.savedVersion = 0,
    this.message = '',
    this.messageId = 0,
    this.running = false,
    this.runScene,
    this.results = const {},
    this.favourites = const {},
    this.failures = const {},
  });

  // Replace changed values while preserving the rest of the screen state.
  SceneState copyWith({
    HomeSnapshot? snapshot,
    HubConnection? connection,
    bool? refreshing,
    bool? restAvailable,
    bool? saving,
    String? deletingId,
    Scene? draft,
    bool? isNew,
    bool? dirty,
    bool? validation,
    int? savedVersion,
    String? message,
    int? messageId,
    bool? running,
    Scene? runScene,
    Map<String, SceneActionStatus>? results,
    Map<String, String>? failures,
    Map<String, bool>? favourites,
    bool clearRun = false,
  }) => SceneState(
    snapshot: snapshot ?? this.snapshot,
    connection: connection ?? this.connection,
    refreshing: refreshing ?? this.refreshing,
    restAvailable: restAvailable ?? this.restAvailable,
    saving: saving ?? this.saving,
    deletingId: deletingId ?? this.deletingId,
    draft: draft ?? this.draft,
    isNew: isNew ?? this.isNew,
    dirty: dirty ?? this.dirty,
    validation: validation ?? this.validation,
    savedVersion: savedVersion ?? this.savedVersion,
    message: message ?? this.message,
    messageId: messageId ?? this.messageId,
    running: running ?? this.running,
    runScene: clearRun ? null : runScene ?? this.runScene,
    results: clearRun ? const {} : results ?? this.results,
    failures: clearRun ? const {} : failures ?? this.failures,
    favourites: favourites ?? this.favourites,
  );

  @override
  List<Object?> get props => [
    snapshot,
    connection,
    refreshing,
    restAvailable,
    saving,
    deletingId,
    draft,
    isNew,
    dirty,
    validation,
    savedVersion,
    message,
    messageId,
    running,
    runScene,
    results,
    failures,
    favourites,
  ];
}
