import 'package:smart_home_controller_by_infinite/ui/home_screen/bloc/home_cubit.dart';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_home_controller_by_infinite/domain/entities/home_snapshot.dart';
import 'package:smart_home_controller_by_infinite/domain/entities/schedule.dart';
import 'package:smart_home_controller_by_infinite/infrastructure/models/home_model.dart';
import 'package:smart_home_controller_by_infinite/infrastructure/models/schedule_model.dart';
import 'package:smart_home_controller_by_infinite/infrastructure/repository/home_repository_impl.dart';
import 'package:smart_home_controller_by_infinite/ui/schedules_screen/bloc/schedule_bloc.dart';
import 'package:smart_home_controller_by_infinite/ui/schedules_screen/bloc/schedule_events.dart';
import 'package:smart_home_controller_by_infinite/ui/schedules_screen/bloc/schedule_state.dart';
import 'package:smart_home_controller_by_infinite/ui/schedules_screen/presentation/schedules_screen.dart';

import 'helpers/home_fakes.dart';

void main() {
  late HomeRepositoryImpl repository;
  late HomeCubit statusCubit;
  late FakeTransport transport;
  late MemoryStore store;
  late FixtureAdapter adapter;
  late ScheduleBloc bloc;
  late Map<String, dynamic> fixture;

  Future<ScheduleState> dispatch(ScheduleEvent event, bool Function(ScheduleState) done) {
    final result = bloc.stream.firstWhere(done).timeout(const Duration(seconds: 3));
    bloc.add(event);
    return result;
  }

  Schedule definition({ScheduleTarget? target, bool enabled = false}) => Schedule(
    id: 'test-schedule',
    name: 'Test schedule',
    time: '07:00',
    days: ['mon', 'fri'],
    target: target ?? const ScheduleTarget(type: 'scene', id: 's1'),
    enabled: enabled,
  );

  setUp(() async {
    fixture = Map<String, dynamic>.from(jsonDecode(File('docs/db.json').readAsStringSync()) as Map);
    transport = FakeTransport();
    store = MemoryStore();
    adapter = FixtureAdapter(fixture);
    repository = HomeRepositoryImpl(api: Dio()..httpClientAdapter = adapter, transport: transport, store: store);
    await repository.loadCache();
    await repository.refresh();
    statusCubit = HomeCubit(repository);
    bloc = ScheduleBloc(repository: repository);
    await dispatch(RefreshSchedules(), (state) => !state.isLoading && state.restAvailable);
  });
  tearDown(() async {
    await bloc.close();
    await statusCubit.close();
    await repository.dispose();
  });

  test('schedule model rejects malformed times, duplicate days and empty device state', () {
    final valid = Map<String, dynamic>.from((fixture['schedules'] as List).first as Map);
    for (final patch in [
      {'time': '24:00'},
      {'time': '7:00'},
      {'days': []},
      {
        'days': ['mon', 'mon'],
      },
      {
        'days': ['monday'],
      },
      {
        'target': {'type': 'device', 'id': 'd1', 'state': {}},
      },
    ]) {
      expect(() => const ScheduleModel().fromJson({...valid, ...patch}), throwsFormatException);
    }
  });

  test('CRUD persists schedule configuration and cache without MQTT commands', () async {
    final schedule = definition(
      target: const ScheduleTarget(type: 'device', id: 'd2', state: {'level': 40}),
    );
    await repository.saveSchedule(schedule, isNew: true);
    await repository.saveSchedule(
      Schedule(
        id: schedule.id,
        name: 'Updated',
        target: schedule.target,
        time: '08:15',
        days: scheduleDays,
        enabled: true,
      ),
      isNew: false,
    );
    await repository.refresh();
    final restored = const HomeModel(HomeSnapshot()).fromJson(store.entries['snapshot']!);
    expect(restored.schedules.last.time, '08:15');
    expect(restored.schedules.last.enabled, isTrue);
    expect(restored.schedules.last.target.state, {'level': 40});
    await repository.deleteSchedule(schedule.id);
    expect(repository.current.schedules.length, 3);
    expect(repository.current.devices.length, 18);
    expect(repository.current.scenes.length, 4);
    expect(transport.sent, isEmpty);
  });

  testWidgets('empty editor validates required fields and confirms discard', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider.value(value: statusCubit),
          BlocProvider.value(value: bloc),
        ],
        child: const MaterialApp(home: SchedulesScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create schedule'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save schedule'));
    await tester.tap(find.text('Save schedule'));
    await tester.runAsync(() async {
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();
    expect(find.text('Enter a schedule name.'), findsOneWidget);
    expect(find.text('Choose at least one repeat day.'), findsOneWidget);
    expect(find.text('Choose an available target.'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).first, 'Unsaved');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsOneWidget);
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(transport.sent, isEmpty);
    await tester.runAsync(() async {
      await bloc.close();
    });
  });
}
