import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:smart_home_controller_by_infinite/domain/entities/home_snapshot.dart';
import 'package:smart_home_controller_by_infinite/domain/transport/device_transport.dart';
import 'package:smart_home_controller_by_infinite/infrastructure/local/home_store.dart';

class MemoryStore implements HomeStore {
  final entries = <String, Map<String, dynamic>>{};
  @override
  Future<Map<String, dynamic>?> read(String key) async => entries[key];
  @override
  Future<void> write(String key, Map<String, dynamic> value) async {
    entries[key] = Map<String, dynamic>.from(jsonDecode(jsonEncode(value)) as Map);
  }

  @override
  Future<void> close() async {}
}

class FakeTransport implements DeviceTransport {
  final incoming = StreamController<DeviceUpdate>.broadcast();
  final status = StreamController<HubConnection>.broadcast();
  final sent = <({String device, Map<String, dynamic> state, String id})>[];
  bool online = false;
  void Function(String, Map<String, dynamic>, String)? onSend;
  @override
  bool get connected => online;
  @override
  Stream<DeviceUpdate> get updates => incoming.stream;
  @override
  Stream<HubConnection> get connections => status.stream;
  @override
  Future<void> connect() async {
    online = true;
    status.add(HubConnection.connected);
  }

  @override
  void send(String deviceId, Map<String, dynamic> state, String commandId) {
    sent.add((device: deviceId, state: state, id: commandId));
    onSend?.call(deviceId, state, commandId);
  }

  @override
  Future<void> dispose() async {
    await incoming.close();
    await status.close();
  }
}

class FixtureAdapter implements HttpClientAdapter {
  FixtureAdapter(this.fixture);
  final Map<String, dynamic> fixture;
  bool fail = false;
  Completer<void>? devicesGate;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (fail) {
      throw DioException(requestOptions: options, type: DioExceptionType.connectionError);
    }
    if (options.path == '/devices') await devicesGate?.future;
    final parts = options.path.substring(1).split('/');
    dynamic value = fixture[parts.first];
    if (['scenes', 'schedules'].contains(parts.first) && options.method != 'GET') {
      final scenes = fixture[parts.first] as List;
      if (options.method == 'POST') {
        value = Map<String, dynamic>.from(
          (options.data is String ? jsonDecode(options.data as String) : options.data) as Map,
        );
        scenes.add(value);
      } else {
        final index = scenes.indexWhere((scene) => scene['id'] == parts.last);
        if (options.method == 'PATCH') {
          value = {
            ...scenes[index] as Map,
            ...(options.data is String ? jsonDecode(options.data as String) : options.data) as Map,
          };
          scenes[index] = value;
        } else if (options.method == 'DELETE') {
          scenes.removeAt(index);
          value = {};
        }
      }
    }
    return ResponseBody.fromString(
      jsonEncode(value),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
