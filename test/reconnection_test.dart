import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:smart_home_controller_by_infinite/domain/entities/home_snapshot.dart';
import 'package:smart_home_controller_by_infinite/domain/transport/device_transport.dart';
import 'package:smart_home_controller_by_infinite/infrastructure/repository/home_repository_impl.dart';
import 'package:smart_home_controller_by_infinite/infrastructure/transport/mqtt_device_transport.dart';
import 'package:smart_home_controller_by_infinite/ui/home_screen/bloc/home_cubit.dart';
import 'helpers/home_fakes.dart';
import 'helpers/socket_error_client.dart';

void main() {
  group('Reconnection', () {
    late HomeRepositoryImpl repository;
    late FixtureAdapter adapter;
    late FakeTransport transport;
    late MemoryStore store;

    setUp(() {
      adapter = FixtureAdapter(Map<String, dynamic>.from(jsonDecode(File('docs/db.json').readAsStringSync()) as Map));
      transport = FakeTransport();
      store = MemoryStore();
      repository = HomeRepositoryImpl(api: Dio()..httpClientAdapter = adapter, transport: transport, store: store);
    });
    tearDown(() => repository.dispose());

    test('app started before REST recovers automatically without another MQTT connect event', () async {
      adapter.fail = true;
      final cubit = HomeCubit(repository);
      await cubit.start();
      expect(cubit.state.error, isNotNull);
      expect(transport.connected, isTrue);
      final recovered = cubit.stream.firstWhere(
        (state) => state.connection == HubConnection.connected && state.error == null,
      );
      adapter.fail = false;
      await recovered.timeout(const Duration(seconds: 4));
      expect(cubit.state.snapshot.rooms.length, 5);
      await cubit.close();
    });
  });

  group('MQTT socket recovery', () {
    test('late socket error stays inside MQTT and reconnects with a fresh client', () async {
      final escaped = <Object>[];
      final clients = <SocketErrorClient>[];
      final transport = MqttDeviceTransport(
        clientFactory: (host, id) {
          final client = SocketErrorClient(host, id);
          clients.add(client);
          return client;
        },
      );
      final states = <HubConnection>[];
      final subscription = transport.connections.listen(states.add);
      await runZonedGuarded(() => transport.connect(), (error, stack) => escaped.add(error))!;
      expect(transport.connected, isTrue);
      clients.single.failLater(const SocketException('connection abort'));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(escaped, isEmpty);
      expect(transport.connected, isFalse);
      expect(states.last, HubConnection.offline);
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      expect(clients.length, 2);
      expect(transport.connected, isTrue);
      await transport.dispose();
      await subscription.cancel();
    });
  });

  group('MQTT payload validation', () {
    test('malformed payloads report recoverable errors and valid state updates still work', () async {
      final client = SocketErrorClient('unused', 'test');
      final transport = MqttDeviceTransport(clientFactory: (_, _) => client);
      final updates = <DeviceUpdate>[];
      final errors = <Object>[];
      final subscription = transport.updates.listen(updates.add, onError: errors.add);
      await transport.connect();
      expect(transport.connected, isTrue);
      expect(client.messages.hasListener, isTrue);
      void receive(String text, {bool retained = false}) {
        final data = MqttClientPayloadBuilder()..addString(text);
        final packet = MqttPublishMessage().toTopic('ia/test/device/d1/state').publishData(data.payload!);
        packet.header!.retain = retained;
        client.messages.add([MqttReceivedMessage('ia/test/device/d1/state', packet)]);
      }

      final invalid = [
        '',
        '{',
        '[]',
        '{}',
        '{"state":{}}',
        '{"state":4}',
        '{"state":{"on":true},"lastUpdated":"invalid"}',
        '{"state":{"on":true},"commandId":2}',
      ];
      for (final text in invalid) {
        receive(text);
      }
      receive('{', retained: true);
      await Future<void>.delayed(Duration.zero);
      expect(errors, hasLength(invalid.length));
      expect(errors, everyElement(isA<FormatException>()));
      expect(updates, isEmpty);
      receive('{"on":true}');
      receive('{"state":{"on":false},"commandId":"valid-id","lastUpdated":"2030-01-01T00:00:00Z"}');
      await Future<void>.delayed(Duration.zero);
      expect(updates.map((update) => update.state['on']), [true, false]);
      expect(updates.last.commandId, 'valid-id');
      expect(updates.last.timestamp, DateTime.utc(2030));
      await subscription.cancel();
      await transport.dispose();
      await client.messages.close();
    });
  });
}
