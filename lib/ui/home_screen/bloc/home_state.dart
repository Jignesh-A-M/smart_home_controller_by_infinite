import 'package:equatable/equatable.dart';

import '../../../domain/entities/home_snapshot.dart';

enum FeedbackAction { none, retry, refresh }

class HomeState extends Equatable {
  final HomeSnapshot snapshot;
  final bool loading;
  final bool refreshing;
  final bool batchRunning;
  final bool showAllScenes;
  final bool showConnectionBanner;
  final HubConnection connection;
  final Map<String, Map<String, dynamic>> pending;
  final String query;
  final String? feedback;
  final String? error;
  final int feedbackId;
  final FeedbackAction feedbackAction;
  final List<SceneAction> retryActions;
  final Map<String, bool> favourites;

  const HomeState({
    this.snapshot = const HomeSnapshot(),
    this.loading = true,
    this.showAllScenes = false,
    this.showConnectionBanner = true,
    this.refreshing = false,
    this.connection = HubConnection.offline,
    this.pending = const {},
    this.query = '',
    this.feedback,
    this.feedbackId = 0,
    this.feedbackAction = FeedbackAction.none,
    this.error,
    this.batchRunning = false,
    this.retryActions = const [],
    this.favourites = const {},
  });

  // Copy changed fields while preserving the remaining screen state.
  HomeState copyWith({
    HomeSnapshot? snapshot,
    bool? loading,
    bool? showAllScenes,
    bool? showConnectionBanner,
    bool? refreshing,
    HubConnection? connection,
    Map<String, Map<String, dynamic>>? pending,
    String? query,
    String? feedback,
    FeedbackAction? feedbackAction,
    String? error,
    bool clearError = false,
    bool? batchRunning,
    List<SceneAction>? retryActions,
    Map<String, bool>? favourites,
  }) => HomeState(
    snapshot: snapshot ?? this.snapshot,
    loading: loading ?? this.loading,
    showAllScenes: showAllScenes ?? this.showAllScenes,
    showConnectionBanner: showConnectionBanner ?? this.showConnectionBanner,
    refreshing: refreshing ?? this.refreshing,
    connection: connection ?? this.connection,
    pending: pending ?? this.pending,
    query: query ?? this.query,
    feedback: feedback ?? this.feedback,
    feedbackId: feedback == null ? feedbackId : feedbackId + 1,
    feedbackAction: feedbackAction ?? (feedback == null ? this.feedbackAction : FeedbackAction.none),
    error: clearError ? null : error ?? this.error,
    batchRunning: batchRunning ?? this.batchRunning,
    retryActions: retryActions ?? this.retryActions,
    favourites: favourites ?? this.favourites,
  );

  @override
  List<Object?> get props => [
    snapshot,
    loading,
    showAllScenes,
    showConnectionBanner,
    refreshing,
    connection,
    pending,
    query,
    feedback,
    feedbackId,
    feedbackAction,
    error,
    batchRunning,
    retryActions,
    favourites,
  ];
}
