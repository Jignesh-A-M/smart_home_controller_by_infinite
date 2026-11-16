import 'dart:async';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

class SocketErrorClient extends MqttServerClient {
  SocketErrorClient(super.server, super.clientIdentifier);
  late Zone socketZone;
  final status = MqttClientConnectionStatus();
  final messages = StreamController<List<MqttReceivedMessage<MqttMessage>>>.broadcast();

  @override
  MqttClientConnectionStatus get connectionStatus => status;
  @override
  Stream<List<MqttReceivedMessage<MqttMessage>>> get updates => messages.stream;

  // Remember the socket's zone to reproduce an asynchronous cleanup failure.
  @override
  Future<MqttClientConnectionStatus?> connect([String? username, String? password]) async {
    socketZone = Zone.current;
    status.state = MqttConnectionState.connected;
    return status;
  }

  @override
  Subscription? subscribe(String topic, MqttQos qosLevel) {
    scheduleMicrotask(() => onSubscribed?.call(topic));
    return null;
  }

  // Model an ignored Socket.close future after the original connect has completed.
  void failLater(Object error) => socketZone.run(() {
    unawaited(Future<void>.error(error));
  });

  @override
  void disconnect() {
    status.state = MqttConnectionState.disconnected;
  }
}
