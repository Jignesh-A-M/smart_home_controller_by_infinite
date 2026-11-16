import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../domain/entities/home_snapshot.dart';
import '../../../domain/repository/home_repository.dart';
import '../../../domain/transport/quick_tile_gateway.dart';
import '../../home_screen/bloc/home_cubit.dart';
import '../../scenes_screen/bloc/scene_bloc.dart';
import '../../scenes_screen/bloc/scene_events.dart';
import '../../settings_screen/bloc/settings_cubit.dart';
import 'quick_tile_state.dart';

class QuickTileCubit extends Cubit<QuickTileState> {
  final HomeRepository repository;
  final QuickTileGateway gateway;
  final HomeCubit home;
  final SceneBloc scenes;
  final SettingsCubit settings;
  final Duration connectionWait;
  StreamSubscription<void>? _requests;
  StreamSubscription<HomeSnapshot>? _changes;
  StreamSubscription<HubConnection>? _readySubscription;
  Completer<bool>? _ready;
  Timer? _readyTimer;
  bool _closing = false;
  String? _configured, _lastToken;
  Future<void> _configuration = Future.value();

  QuickTileCubit({
    required this.repository,
    required this.gateway,
    required this.home,
    required this.scenes,
    required this.settings,
    this.connectionWait = const Duration(seconds: 8),
  }) : super(const QuickTileState());

  // Start native integration after saved preferences are restored.
  Future<void> start() async {
    try {
      final available = await gateway.initialize();
      if (_closing) return;
      emit(QuickTileState(available: available));
      if (!available) return;
      _requests = gateway.requests.listen((_) => _consume());
      _changes = repository.changes.listen((_) => _syncSelection());
      await _syncSelection();
      await _consume();
    } catch (_) {
      if (!_closing) home.notify('Quick Settings tile is unavailable on this device.');
    }
  }

  // Save only a current favourite scene without executing it.
  Future<void> select(Scene scene) async {
    if (!state.available) {
      home.notify('Quick Settings tiles are available in the Android app.');
      return;
    }
    if (!repository.isFavourite(scene.id, scene.favourite, scene: true)) return;
    await settings.setQuickScene(scene.id);
    if (repository.settings.quickSceneId != scene.id || _closing) return;
    try {
      await _syncSelection();
      if (!_closing) {
        home.notify(
          _configured == '${scene.id}/${scene.name}'
              ? '${scene.name} selected for the Quick Settings tile.'
              : 'Could not update the quick tile. Select the scene again.',
        );
      }
    } catch (_) {
      if (!_closing) home.notify('Could not update the quick tile. Select the scene again.');
    }
  }

  // Keep the native label aligned with scene deletion, renaming and favourite changes.
  Future<void> _syncSelection() {
    _configuration = _configuration.then((_) => _configureSelection());
    return _configuration;
  }

  // Serialize platform writes so a successful selection reflects the finished native call.
  Future<void> _configureSelection() async {
    if (_closing || !state.available) return;
    final scene = repository.current.scenes.where((s) => s.id == repository.settings.quickSceneId).firstOrNull;
    final valid = scene != null && repository.isFavourite(scene.id, scene.favourite, scene: true);
    final id = valid ? scene.id : '';
    final name = valid ? scene.name : 'Favourite scene';
    final key = '$id/$name';
    if (_configured == key) return;
    try {
      await gateway.configure(id, name);
      _configured = key;
    } catch (_) {
      _configured = null;
    }
  }

  // Wait briefly for a foreground connection and discard requests that time out.
  Future<bool> _waitForConnection() async {
    if (repository.connected) return true;
    final ready = Completer<bool>();
    _ready = ready;
    _readySubscription = repository.connections.listen((_) {
      if (repository.connected && !ready.isCompleted) ready.complete(true);
    });
    _readyTimer = Timer(connectionWait, () {
      if (!ready.isCompleted) ready.complete(false);
    });
    try {
      return await ready.future;
    } finally {
      _readyTimer?.cancel();
      await _readySubscription?.cancel();
      _ready = null;
    }
  }

  // Reuse the normal scene flow; a tile never maintains an offline command queue.
  Future<void> _consume() async {
    var started = false;
    try {
      final request = await gateway.takeRequest();
      if (_closing || request == null || request.token == _lastToken) return;
      _lastToken = request.token;
      if (state.busy || scenes.state.running) {
        home.notify('A scene is already running. Wait for it to finish.');
        return;
      }
      started = true;
      emit(QuickTileState(available: state.available, busy: true, openScenesVersion: state.openScenesVersion + 1));
      if (request.sceneId.isEmpty) {
        home.notify('Choose a favourite scene using Use for quick tile in Scenes.');
        return;
      }
      if (!await _waitForConnection() || _closing) {
        if (!_closing) home.notify('Hub offline. Reconnect, then tap the quick tile again.');
        return;
      }
      await repository.refresh();
      if (_closing) return;
      final scene = repository.current.scenes.where((s) => s.id == request.sceneId).firstOrNull;
      if (scene == null ||
          !repository.isFavourite(scene.id, scene.favourite, scene: true) ||
          repository.settings.quickSceneId != scene.id) {
        home.notify('The quick-tile scene is no longer available. Choose a favourite scene again.');
        return;
      }
      scenes.add(SceneRunRequested(scene));
    } catch (_) {
      if (!_closing) home.notify('Could not run the quick-tile scene. Check the connection and tap again.');
    } finally {
      if (started && !_closing) {
        emit(QuickTileState(available: state.available, openScenesVersion: state.openScenesVersion));
      }
    }
  }

  // Cancel the bounded wait and native listeners when the application owner closes.
  @override
  Future<void> close() async {
    _closing = true;
    _readyTimer?.cancel();
    if (_ready != null && !_ready!.isCompleted) _ready!.complete(false);
    await _readySubscription?.cancel();
    await _requests?.cancel();
    await _changes?.cancel();
    await _configuration;
    await gateway.dispose();
    return super.close();
  }
}
