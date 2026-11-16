import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_home_controller_by_infinite/domain/entities/home_snapshot.dart';
import 'package:smart_home_controller_by_infinite/domain/transport/device_transport.dart';
import 'helpers/quick_tile_fake.dart';
import 'package:smart_home_controller_by_infinite/infrastructure/repository/home_repository_impl.dart';
import 'package:smart_home_controller_by_infinite/ui/home_screen/bloc/home_cubit.dart';
import 'package:smart_home_controller_by_infinite/ui/quick_tile/bloc/quick_tile_cubit.dart';
import 'package:smart_home_controller_by_infinite/ui/scenes_screen/bloc/scene_bloc.dart';
import 'package:smart_home_controller_by_infinite/ui/settings_screen/bloc/settings_cubit.dart';
import 'helpers/home_fakes.dart';

void main() {
  late HomeRepositoryImpl repository;
  late FakeTransport transport;
  late HomeCubit home;
  late SceneBloc scenes;
  late SettingsCubit settings;
  late FakeQuickTileGateway gateway;
  late QuickTileCubit quick;
  setUp(() async {
    transport = FakeTransport();
    repository = HomeRepositoryImpl(
      api: Dio()
        ..httpClientAdapter = FixtureAdapter(
          Map<String, dynamic>.from(jsonDecode(File('docs/db.json').readAsStringSync()) as Map),
        ),
      transport: transport,
      store: MemoryStore(),
      commandTimeout: const Duration(milliseconds: 50),
    );
    await repository.loadCache();
    await repository.refresh();
    home = HomeCubit(repository);
    scenes = SceneBloc(repository: repository);
    settings = SettingsCubit(repository: repository);
    await settings.load();
    gateway = FakeQuickTileGateway();
    quick = QuickTileCubit(
      repository: repository,
      gateway: gateway,
      home: home,
      scenes: scenes,
      settings: settings,
      connectionWait: const Duration(milliseconds: 25),
    );
    await quick.start();
  });
  tearDown(() async {
    await quick.close();
    await scenes.close();
    await settings.close();
    await home.close();
  });
  Future<void> connect() async {
    final ready = repository.connections.firstWhere((value) => value == HubConnection.connected);
    await repository.connect();
    await ready;
  }

  test('tile uses normal scene actions once and ignores a duplicate request token', () async {
    await connect();
    final scene = repository.current.scenes.first;
    await quick.select(scene);
    transport.onSend = (id, patch, commandId) => transport.incoming.add(DeviceUpdate(id, patch, commandId: commandId));
    final finished = scenes.stream.firstWhere((s) => s.runScene?.id == scene.id && !s.running && s.results.isNotEmpty);
    gateway.tap(scene.id, 'one');
    await finished;
    expect(transport.sent, hasLength(scene.actions.length));
    for (final sent in transport.sent) {
      expect(sent.state, scene.actions.firstWhere((action) => action.deviceId == sent.device).state);
    }
    gateway.tap(scene.id, 'one');
    await Future<void>.delayed(Duration.zero);
    expect(transport.sent, hasLength(scene.actions.length));
    expect(quick.state.openScenesVersion, 1);
  });

  test('offline tile times out and never replays after network recovery', () async {
    await quick.select(repository.current.scenes.first);
    final failed = home.stream.firstWhere((s) => s.feedback?.startsWith('Hub offline.') == true);
    gateway.tap('s1', 'offline');
    await failed;
    expect(transport.sent, isEmpty);
    await connect();
    await Future<void>.delayed(Duration.zero);
    expect(transport.sent, isEmpty);
  });

  test('removed favourite disables selection and cannot run an old tile request', () async {
    await connect();
    await quick.select(repository.current.scenes.first);
    await repository.setFavourite('s1', false, scene: true);
    await Future<void>.delayed(Duration.zero);
    expect(gateway.selections.last, '');
    final failed = home.stream.firstWhere((s) => s.feedback?.contains('no longer available') == true);
    gateway.tap('s1', 'removed');
    await failed;
    expect(transport.sent, isEmpty);
  });
}
