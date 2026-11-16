import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_home_controller_by_infinite/domain/entities/app_settings.dart';
import 'package:smart_home_controller_by_infinite/domain/repository/home_repository.dart';
import 'package:smart_home_controller_by_infinite/domain/transport/device_transport.dart';
import 'package:smart_home_controller_by_infinite/infrastructure/repository/home_repository_impl.dart';
import 'package:smart_home_controller_by_infinite/ui/common/temperature_scope.dart';
import 'package:smart_home_controller_by_infinite/ui/history_screen/presentation/history_screen.dart';
import 'package:smart_home_controller_by_infinite/ui/history_screen/widgets/temperature_chart.dart';
import 'package:smart_home_controller_by_infinite/ui/home_screen/bloc/home_cubit.dart';
import 'helpers/home_fakes.dart';

void main() {
  late HomeRepositoryImpl repository;
  late FakeTransport transport;
  late MemoryStore store;
  late FixtureAdapter adapter;
  final start = DateTime.utc(2030);
  setUp(() async {
    transport = FakeTransport();
    store = MemoryStore();
    adapter = FixtureAdapter(Map<String, dynamic>.from(jsonDecode(File('docs/db.json').readAsStringSync()) as Map));
    repository = HomeRepositoryImpl(
      api: Dio()..httpClientAdapter = adapter,
      transport: transport,
      store: store,
      transportFactory: (_) => FakeTransport(),
    );
    await repository.loadCache();
    await repository.refresh();
  });
  tearDown(() => repository.dispose());

  test('history contains only received valid readings and keeps latest 360', () async {
    expect(repository.temperatureHistory('d8'), isEmpty);
    for (var i = 0; i < 400; i++) {
      transport.incoming.add(
        DeviceUpdate('d8', {'temperature': 20 + i / 100}, timestamp: start.add(Duration(seconds: i * 10))),
      );
    }
    await Future<void>.delayed(Duration.zero);
    final history = repository.temperatureHistory('d8');
    expect(history, hasLength(360));
    expect(history.first.celsius, 20.4);
    expect(history.last.celsius, closeTo(23.99, .000001));
    transport.incoming.add(DeviceUpdate('d8', {'temperature': 999}, timestamp: start.add(const Duration(hours: 2))));
    transport.incoming.add(DeviceUpdate('d8', {'temperature': 22}, timestamp: start));
    transport.incoming.add(DeviceUpdate('d8', {'humidity': 60}, timestamp: start.add(const Duration(hours: 2))));
    await Future<void>.delayed(Duration.zero);
    expect(repository.temperatureHistory('d8'), history);
  });

  test('history persists independently of network and clears with downloaded cache', () async {
    transport.incoming.add(DeviceUpdate('d8', {'temperature': 25}, timestamp: start));
    await Future<void>.delayed(Duration.zero);
    await repository.dispose();
    final restored = HomeRepositoryImpl(
      api: Dio()..httpClientAdapter = adapter,
      transport: FakeTransport(),
      store: store,
    );
    await restored.loadCache();
    expect(restored.temperatureHistory('d8').single.celsius, 25);
    expect(restored.connected, isFalse);
    await restored.clearCache();
    expect(restored.temperatureHistory('d8'), isEmpty);
    expect(store.entries['temperatureHistory'], isEmpty);
    await restored.dispose();
  });

  testWidgets('chart handles empty, single, gap, offline and Fahrenheit without overflow', (tester) async {
    final home = HomeCubit(repository);
    Widget screen(TemperatureUnit unit) => RepositoryProvider<HomeRepository>.value(
      value: repository,
      child: BlocProvider.value(
        value: home,
        child: MaterialApp(
          home: TemperatureScope(
            unit: unit,
            child: const HistoryScreen(deviceId: 'd8'),
          ),
        ),
      ),
    );
    await tester.binding.setSurfaceSize(const Size(360, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(screen(TemperatureUnit.celsius));
    expect(find.textContaining('No temperature readings yet'), findsOneWidget);
    await tester.runAsync(() async {
      transport.incoming.add(DeviceUpdate('d8', {'temperature': 25}, timestamp: start));
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();
    expect(find.byType(TemperatureChart), findsOneWidget);
    expect(tester.widget<TemperatureChart>(find.byType(TemperatureChart)).readings, hasLength(1));
    await tester.runAsync(() async {
      transport.incoming.add(DeviceUpdate('d8', {'temperature': 26}, timestamp: start.add(const Duration(minutes: 3))));
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();
    await tester.pumpWidget(screen(TemperatureUnit.fahrenheit));
    expect(find.text('Temperature (°F)'), findsOneWidget);
    expect(find.text('Latest: 78.8 \u00b0F'), findsOneWidget);
    expect(tester.widget<TemperatureChart>(find.byType(TemperatureChart)).readings, hasLength(2));
    expect(repository.temperatureHistory('d8').last.celsius, 26);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(home.close);
  });
}
