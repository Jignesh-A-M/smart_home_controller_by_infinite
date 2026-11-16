import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:smart_home_controller_by_infinite/domain/entities/app_settings.dart';
import 'package:smart_home_controller_by_infinite/domain/entities/home_snapshot.dart';
import 'package:smart_home_controller_by_infinite/domain/transport/device_transport.dart';

class MqttDeviceTransport implements DeviceTransport {
  MqttDeviceTransport({this.settings = const AppSettings(), MqttServerClient Function(String, String)? clientFactory})
    : _clientFactory = clientFactory ?? MqttServerClient.new;

  final AppSettings settings;
  final MqttServerClient Function(String, String) _clientFactory;
  final _updates = StreamController<DeviceUpdate>.broadcast();
  final _connections = StreamController<HubConnection>.broadcast();
  MqttServerClient? _client;
  StreamSubscription<dynamic>? _subscription;
  Timer? _retry;
  bool _disposed = false, _connecting = false;
  bool _ready = false;
  int _attempt = 0;
  Object? _activeAttempt;

  @override
  Stream<DeviceUpdate> get updates => _updates.stream;

  @override
  Stream<HubConnection> get connections => _connections.stream;

  @override
  bool get connected => _ready && _client?.connectionStatus?.state == MqttConnectionState.connected;

  // Recreate one MQTT client per attempt and use bounded exponential backoff.
  @override
  Future<void> connect() {
    if (_disposed || connected || _connecting) return Future.value();
    final attempt = Object();
    _activeAttempt = attempt;
    // Handle late socket cleanup errors only inside this MQTT connection.
    return runZoned(
      _connect,
      zoneSpecification: ZoneSpecification(
        handleUncaughtError: (self, parent, zone, error, stack) {
          if (error is SocketException) {
            if (!_disposed && identical(_activeAttempt, attempt)) {
              _scheduleRetry();
            }
          } else {
            parent.handleUncaughtError(zone, error, stack);
          }
        },
      ),
    );
  }

  // Connect and subscribe before enabling device commands.
  Future<void> _connect() async {
    if (_disposed || connected || _connecting) return;
    _connecting = true;
    _ready = false;
    _retry?.cancel();
    _connections.add(HubConnection.reconnecting);
    await _subscription?.cancel();
    _client?.onDisconnected = null;
    _client?.disconnect();
    final client = _clientFactory(settings.mqttHost, 'ia-phone-${DateTime.now().microsecondsSinceEpoch}');
    _client = client;
    client.port = settings.mqttPort;
    client.keepAlivePeriod = 20;
    client.disconnectOnNoResponsePeriod = 30;
    client.connectTimeoutPeriod = 8000;
    client.logging(on: false);
    client.onDisconnected = () {
      if (!_disposed && !_connecting) _scheduleRetry();
    };
    try {
      await client.connect();
      if (_disposed) {
        client.disconnect();
        return;
      }
      if (client.connectionStatus?.state != MqttConnectionState.connected) {
        throw StateError('MQTT connection failed');
      }
      final subscribed = Completer<void>();
      client.onSubscribed = (_) {
        if (!subscribed.isCompleted) subscribed.complete();
      };
      client.onSubscribeFail = (_) {
        if (!subscribed.isCompleted) {
          subscribed.completeError(StateError('State subscription failed'));
        }
      };
      _subscription = client.updates!.listen((messages) {
        for (final message in messages) {
          try {
            final packet = message.payload as MqttPublishMessage;
            if (packet.header?.retain == true) continue;
            final decoded = jsonDecode(MqttPublishPayload.bytesToStringAsString(packet.payload.message));
            if (decoded is! Map) throw const FormatException('Expected a device state object.');
            final map = Map<String, dynamic>.from(decoded);
            if (map.containsKey('state') && map['state'] is! Map) {
              throw const FormatException('Expected a device state object.');
            }
            final state = map['state'] is Map ? Map<String, dynamic>.from(map['state'] as Map) : map;
            if (state.isEmpty) throw const FormatException('Empty device state.');
            final commandId = map['commandId'];
            final rawTime = map['lastUpdated'];
            if (commandId != null && commandId is! String ||
                rawTime != null && (rawTime is! String || DateTime.tryParse(rawTime) == null)) {
              throw const FormatException('Invalid device update metadata.');
            }
            _updates.add(
              DeviceUpdate(
                message.topic.split('/').reversed.elementAt(1),
                state,
                commandId: commandId as String?,
                timestamp: rawTime == null ? null : DateTime.parse(rawTime as String),
              ),
            );
          } catch (_) {
            _updates.addError(const FormatException('Invalid or empty device update.'));
          }
        }
      });
      client.subscribe('${settings.topicPrefix}/device/+/state', MqttQos.atLeastOnce);
      await subscribed.future.timeout(const Duration(seconds: 5));
      if (_disposed) {
        client.disconnect();
        return;
      }
      _ready = true;
      _attempt = 0;
      _connections.add(HubConnection.connected);
    } catch (_) {
      if (!_disposed) _scheduleRetry();
    } finally {
      _connecting = false;
    }
  }

  void _scheduleRetry() {
    if (_disposed) return;
    _ready = false;
    _connections.add(HubConnection.offline);
    _retry?.cancel();
    _retry = Timer(Duration(seconds: min(30, 1 << min(_attempt++, 5))), connect);
  }

  @override
  void send(String deviceId, Map<String, dynamic> state, String commandId) {
    if (!connected) throw StateError('Hub is offline. Reconnect and retry.');
    final payload = MqttClientPayloadBuilder()..addString(jsonEncode({'commandId': commandId, 'state': state}));
    _client!.publishMessage(
      '${settings.topicPrefix}/device/$deviceId/set',
      MqttQos.atMostOnce,
      payload.payload!,
      retain: false,
    );
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    _retry?.cancel();
    await _subscription?.cancel();
    _client?.onDisconnected = null;
    _client?.disconnect();
    await _updates.close();
    await _connections.close();
  }
}
