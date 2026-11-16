import '../entities/home_snapshot.dart';

class DeviceUpdate {
  const DeviceUpdate(this.deviceId, this.state, {this.commandId, this.timestamp});
  final String deviceId;
  final Map<String, dynamic> state;
  final String? commandId;
  final DateTime? timestamp;
}

// Hide MQTT details so another transport can implement the same contract.
abstract class DeviceTransport {
  // Report malformed updates through stream errors without replacing confirmed state.
  Stream<DeviceUpdate> get updates;
  Stream<HubConnection> get connections;
  bool get connected;
  Future<void> connect();
  void send(String deviceId, Map<String, dynamic> state, String commandId);
  Future<void> dispose();
}
