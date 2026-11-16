import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_home_controller_by_infinite/domain/entities/home_snapshot.dart';
import 'package:smart_home_controller_by_infinite/domain/transport/device_transport.dart';
import 'package:smart_home_controller_by_infinite/infrastructure/repository/home_repository_impl.dart';
import 'package:smart_home_controller_by_infinite/ui/home_screen/bloc/home_cubit.dart';
import 'package:smart_home_controller_by_infinite/ui/scenes_screen/bloc/scene_bloc.dart';
import 'package:smart_home_controller_by_infinite/ui/scenes_screen/bloc/scene_events.dart';
import 'package:smart_home_controller_by_infinite/ui/scenes_screen/bloc/scene_state.dart';
import 'helpers/home_fakes.dart';

void main() {
  group('Scenes', () {
    late HomeRepositoryImpl repository;
    late HomeCubit statusCubit;
    late SceneBloc bloc;
    late FakeTransport transport;
    late MemoryStore store;
    late FixtureAdapter adapter;
    late Map<String, dynamic> fixture;

    Future<SceneState> dispatch(SceneEvent event, bool Function(SceneState) done) {
      final result = bloc.stream.firstWhere(done).timeout(const Duration(seconds: 3));
      bloc.add(event);
      return result;
    }

    setUp(() async {
      fixture = Map<String, dynamic>.from(jsonDecode(File('docs/db.json').readAsStringSync()) as Map);
      transport = FakeTransport();
      store = MemoryStore();
      adapter = FixtureAdapter(fixture);
      repository = HomeRepositoryImpl(
        api: Dio()..httpClientAdapter = adapter,
        transport: transport,
        store: store,
        commandTimeout: const Duration(milliseconds: 30),
      );
      await repository.loadCache();
      await repository.refresh();
      statusCubit = HomeCubit(repository);
      bloc = SceneBloc(repository: repository);
      await dispatch(ScenesRefreshRequested(), (s) => !s.refreshing && s.restAvailable);
    });
    tearDown(() async {
      await bloc.close();
      await statusCubit.close();
      await repository.dispose();
    });

    Scene definition({String id = 'test-scene', List<SceneAction>? actions}) => Scene(
      id: id,
      name: 'Test scene',
      icon: 'movie',
      favourite: false,
      actions:
          actions ??
          [
            const SceneAction('d1', {'on': false}),
          ],
    );

    Future<void> connect() async {
      final ready = bloc.stream.firstWhere((s) => s.connection == HubConnection.connected);
      await repository.connect();
      await ready.timeout(const Duration(seconds: 3));
    }

    test('scene CRUD round-trips partial targets without sending commands', () async {
      final scene = definition(
        actions: [
          const SceneAction('d2', {'level': 80}),
        ],
      );
      final saved = await repository.saveScene(scene, isNew: true);
      expect(saved.actions.single.state, {'level': 80});
      final changed = Scene(id: saved.id, name: 'Updated', icon: saved.icon, favourite: true, actions: saved.actions);
      await repository.saveScene(changed, isNew: false);
      await repository.refresh();
      expect(repository.current.scenes.last.name, 'Updated');
      expect((store.entries['snapshot']!['scenes'] as List).last['name'], 'Updated');
      await repository.deleteScene(scene.id);
      expect(repository.current.scenes.length, 4);
      expect(transport.sent, isEmpty);
    });

    test('invalid targets and read-only devices are rejected before saving', () async {
      for (final action in [
        const SceneAction('d2', {'level': 150}),
        const SceneAction('d5', {'motion': true}),
        const SceneAction('d18', {'on': true}),
        const SceneAction('d4', {'current': 22}),
      ]) {
        await expectLater(repository.saveScene(definition(actions: [action]), isNew: true), throwsFormatException);
      }
      expect(repository.current.scenes.length, 4);
      expect(transport.sent, isEmpty);
    });

    test('failed REST save preserves edited draft and confirmed cache', () async {
      await dispatch(const SceneEditorOpened(), (s) => s.draft != null);
      await dispatch(SceneDraftChanged(name: 'Keep my draft', actions: definition().actions), (s) => s.dirty);
      adapter.fail = true;
      await dispatch(SceneSaveRequested(), (s) => !s.saving && s.messageId > 0);
      expect(bloc.state.draft!.name, 'Keep my draft');
      expect(bloc.state.dirty, isTrue);
      expect(bloc.state.restAvailable, isFalse);
      expect(repository.current.scenes.length, 4);
      expect((store.entries['snapshot']!['scenes'] as List).length, 4);
      adapter.fail = false;
      await dispatch(ScenesRefreshRequested(), (s) => !s.refreshing && s.restAvailable);
      await dispatch(SceneSaveRequested(), (s) => s.savedVersion == 1);
      expect(repository.current.scenes.length, 5);
      expect(transport.sent, isEmpty);
    });

    test('scene partial failure retries only failed devices', () async {
      await connect();
      transport.onSend = (id, target, commandId) {
        if (id == 'd1') {
          transport.incoming.add(DeviceUpdate(id, target, commandId: commandId));
        }
      };
      final scene = definition(
        actions: [
          const SceneAction('d1', {'on': false}),
          const SceneAction('d13', {'on': false}),
        ],
      );
      await dispatch(SceneRunRequested(scene), (s) => !s.running && s.results.length == 2);
      expect(bloc.state.results, {'d1': SceneActionStatus.confirmed, 'd13': SceneActionStatus.failed});
      transport.onSend = (id, target, commandId) =>
          transport.incoming.add(DeviceUpdate(id, target, commandId: commandId));
      await dispatch(
        SceneRunRequested(scene, retry: true),
        (s) => !s.running && s.results.values.every((v) => v == SceneActionStatus.confirmed),
      );
      expect(transport.sent.map((s) => s.device).toList(), ['d1', 'd13', 'd13']);
      expect(repository.current.devices.firstWhere((d) => d.id == 'd1').state['on'], isFalse);
    });
  });
}
