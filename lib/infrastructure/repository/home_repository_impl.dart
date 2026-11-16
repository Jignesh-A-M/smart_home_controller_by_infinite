import 'dart:async';

import 'package:dio/dio.dart';

import '../../domain/entities/app_settings.dart';
import '../../domain/entities/home_snapshot.dart';
import '../../domain/entities/room.dart';
import '../../domain/entities/schedule.dart';
import '../../domain/entities/temperature_reading.dart';
import '../../domain/repository/home_repository.dart';
import '../../domain/transport/device_transport.dart';
import '../local/home_store.dart';
import '../models/home_model.dart';
import '../models/scene_model.dart';
import '../models/schedule_model.dart';
import '../models/settings_model.dart';
import '../models/temperature_history_model.dart';

// Remember the command ID, requested values and reply we are waiting for.
class _PendingCommand {
  _PendingCommand({required this.commandId, required this.targetState});

  final String commandId;
  final Map<String, dynamic> targetState;

  // The MQTT reply completes the Future that command() is waiting for.
  final confirmation = Completer<void>();
}

// Share REST data, confirmed MQTT updates and SQLite data with Bloc/Cubit.
class HomeRepositoryImpl implements HomeRepository {
  // Setup and shared data

  final Dio api;
  DeviceTransport transport;
  final HomeStore store;
  final Duration commandTimeout;
  final DeviceTransport Function(AppSettings)? transportFactory;

  final _snapshotController = StreamController<HomeSnapshot>.broadcast();
  final _connectionController = StreamController<HubConnection>.broadcast();
  final _messageController = StreamController<String>.broadcast();
  late StreamSubscription<DeviceUpdate> _deviceSubscription;
  late StreamSubscription<HubConnection> _connectionSubscription;

  HomeSnapshot _snapshot = const HomeSnapshot();
  AppSettings _settings = const AppSettings();
  HubConnection _connectionStatus = HubConnection.offline;
  bool _isDisposed = false;
  bool _isChangingConnection = false;
  bool _restAvailable = false;
  Timer? _restRetryTimer;

  final _pendingCommands = <String, _PendingCommand>{};
  final _favouriteOverrides = <String, dynamic>{};
  final _temperatureHistory = <String, List<TemperatureReading>>{};

  // These futures keep local writes in order and let callers share one refresh.
  Future<void>? _activeRefresh;
  Future<void>? _lastHistorySave;
  Future<void>? _lastFavouriteSave;

  // Changing settings invalidates requests started with the old server address.
  int _connectionVersion = 0;
  int _activeSaves = 0;

  // Versions stop a slow REST refresh from replacing newer MQTT or CRUD changes.
  final _deviceVersions = <String, int>{};
  int _sceneVersion = 0;
  int _scheduleVersion = 0;

  HomeRepositoryImpl({
    required this.api,
    required this.transport,
    required this.store,
    this.commandTimeout = const Duration(seconds: 3),
    this.transportFactory,
  }) {
    _listenToTransport();
  }

  // Return the last confirmed home data.
  @override
  HomeSnapshot get current => _snapshot;

  // Notify Bloc/Cubit when home data changes.
  @override
  Stream<HomeSnapshot> get changes => _snapshotController.stream;

  // Notify Bloc/Cubit when the hub connection changes.
  @override
  Stream<HubConnection> get connections => _connectionController.stream;

  // Report recoverable errors without replacing useful data.
  @override
  Stream<String> get messages => _messageController.stream;

  // Allow commands only when REST and MQTT are both ready.
  @override
  bool get connected {
    if (_isChangingConnection || !_restAvailable || !transport.connected) {
      return false;
    }
    return _connectionStatus == HubConnection.connected;
  }

  // Allow REST operations while the current server is reachable.
  @override
  bool get restAvailable => _restAvailable && !_isChangingConnection;

  // Return the current preferences.
  @override
  AppSettings get settings => _settings;

  // Return the rooms already loaded into memory.
  @override
  Future<List<Room>> getRooms() async {
    return List.unmodifiable(_snapshot.rooms);
  }

  // Return sensor readings without allowing callers to edit the stored list.
  @override
  List<TemperatureReading> temperatureHistory(String deviceId) {
    return List.unmodifiable(_temperatureHistory[deviceId] ?? []);
  }

  // Use the local favourite choice when one exists.
  @override
  bool isFavourite(String id, bool initial, {bool scene = false}) {
    final type = scene ? 'scene' : 'device';
    final savedValue = _favouriteOverrides['$type:$id'] as bool?;
    return savedValue ?? initial;
  }

  // Find a device in the confirmed home data.
  Device? _findDevice(String id) {
    for (final device in _snapshot.devices) {
      if (device.id == id) return device;
    }
    return null;
  }

  // Tell listeners that the confirmed home data changed.
  void _notifySnapshotChanged() {
    if (!_isDisposed) _snapshotController.add(_snapshot);
  }

  // Count active REST saves so settings cannot interrupt them.
  void _beginSave() {
    if (_isChangingConnection) {
      throw StateError('Connection settings are being applied. Retry.');
    }
    _activeSaves++;
  }

  // Load and refresh home data

  // Share an existing refresh instead of sending duplicate REST requests.
  @override
  Future<void> refresh() {
    if (_activeRefresh != null) return _activeRefresh!;
    _restRetryTimer?.cancel();
    _restRetryTimer = null;

    final operation = _refreshFromServer(_connectionVersion);
    _activeRefresh = operation;
    return operation;
  }

  // Fetch data and schedule recovery only when the current REST server fails.
  Future<void> _refreshFromServer(int connectionVersion) async {
    try {
      await _fetchSnapshot();
    } on DioException {
      if (!_isDisposed && connectionVersion == _connectionVersion) {
        _markRestUnavailable();
      }
      rethrow;
    } finally {
      if (connectionVersion == _connectionVersion) _activeRefresh = null;
    }
  }

  // Load all REST resources and preserve any newer local changes.
  Future<void> _fetchSnapshot() async {
    final connectionVersion = _connectionVersion;
    final sceneVersion = _sceneVersion;
    final scheduleVersion = _scheduleVersion;
    final deviceVersions = Map<String, int>.from(_deviceVersions);

    final responses = await Future.wait([
      api.get<dynamic>('/hub'),
      api.get<dynamic>('/rooms'),
      api.get<dynamic>('/devices'),
      api.get<dynamic>('/scenes'),
      api.get<dynamic>('/schedules'),
    ]);
    if (_isDisposed || connectionVersion != _connectionVersion) return;

    final json = <String, dynamic>{
      'hub': responses[0].data,
      'rooms': responses[1].data,
      'devices': responses[2].data,
      'scenes': responses[3].data,
      'schedules': responses[4].data,
      'lastSync': DateTime.now().toUtc().toIso8601String(),
    };
    final fetched = const HomeModel(HomeSnapshot()).fromJson(json);
    final devices = <Device>[];

    for (final fetchedDevice in fetched.devices) {
      final currentDevice = _findDevice(fetchedDevice.id);
      if (currentDevice != null) {
        final receivedDuringRefresh =
            (_deviceVersions[fetchedDevice.id] ?? 0) != (deviceVersions[fetchedDevice.id] ?? 0);
        final hasNewerTimestamp = currentDevice.lastUpdated.isAfter(fetchedDevice.lastUpdated);
        if (receivedDuringRefresh || hasNewerTimestamp) {
          devices.add(currentDevice);
          continue;
        }
      }
      devices.add(fetchedDevice);
    }

    var scenes = fetched.scenes;
    if (sceneVersion != _sceneVersion) scenes = _snapshot.scenes;
    var schedules = fetched.schedules;
    if (scheduleVersion != _scheduleVersion) schedules = _snapshot.schedules;

    _snapshot = HomeSnapshot(
      hubName: fetched.hubName,
      rooms: fetched.rooms,
      devices: devices,
      scenes: scenes,
      schedules: schedules,
      lastSync: fetched.lastSync,
    );
    await _saveSnapshot();
    _restAvailable = true;
    _restRetryTimer?.cancel();
    _restRetryTimer = null;
    _notifySnapshotChanged();
    if (transport.connected && _connectionStatus != HubConnection.connected) {
      _setConnectionStatus(HubConnection.connected);
    }
  }

  // Refresh automatically while keeping existing data if the request fails.
  Future<void> _refreshInBackground() async {
    try {
      await refresh();
    } catch (_) {
      // REST connection failures schedule their next attempt in refresh().
    }
  }

  // Retry REST after two seconds without restarting a working MQTT connection.
  void _markRestUnavailable() {
    if (_isDisposed || _isChangingConnection) return;
    _restAvailable = false;
    if (transport.connected) {
      _setConnectionStatus(HubConnection.reconnecting);
    } else {
      _setConnectionStatus(HubConnection.offline);
    }
    if (_restRetryTimer != null) return;

    final connectionVersion = _connectionVersion;
    _restRetryTimer = Timer(const Duration(seconds: 2), () {
      _restRetryTimer = null;
      if (_isDisposed || _isChangingConnection || connectionVersion != _connectionVersion) {
        return;
      }
      unawaited(_refreshInBackground());
    });
  }

  /// ================= Scenes =============================
  //region Scenes
  // Scenes

  // Validate and save a scene through REST without running its actions.
  @override
  Future<Scene> saveScene(Scene scene, {required bool isNew}) async {
    _beginSave();
    try {
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
        final device = _findDevice(action.deviceId);
        if (device == null || !validCommandTarget(device.type, action.state)) {
          throw const FormatException('Choose supported devices and valid target states.');
        }
      }

      final alreadyExists = _snapshot.scenes.any((savedScene) => savedScene.id == model.id);
      Response<dynamic> response;
      if (isNew && !alreadyExists) {
        response = await api.post<dynamic>('/scenes', data: model.toJson());
      } else {
        final id = Uri.encodeComponent(model.id);
        response = await api.patch<dynamic>('/scenes/$id', data: model.toJson());
      }
      final savedScene = const SceneModel().fromJson(Map<String, dynamic>.from(response.data as Map));
      if (savedScene.id != model.id) {
        throw const FormatException('Unexpected scene ID in the hub response.');
      }

      final scenes = List<Scene>.from(_snapshot.scenes);
      scenes.removeWhere((scene) => scene.id == savedScene.id);
      scenes.add(savedScene);
      _sceneVersion++;
      _replaceScenes(scenes);
      await _saveSnapshot();
      _notifySnapshotChanged();
      return savedScene;
    } on DioException {
      _markRestUnavailable();
      rethrow;
    } finally {
      _activeSaves--;
    }
  }

  // Delete a scene only after checking that no schedule uses it.
  @override
  Future<void> deleteScene(String id) async {
    _beginSave();
    try {
      final response = await api.get<dynamic>('/schedules');
      if (response.data is! List) {
        throw const FormatException('Cannot verify schedule references.');
      }
      for (final schedule in response.data as List) {
        if (schedule['target']?['type'] == 'scene' && schedule['target']?['id'] == id) {
          throw StateError('This scene is used by a schedule. Retarget or delete that schedule first.');
        }
      }

      await api.delete<dynamic>('/scenes/${Uri.encodeComponent(id)}');
      final scenes = List<Scene>.from(_snapshot.scenes);
      scenes.removeWhere((scene) => scene.id == id);
      _sceneVersion++;
      _replaceScenes(scenes);
      await _saveSnapshot();
      _notifySnapshotChanged();
    } on DioException {
      _markRestUnavailable();
      rethrow;
    } finally {
      _activeSaves--;
    }
  }

  // Replace scenes while keeping the other confirmed home data.
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
  //endregion
  /// ================================================

  /// ================== Schedules =======================
  //region Schedules
  // Schedules

  // Validate and save schedule configuration for the backend scheduler.
  @override
  Future<Schedule> saveSchedule(Schedule schedule, {required bool isNew}) async {
    _beginSave();
    try {
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
        final sceneExists = _snapshot.scenes.any((scene) => scene.id == model.target.id);
        if (!sceneExists) {
          throw const FormatException('The selected scene no longer exists. Choose another scene.');
        }
      } else {
        final device = _findDevice(model.target.id);
        if (device == null || !validCommandTarget(device.type, model.target.state)) {
          throw const FormatException('Choose a supported device and valid target values.');
        }
      }

      final alreadyExists = _snapshot.schedules.any((savedSchedule) => savedSchedule.id == model.id);
      Response<dynamic> response;
      if (isNew && !alreadyExists) {
        response = await api.post<dynamic>('/schedules', data: model.toJson());
      } else {
        final id = Uri.encodeComponent(model.id);
        response = await api.patch<dynamic>('/schedules/$id', data: model.toJson());
      }
      final savedSchedule = const ScheduleModel().fromJson(Map<String, dynamic>.from(response.data as Map));
      if (savedSchedule.id != model.id) {
        throw const FormatException('Unexpected schedule ID from the hub.');
      }

      final schedules = List<Schedule>.from(_snapshot.schedules);
      schedules.removeWhere((schedule) => schedule.id == savedSchedule.id);
      schedules.add(savedSchedule);
      _scheduleVersion++;
      _replaceSchedules(schedules);
      await _saveSnapshot();
      _notifySnapshotChanged();
      return savedSchedule;
    } on DioException {
      _markRestUnavailable();
      rethrow;
    } finally {
      _activeSaves--;
    }
  }

  // Remove a schedule without changing its target scene or device.
  @override
  Future<void> deleteSchedule(String id) async {
    _beginSave();
    try {
      await api.delete<dynamic>('/schedules/${Uri.encodeComponent(id)}');
      final schedules = List<Schedule>.from(_snapshot.schedules);
      schedules.removeWhere((schedule) => schedule.id == id);
      _scheduleVersion++;
      _replaceSchedules(schedules);
      await _saveSnapshot();
      _notifySnapshotChanged();
    } on DioException {
      _markRestUnavailable();
      rethrow;
    } finally {
      _activeSaves--;
    }
  }

  // Replace schedules while keeping the other confirmed home data.
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
  //endregion

  /// ==================================================

  /// =================== Local storage ===================================///

  //region Local storage
  // Restore readings, favourite choices and the last confirmed home data.
  @override
  Future<void> loadCache() async {
    final historyJson = await store.read('temperatureHistory');
    final history = const TemperatureHistoryModel().fromJson(historyJson ?? {});
    _temperatureHistory.clear();
    _temperatureHistory.addAll(history);

    final favourites = await store.read('favourites');
    _favouriteOverrides.addAll(favourites ?? {});

    final snapshotJson = await store.read('snapshot');
    if (snapshotJson != null) {
      _snapshot = const HomeModel(HomeSnapshot()).fromJson(snapshotJson);
    }
    _notifySnapshotChanged();
  }

  // Save confirmed home data for the next offline launch.
  Future<void> _saveSnapshot() async {
    await store.write('snapshot', HomeModel(_snapshot).toJson());
  }

  // Keep live confirmed values even if saving the offline snapshot fails.
  Future<void> _saveSnapshotInBackground() async {
    try {
      await _saveSnapshot();
    } catch (_) {
      // The next update or refresh can save the snapshot again.
    }
  }

  // Queue favourite saves so quick taps cannot overwrite each other.
  @override
  Future<void> setFavourite(String id, bool value, {bool scene = false}) {
    final operation = _saveFavourite(_lastFavouriteSave, id, value, scene);
    _lastFavouriteSave = operation;
    return operation;
  }

  // Save a local favourite choice before notifying the screen.
  Future<void> _saveFavourite(Future<void>? previousSave, String id, bool value, bool scene) async {
    try {
      await previousSave;
    } catch (_) {
      // A failed earlier save must not block the user's next choice.
    }

    final type = scene ? 'scene' : 'device';
    final favourites = Map<String, dynamic>.from(_favouriteOverrides);
    favourites['$type:$id'] = value;
    await store.write('favourites', favourites);
    _favouriteOverrides.clear();
    _favouriteOverrides.addAll(favourites);
    _notifySnapshotChanged();
  }

  // Keep the latest 360 received readings and queue their local save.
  void _recordTemperature(String id, DateTime timestamp, double temperature) {
    final readings = _temperatureHistory.putIfAbsent(id, () => []);
    if (readings.isNotEmpty && !timestamp.isAfter(readings.last.timestamp)) return;
    readings.add(TemperatureReading(timestamp, temperature));
    if (readings.length > 360) {
      readings.removeRange(0, readings.length - 360);
    }
    _lastHistorySave = _saveTemperatureHistory(_lastHistorySave);
  }

  // Wait for the previous history save so newer data is written last.
  Future<void> _saveTemperatureHistory(Future<void>? previousSave) async {
    try {
      await previousSave;
      final json = TemperatureHistoryModel(_temperatureHistory).toJson();
      await store.write('temperatureHistory', json);
    } catch (_) {
      // Keep readings in memory and try saving again on the next sample.
    }
  }

  // Clear readings after any history save already in progress finishes.
  Future<void> _clearTemperatureHistory() async {
    await _lastHistorySave;
    _temperatureHistory.clear();
    await store.write('temperatureHistory', {});
  }

  // Clear downloaded data while preserving preferences and favourite choices.
  @override
  Future<void> clearCache() async {
    if (_isChangingConnection || _pendingCommands.isNotEmpty || _activeSaves > 0) {
      throw StateError('Wait for the current command or save to finish, then retry.');
    }
    _isChangingConnection = true;
    try {
      _connectionVersion++;
      _restRetryTimer?.cancel();
      _restRetryTimer = null;
      _activeRefresh = null;
      await store.write('snapshot', const HomeModel(HomeSnapshot()).toJson());
      _restAvailable = false;
      await _clearTemperatureHistory();
      _snapshot = const HomeSnapshot();
      _deviceVersions.clear();
      _notifySnapshotChanged();
      _setConnectionStatus(HubConnection.offline);
    } finally {
      _isChangingConnection = false;
    }
  }
  //endregion

  /// ========================================================

  /// ====================== Settings =======================///

  //region Settings
  // Settings

  // Restore saved preferences before the app starts its connections.
  @override
  Future<void> loadSettings() async {
    final json = await store.read('settings');
    if (json == null) return;
    final savedSettings = const SettingsModel(AppSettings()).fromJson(json);
    await _applySettings(savedSettings, persist: false, reconnect: false);
  }

  // Save preferences and reconnect if the server or MQTT settings changed.
  @override
  Future<void> saveSettings(AppSettings value) async {
    await _applySettings(value);
  }

  // Save preferences before replacing connections or clearing old hub data.
  Future<void> _applySettings(AppSettings value, {bool persist = true, bool reconnect = true}) async {
    SettingsModel.validate(value);
    final connectionChanged = !_settings.sameConnection(value);
    final hasActiveWork = _pendingCommands.isNotEmpty || _activeSaves > 0;
    if (_isChangingConnection || (connectionChanged && hasActiveWork)) {
      throw StateError('Wait for the current command or save to finish, then retry.');
    }

    if (!connectionChanged) {
      if (persist) await store.write('settings', SettingsModel(value).toJson());
      _settings = value;
      _notifySnapshotChanged();
      return;
    }

    final createTransport = transportFactory;
    if (createTransport == null) {
      throw StateError('Connection changes are unavailable.');
    }
    _isChangingConnection = true;
    try {
      if (persist) await store.write('settings', SettingsModel(value).toJson());
      _connectionVersion++;
      _restRetryTimer?.cancel();
      _restRetryTimer = null;
      _restAvailable = false;
      _activeRefresh = null;
      _setConnectionStatus(HubConnection.reconnecting);

      await _deviceSubscription.cancel();
      await _connectionSubscription.cancel();
      await transport.dispose();
      api.options.baseUrl = value.restUrl;
      transport = createTransport(value);
      _listenToTransport();

      if (persist) {
        await store.write('snapshot', const HomeModel(HomeSnapshot()).toJson());
        await _clearTemperatureHistory();
        _snapshot = const HomeSnapshot();
        _deviceVersions.clear();
        _notifySnapshotChanged();
      }
      _settings = value;
    } finally {
      _isChangingConnection = false;
    }

    if (reconnect) {
      unawaited(_connectInBackground());
      unawaited(_refreshInBackground());
    }
  }
  //endregion

  /// ====================================================

  /// ================= MOTT and device commands ===================
  //region MQTT and device commands
  // MQTT and device commands

  // Open the MQTT connection.
  @override
  Future<void> connect() async {
    await transport.connect();
  }

  // Try a new MQTT connection while its status stream reports the result.
  Future<void> _connectInBackground() async {
    try {
      await connect();
    } catch (_) {
      // Connection status remains available through the transport stream.
    }
  }

  // Attach named handlers to device updates and connection changes.
  void _listenToTransport() {
    _deviceSubscription = transport.updates.listen(_onDeviceUpdate, onError: _onInvalidDeviceUpdate);
    _connectionSubscription = transport.connections.listen(_onConnectionChanged);
  }

  // Refresh after reconnecting or fail commands that lost their connection.
  void _onConnectionChanged(HubConnection status) {
    if (_isDisposed) return;
    if (status == HubConnection.connected) {
      _setConnectionStatus(HubConnection.reconnecting);
      unawaited(_refreshInBackground());
      return;
    }

    _setConnectionStatus(status);
    _failPendingCommands('Connection lost. Retry when connected.');
  }

  // Store the connection value before notifying listeners.
  void _setConnectionStatus(HubConnection status) {
    _connectionStatus = status;
    _connectionController.add(status);
  }

  // Keep confirmed values when the transport reports a malformed message.
  void _onInvalidDeviceUpdate(Object error) {
    if (_isDisposed || _isChangingConnection) return;
    _messageController.add('Invalid device update received. Last confirmed values are unchanged. Refresh to retry.');
  }

  // Validate a live reply, update confirmed data and complete its matching command.
  void _onDeviceUpdate(DeviceUpdate update) {
    if (_isDisposed || _isChangingConnection) return;
    final device = _findDevice(update.deviceId);
    if (device == null) return;
    if (!validState(device.type, update.state)) {
      _messageController.add(
        'Invalid update for ${device.name}. Last confirmed values are unchanged. Refresh to retry.',
      );
      return;
    }

    final timestamp = update.timestamp ?? DateTime.now().toUtc();
    if (timestamp.isBefore(device.lastUpdated)) return;
    if (device.type == DeviceType.sensor && update.state['temperature'] is num) {
      final temperature = (update.state['temperature'] as num).toDouble();
      _recordTemperature(device.id, timestamp, temperature);
    }

    _deviceVersions[device.id] = (_deviceVersions[device.id] ?? 0) + 1;
    final devices = <Device>[];
    for (final currentDevice in _snapshot.devices) {
      if (currentDevice.id == device.id) {
        devices.add(currentDevice.confirmed(update.state, timestamp));
      } else {
        devices.add(currentDevice);
      }
    }
    _snapshot = _snapshot.withDevices(devices);
    _notifySnapshotChanged();
    unawaited(_saveSnapshotInBackground());

    final command = _pendingCommands[device.id];
    if (command == null || command.commandId != update.commandId || command.confirmation.isCompleted) {
      return;
    }
    for (final field in command.targetState.entries) {
      if (update.state[field.key] != field.value) return;
    }
    command.confirmation.complete();
  }

  // Send one MQTT command and wait up to three seconds for its matching reply.
  @override
  Future<void> command(String id, Map<String, dynamic> state) async {
    final device = _findDevice(id);
    if (!connected) throw StateError('Hub offline. Reconnect and retry.');
    if (device == null || !device.controllable) {
      throw StateError('Device offline or read-only.');
    }
    if (_pendingCommands.containsKey(id)) {
      throw StateError('A command is already pending for this device.');
    }
    if (!validCommandTarget(device.type, state)) {
      throw const FormatException('Invalid command values.');
    }

    final command = _PendingCommand(
      commandId: 'phone-${DateTime.now().microsecondsSinceEpoch}',
      targetState: Map<String, dynamic>.from(state),
    );
    _pendingCommands[id] = command;

    // Listen for a reply before sending, because sending may fail immediately.
    final reply = command.confirmation.future.timeout(
      commandTimeout,
      onTimeout: () => throw TimeoutException('${device.name} did not respond. Retry.'),
    );
    try {
      transport.send(id, state, command.commandId);
    } catch (error, stack) {
      if (!command.confirmation.isCompleted) {
        command.confirmation.completeError(error, stack);
      }
    }
    try {
      await reply;
    } finally {
      if (_pendingCommands[id] == command) _pendingCommands.remove(id);
    }
  }

  // Release commands waiting for a reply when the connection or screen closes.
  void _failPendingCommands(String message) {
    for (final command in _pendingCommands.values) {
      if (!command.confirmation.isCompleted) {
        command.confirmation.completeError(StateError(message));
      }
    }
  }
  //endregion

  /// ==================================================

  // Cleanup

  // Stop listeners, pending replies, network clients and the local database.
  @override
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;
    _restRetryTimer?.cancel();
    await _deviceSubscription.cancel();
    await _connectionSubscription.cancel();
    _failPendingCommands('Dashboard closed.');
    await transport.dispose();
    await _lastHistorySave;
    await store.close();
    api.close();
    await _snapshotController.close();
    await _connectionController.close();
    await _messageController.close();
  }
}
