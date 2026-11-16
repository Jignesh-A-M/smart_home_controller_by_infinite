import '../../domain/entities/temperature_reading.dart';
import '../models/temperature_history_model.dart';
import 'dart:async';

import 'package:dio/dio.dart';

import '../../domain/entities/app_settings.dart';
import '../../domain/entities/home_snapshot.dart';
import '../../domain/entities/room.dart';
import '../../domain/entities/schedule.dart';
import '../../domain/repository/home_repository.dart';
import '../../domain/transport/device_transport.dart';
import '../local/home_store.dart';
import '../models/home_model.dart';
import '../models/scene_model.dart';
import '../models/schedule_model.dart';
import '../models/settings_model.dart';

class _Pending {
  _Pending(this.id, this.patch);

  final String id;
  final Map<String, dynamic> patch;
  final done = Completer<void>();
}

// Combine REST configuration, live confirmed state and the local SQLite cache.
class HomeRepositoryImpl implements HomeRepository {
  HomeRepositoryImpl({
    required this.api,
    required this.transport,
    required this.store,
    this.commandTimeout = const Duration(seconds: 3),
    this.transportFactory,
  }) {
    _listenTransport();
  }

  final Dio api;
  DeviceTransport transport;
  final DeviceTransport Function(AppSettings)? transportFactory;
  final HomeStore store;
  final Duration commandTimeout;
  final _changes = StreamController<HomeSnapshot>.broadcast();
  final _connections = StreamController<HubConnection>.broadcast();
  final _messages = StreamController<String>.broadcast();
  final _pending = <String, _Pending>{};
  final _revisions = <String, int>{};
  final _favourites = <String, dynamic>{};
  final _temperatureHistory = <String, List<TemperatureReading>>{};
  Future<void>? _historyWrite;
  late StreamSubscription<DeviceUpdate> _updatesSubscription;
  late StreamSubscription<HubConnection> _connectionSubscription;
  HomeSnapshot _snapshot = const HomeSnapshot();
  HubConnection _connection = HubConnection.offline;
  bool _disposed = false;
  bool _reconfiguring = false;
  bool _restAvailable = false;
  Timer? _restRetry;
  int _generation = 0, _writes = 0;
  AppSettings _settings = const AppSettings();
  Future<void>? _refreshing;
  Future<void> _favouriteWrite = Future.value();
  int _sceneRevision = 0;
  int _scheduleRevision = 0;

  // Bind one active transport and invalidate callbacks from older connections.
  void _listenTransport() {
    _updatesSubscription = transport.updates.listen(
      _receive,
      onError: (Object error) {
        if (!_disposed && !_reconfiguring) {
          _messages.add('Invalid device update received. Last confirmed values are unchanged. Refresh to retry.');
        }
      },
    );
    _connectionSubscription = transport.connections.listen((status) {
      if (_disposed) return;
      if (status == HubConnection.connected) {
        // A failed REST sync retries independently while MQTT stays subscribed.
        _connections.add(_connection = HubConnection.reconnecting);
        unawaited(refresh().catchError((Object _) {}));
      } else {
        _connections.add(_connection = status);
        for (final pending in _pending.values) {
          if (!pending.done.isCompleted) {
            pending.done.completeError(StateError('Connection lost. Retry when connected.'));
          }
        }
      }
    });
  }

  @override
  HomeSnapshot get current => _snapshot;

  // Expose bounded, immutable readings already received from the sensor.
  @override
  List<TemperatureReading> temperatureHistory(String deviceId) =>
      List.unmodifiable(_temperatureHistory[deviceId] ?? []);

  @override
  Future<List<Room>> getRooms() async => List.unmodifiable(_snapshot.rooms);

  @override
  Stream<HomeSnapshot> get changes => _changes.stream;

  @override
  Stream<HubConnection> get connections => _connections.stream;

  @override
  Stream<String> get messages => _messages.stream;

  @override
  bool get connected =>
      !_reconfiguring && _restAvailable && transport.connected && _connection == HubConnection.connected;

  @override
  bool get restAvailable => _restAvailable && !_reconfiguring;

  @override
  bool isFavourite(String id, bool initial, {bool scene = false}) =>
      _favourites['${scene ? 'scene' : 'device'}:$id'] as bool? ?? initial;

  void _emit() {
    if (!_disposed) _changes.add(_snapshot);
  }

  Future<void> _save() => store.write('snapshot', HomeModel(_snapshot).toJson());

  @override
  Future<void> loadCache() async {
    final history = await store.read('temperatureHistory');
    _temperatureHistory
      ..clear()
      ..addAll(const TemperatureHistoryModel().fromJson(history ?? {}));
    _favourites.addAll(await store.read('favourites') ?? {});
    final cached = await store.read('snapshot');
    if (cached != null) {
      _snapshot = const HomeModel(HomeSnapshot()).fromJson(cached);
    }
    _emit();
  }

  @override
  Future<void> connect() => transport.connect();

  @override
  Future<void> refresh() {
    if (_refreshing != null) return _refreshing!;
    _restRetry?.cancel();
    _restRetry = null;
    final generation = _generation;
    late final Future<void> operation;
    operation = _fetch()
        .catchError((Object error, StackTrace stack) {
          if (!_disposed && generation == _generation && error is DioException) {
            _restFailed();
          }
          Error.throwWithStackTrace(error, stack);
        })
        .whenComplete(() {
          if (identical(_refreshing, operation)) _refreshing = null;
        });
    _refreshing = operation;
    return operation;
  }

  // Retry failed REST syncs without waiting for another MQTT connection event.
  void _restFailed() {
    if (_disposed || _reconfiguring) return;
    _restAvailable = false;
    _connections.add(_connection = transport.connected ? HubConnection.reconnecting : HubConnection.offline);
    if (_restRetry != null) return;
    final generation = _generation;
    _restRetry = Timer(const Duration(seconds: 2), () {
      _restRetry = null;
      if (_disposed || _reconfiguring || generation != _generation) return;
      unawaited(refresh().catchError((Object _) {}));
    });
  }

  Future<void> _fetch() async {
    final generation = _generation;
    final sceneRevision = _sceneRevision;
    final scheduleRevision = _scheduleRevision;
    final revisions = Map<String, int>.from(_revisions);
    final values = await Future.wait(
      ['hub', 'rooms', 'devices', 'scenes', 'schedules'].map((resource) => api.get<dynamic>('/$resource')),
    );
    final json = <String, dynamic>{
      'hub': values[0].data,
      'rooms': values[1].data,
      'devices': values[2].data,
      'scenes': values[3].data,
      'schedules': values[4].data,
      'lastSync': DateTime.now().toUtc().toIso8601String(),
    };
    if (_disposed || generation != _generation) return;
    var fresh = const HomeModel(HomeSnapshot()).fromJson(json);
    // Keep live messages received while this REST request was in flight.
    fresh = fresh.withDevices(
      fresh.devices.map((device) {
        final current = _snapshot.devices.where((d) => d.id == device.id).firstOrNull;
        return current != null &&
                ((_revisions[device.id] ?? 0) != (revisions[device.id] ?? 0) ||
                    current.lastUpdated.isAfter(device.lastUpdated))
            ? current
            : device;
      }).toList(),
    );
    // A slower refresh cannot undo a completed scene save or deletion.
    if (sceneRevision != _sceneRevision || scheduleRevision != _scheduleRevision) {
      fresh = HomeSnapshot(
        hubName: fresh.hubName,
        rooms: fresh.rooms,
        devices: fresh.devices,
        scenes: sceneRevision != _sceneRevision ? _snapshot.scenes : fresh.scenes,
        schedules: scheduleRevision != _scheduleRevision ? _snapshot.schedules : fresh.schedules,
        lastSync: fresh.lastSync,
      );
    }
    if (_disposed) return;
    _snapshot = fresh;
    await _save();
    _restAvailable = true;
    _restRetry?.cancel();
    _restRetry = null;
    _emit();
    if (transport.connected && _connection != HubConnection.connected) {
      _connections.add(_connection = HubConnection.connected);
    }
  }

  void _receive(DeviceUpdate update) {
    if (_disposed || _reconfiguring) return;
    final device = _snapshot.devices.where((d) => d.id == update.deviceId).firstOrNull;
    if (device == null) return;
    if (!validState(device.type, update.state)) {
      _messages.add('Invalid update for ${device.name}. Last confirmed values are unchanged. Refresh to retry.');
      return;
    }
    final timestamp = update.timestamp ?? DateTime.now().toUtc();
    if (timestamp.isBefore(device.lastUpdated)) return;
    if (device.type == DeviceType.sensor && update.state['temperature'] is num) {
      _recordTemperature(device.id, timestamp, (update.state['temperature'] as num).toDouble());
    }
    _revisions[device.id] = (_revisions[device.id] ?? 0) + 1;
    _snapshot = _snapshot.withDevices(
      _snapshot.devices.map((d) => d.id == device.id ? d.confirmed(update.state, timestamp) : d).toList(),
    );
    _emit();
    unawaited(
      _save().catchError((Object _) {
        /* Keep confirmed live values if local storage is temporarily unavailable. */
      }),
    );
    final pending = _pending[device.id];
    if (pending != null &&
        pending.id == update.commandId &&
        !pending.done.isCompleted &&
        pending.patch.entries.every((entry) => update.state[entry.key] == entry.value)) {
      pending.done.complete();
    }
  }

  // Keep the latest 360 real readings and persist writes in arrival order.
  void _recordTemperature(String id, DateTime time, double value) {
    final samples = _temperatureHistory.putIfAbsent(id, () => []);
    if (samples.isNotEmpty && !time.isAfter(samples.last.timestamp)) return;
    samples.add(TemperatureReading(time, value));
    if (samples.length > 360) samples.removeRange(0, samples.length - 360);
    _historyWrite = (_historyWrite ?? Future<void>.value())
        .catchError((Object _) {})
        .then((_) {
          return store.write('temperatureHistory', TemperatureHistoryModel(_temperatureHistory).toJson());
        })
        .catchError((Object _) {
          // Keep live readings in memory and retry persistence on the next sample.
        });
  }

  // Clear collected readings together with downloaded hub data.
  Future<void> _clearTemperatureHistory() async {
    await _historyWrite;
    _temperatureHistory.clear();
    await store.write('temperatureHistory', {});
  }

  @override
  Future<void> setFavourite(String id, bool value, {bool scene = false}) =>
      _favouriteWrite = _favouriteWrite.catchError((Object _) {}).then((_) async {
        final next = {..._favourites, '${scene ? 'scene' : 'device'}:$id': value};
        await store.write('favourites', next);
        _favourites
          ..clear()
          ..addAll(next);
        _emit();
      });

  // Store a scene definition through REST; saving never sends device commands.
  @override
  Future<Scene> saveScene(Scene scene, {required bool isNew}) => _write(() => _saveScene(scene, isNew: isNew));

  Future<Scene> _saveScene(Scene scene, {required bool isNew}) async {
    final model = SceneModel(
      id: scene.id,
      name: scene.name.trim(),
      icon: scene.icon,
      favourite: scene.favourite,
      actions: scene.actions,
    );
    const SceneModel().fromJson(model.toJson());
    if (model.name.length > 60) {
      throw const FormatException('Use a scene name of 60 characters or fewer.');
    }
    for (final action in model.actions) {
      final device = _snapshot.devices.where((d) => d.id == action.deviceId).firstOrNull;
      if (device == null || !validCommandTarget(device.type, action.state)) {
        throw const FormatException('Choose supported devices and valid target states.');
      }
    }
    // A retry after a local cache failure updates the same stable scene ID.
    final create = isNew && !_snapshot.scenes.any((s) => s.id == model.id);
    final response = create
        ? await api.post<dynamic>('/scenes', data: model.toJson())
        : await api.patch<dynamic>('/scenes/${Uri.encodeComponent(model.id)}', data: model.toJson());
    final saved = const SceneModel().fromJson(Map<String, dynamic>.from(response.data as Map));
    if (saved.id != model.id) {
      throw const FormatException('Unexpected scene ID in the hub response.');
    }
    _sceneRevision++;
    _replaceScenes([..._snapshot.scenes.where((s) => s.id != saved.id), saved]);
    await _save();
    _emit();
    return saved;
  }

  // Guard schedule references before deleting a scene from the mock server.
  @override
  Future<void> deleteScene(String id) => _write(() => _deleteScene(id));

  Future<void> _deleteScene(String id) async {
    final response = await api.get<dynamic>('/schedules');
    if (response.data is! List) {
      throw const FormatException('Cannot verify schedule references.');
    }
    final referenced = (response.data as List).any(
      (schedule) => schedule['target']?['type'] == 'scene' && schedule['target']?['id'] == id,
    );
    if (referenced) {
      throw StateError('This scene is used by a schedule. Retarget or delete that schedule first.');
    }
    await api.delete<dynamic>('/scenes/${Uri.encodeComponent(id)}');
    _sceneRevision++;
    _replaceScenes(_snapshot.scenes.where((s) => s.id != id).toList());
    await _save();
    _emit();
  }

  void _replaceScenes(List<Scene> scenes) {
    _snapshot = HomeSnapshot(
      hubName: _snapshot.hubName,
      rooms: _snapshot.rooms,
      devices: _snapshot.devices,
      scenes: scenes,
      schedules: _snapshot.schedules,
      lastSync: _snapshot.lastSync,
    );
  }

  // Save configuration only; the running simulator executes due schedules.
  @override
  Future<Schedule> saveSchedule(Schedule schedule, {required bool isNew}) =>
      _write(() => _saveSchedule(schedule, isNew: isNew));

  Future<Schedule> _saveSchedule(Schedule schedule, {required bool isNew}) async {
    final model = ScheduleModel(
      id: schedule.id,
      name: schedule.name.trim(),
      target: schedule.target,
      time: schedule.time,
      days: schedule.days,
      enabled: schedule.enabled,
    );
    const ScheduleModel().fromJson(model.toJson());
    if (model.target.type == 'scene') {
      if (!_snapshot.scenes.any((scene) => scene.id == model.target.id)) {
        throw const FormatException('The selected scene no longer exists. Choose another scene.');
      }
    } else {
      final device = _snapshot.devices.where((device) => device.id == model.target.id).firstOrNull;
      if (device == null || !validCommandTarget(device.type, model.target.state)) {
        throw const FormatException('Choose a supported device and valid target values.');
      }
    }
    final create = isNew && !_snapshot.schedules.any((s) => s.id == model.id);
    final response = create
        ? await api.post<dynamic>('/schedules', data: model.toJson())
        : await api.patch<dynamic>('/schedules/${Uri.encodeComponent(model.id)}', data: model.toJson());
    final saved = const ScheduleModel().fromJson(Map<String, dynamic>.from(response.data as Map));
    if (saved.id != model.id) {
      throw const FormatException('Unexpected schedule ID from the hub.');
    }
    _scheduleRevision++;
    _replaceSchedules([..._snapshot.schedules.where((s) => s.id != saved.id), saved]);
    await _save();
    _emit();
    return saved;
  }

  // Remove a schedule without changing its target scene or device.
  @override
  Future<void> deleteSchedule(String id) => _write(() => _deleteSchedule(id));

  Future<void> _deleteSchedule(String id) async {
    await api.delete<dynamic>('/schedules/${Uri.encodeComponent(id)}');
    _scheduleRevision++;
    _replaceSchedules(_snapshot.schedules.where((s) => s.id != id).toList());
    await _save();
    _emit();
  }

  // Preserve the shared confirmed devices and scenes when schedule data changes.
  void _replaceSchedules(List<Schedule> schedules) {
    _snapshot = HomeSnapshot(
      hubName: _snapshot.hubName,
      rooms: _snapshot.rooms,
      devices: _snapshot.devices,
      scenes: _snapshot.scenes,
      schedules: schedules,
      lastSync: _snapshot.lastSync,
    );
  }

  @override
  AppSettings get settings => _settings;

  // Restore preferences before the app starts fetching data or connecting MQTT.
  @override
  Future<void> loadSettings() async {
    final json = await store.read('settings');
    if (json != null) {
      await _updateSettings(const SettingsModel(AppSettings()).fromJson(json), persist: false, reconnect: false);
    }
  }

  // Save preferences first, then replace only connections whose settings changed.
  @override
  Future<void> saveSettings(AppSettings value) => _updateSettings(value);

  Future<void> _updateSettings(AppSettings value, {bool persist = true, bool reconnect = true}) async {
    SettingsModel.validate(value);
    final changed = !_settings.sameConnection(value);
    if (_reconfiguring || (changed && (_pending.isNotEmpty || _writes > 0))) {
      throw StateError('Wait for the current command or save to finish, then retry.');
    }
    if (!changed) {
      if (persist) await store.write('settings', SettingsModel(value).toJson());
      _settings = value;
      _emit();
      return;
    }
    if (changed && transportFactory == null) {
      throw StateError('Connection changes are unavailable.');
    }
    _reconfiguring = true;
    try {
      if (persist) await store.write('settings', SettingsModel(value).toJson());
      if (changed) {
        _generation++;
        _restRetry?.cancel();
        _restRetry = null;
        _restAvailable = false;
        _refreshing = null;
        _connections.add(_connection = HubConnection.reconnecting);
        await _updatesSubscription.cancel();
        await _connectionSubscription.cancel();
        await transport.dispose();
        api.options.baseUrl = value.restUrl;
        transport = transportFactory!(value);
        _listenTransport();
        if (persist) {
          await store.write('snapshot', const HomeModel(HomeSnapshot()).toJson());
          await _clearTemperatureHistory();
          _snapshot = const HomeSnapshot();
          _revisions.clear();
          _emit();
        }
      }
      _settings = value;
    } finally {
      _reconfiguring = false;
    }
    if (changed && reconnect) {
      unawaited(connect().catchError((Object _) {}));
      unawaited(refresh().catchError((Object _) {}));
    }
  }

  // Clear downloaded hub data while preserving local preferences and stars.
  @override
  Future<void> clearCache() async {
    if (_reconfiguring || _pending.isNotEmpty || _writes > 0) {
      throw StateError('Wait for the current command or save to finish, then retry.');
    }
    _reconfiguring = true;
    try {
      _generation++;
      _restRetry?.cancel();
      _restRetry = null;
      _refreshing = null;
      await store.write('snapshot', const HomeModel(HomeSnapshot()).toJson());
      _restAvailable = false;
      await _clearTemperatureHistory();
      _snapshot = const HomeSnapshot();
      _revisions.clear();
      _emit();
      _connections.add(_connection = HubConnection.offline);
    } finally {
      _reconfiguring = false;
    }
  }

  // Keep settings changes from interrupting REST configuration mutations.
  Future<T> _write<T>(Future<T> Function() action) async {
    if (_reconfiguring) {
      throw StateError('Connection settings are being applied. Retry.');
    }
    _writes++;
    try {
      return await action();
    } catch (error) {
      if (error is DioException) _restFailed();
      rethrow;
    } finally {
      _writes--;
    }
  }

  // Confirm only the matching request; a timeout leaves the confirmed cache unchanged.
  @override
  Future<void> command(String id, Map<String, dynamic> state) async {
    final device = _snapshot.devices.where((d) => d.id == id).firstOrNull;
    if (!connected) throw StateError('Hub offline. Reconnect and retry.');
    if (device == null || !device.controllable) {
      throw StateError('Device offline or read-only.');
    }
    if (_pending.containsKey(id)) {
      throw StateError('A command is already pending for this device.');
    }
    if (!validCommandTarget(device.type, state)) {
      throw const FormatException('Invalid command values.');
    }
    final pending = _Pending('phone-${DateTime.now().microsecondsSinceEpoch}', Map.of(state));
    _pending[id] = pending;
    // Attach timeout handling before publish in case the connection drops immediately.
    final result = pending.done.future.timeout(
      commandTimeout,
      onTimeout: () => throw TimeoutException('${device.name} did not respond. Retry.'),
    );
    try {
      transport.send(id, state, pending.id);
    } catch (error, stack) {
      if (!pending.done.isCompleted) pending.done.completeError(error, stack);
    }
    try {
      await result;
    } finally {
      if (_pending[id] == pending) _pending.remove(id);
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _restRetry?.cancel();
    await _updatesSubscription.cancel();
    await _connectionSubscription.cancel();
    for (final pending in _pending.values) {
      if (!pending.done.isCompleted) {
        pending.done.completeError(StateError('Dashboard closed.'));
      }
    }
    await transport.dispose();
    await _historyWrite;
    await store.close();
    api.close();
    await _changes.close();
    await _connections.close();
    await _messages.close();
  }
}
