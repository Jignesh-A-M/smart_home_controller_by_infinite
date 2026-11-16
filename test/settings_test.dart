import 'package:smart_home_controller_by_infinite/ui/home_screen/bloc/home_cubit.dart';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_home_controller_by_infinite/domain/entities/app_settings.dart';
import 'package:smart_home_controller_by_infinite/domain/entities/home_snapshot.dart';
import 'package:smart_home_controller_by_infinite/infrastructure/repository/home_repository_impl.dart';
import 'package:smart_home_controller_by_infinite/ui/common/temperature_scope.dart';
import 'package:smart_home_controller_by_infinite/ui/home_screen/widgets/device_card.dart';
import 'package:smart_home_controller_by_infinite/ui/settings_screen/bloc/settings_cubit.dart';

import 'helpers/home_fakes.dart';

class SettingsStore extends MemoryStore {
  String? failKey;

  @override
  Future<void> write(String key, Map<String, dynamic> value) async {
    if (key == failKey) throw StateError('Disk full. Retry.');
    await super.write(key, value);
  }
}

void main() {
  late HomeRepositoryImpl repository;
  late HomeCubit statusCubit;
  late FakeTransport original;
  late SettingsStore store;
  late FixtureAdapter adapter;
  late SettingsCubit cubit;
  late List<FakeTransport> replacements;
  late List<AppSettings> installed;

  setUp(() async {
    original = FakeTransport();
    store = SettingsStore();
    replacements = [];
    installed = [];
    adapter = FixtureAdapter(Map<String, dynamic>.from(jsonDecode(File('docs/db.json').readAsStringSync()) as Map));
    repository = HomeRepositoryImpl(
      api: Dio()..httpClientAdapter = adapter,
      transport: original,
      store: store,
      commandTimeout: const Duration(milliseconds: 250),
      transportFactory: (settings) {
        installed.add(settings);
        final next = FakeTransport();
        replacements.add(next);
        return next;
      },
    );
    await repository.loadCache();
    await repository.refresh();
    statusCubit = HomeCubit(repository);
    cubit = SettingsCubit(repository: repository);
    await cubit.load();
  });
  tearDown(() async {
    await cubit.close();
    await statusCubit.close();
    await repository.dispose();
  });

  Future<void> connect() async {
    final ready = repository.connections.firstWhere((s) => s == HubConnection.connected);
    await repository.connect();
    await ready.timeout(const Duration(seconds: 2));
  }

  test('preferences restore without mutating confirmed devices or sending MQTT', () async {
    final before = jsonEncode(store.entries['snapshot']);
    await cubit.setDarkMode(true);
    await cubit.setTemperatureUnit(TemperatureUnit.fahrenheit);
    final restored = SettingsCubit(repository: repository);
    await restored.load();
    expect(restored.state.saved.darkMode, isTrue);
    expect(restored.state.saved.temperatureUnit, TemperatureUnit.fahrenheit);
    expect(jsonEncode(store.entries['snapshot']), before);
    expect(original.sent, isEmpty);
    expect(installed, isEmpty);
    await restored.close();
  });

  test('invalid URLs, broker ports and topic wildcards leave active settings intact', () async {
    for (final value in [
      const AppSettings(restUrl: 'file:///tmp/db'),
      const AppSettings(restUrl: 'http://user:pass@localhost:3000'),
      const AppSettings(mqttHost: 'mqtt://broker.hivemq.com'),
      const AppSettings(mqttPort: 0),
      const AppSettings(mqttPort: 65536),
      const AppSettings(topicPrefix: 'ia/+/test'),
      const AppSettings(topicPrefix: 'ia/<yourname>'),
      const AppSettings(topicPrefix: 'ia/with spaces'),
    ]) {
      await expectLater(repository.saveSettings(value), throwsFormatException);
    }
    expect(repository.settings, const AppSettings());
    expect(installed, isEmpty);
  });

  test('connection changes dispose old transport and install only new configuration', () async {
    await connect();
    final ready = repository.connections.firstWhere((s) => s == HubConnection.connected);
    await repository.saveSettings(
      const AppSettings(topicPrefix: 'ia/new-prefix', mqttHost: 'localhost', mqttPort: 1884),
    );
    await ready.timeout(const Duration(seconds: 2));
    expect(original.incoming.isClosed, isTrue);
    expect(installed.single.topicPrefix, 'ia/new-prefix');
    expect(installed.single.mqttPort, 1884);
    expect(repository.transport, same(replacements.single));
    expect(repository.settings.topicPrefix, 'ia/new-prefix');
    expect(original.sent, isEmpty);
  });

  test('clear cache preserves settings and favourite overrides; refresh restores hub data', () async {
    await repository.setFavourite('d1', false);
    await cubit.setDarkMode(true);
    await repository.clearCache();
    expect(repository.current.rooms, isEmpty);
    expect(repository.current.schedules, isEmpty);
    expect(store.entries['settings']!['darkMode'], isTrue);
    expect(repository.isFavourite('d1', true), isFalse);
    expect((adapter.fixture['devices'] as List).length, 18);
    await repository.refresh();
    expect(repository.current.rooms.length, 5);
    expect(repository.isFavourite('d1', true), isFalse);
  });

  testWidgets('Fahrenheit thermostat input produces Celsius command values', (tester) async {
    Map<String, dynamic>? command;
    final thermostat = repository.current.devices.firstWhere((d) => d.type == DeviceType.thermostat);
    await tester.pumpWidget(
      MaterialApp(
        home: TemperatureScope(
          unit: TemperatureUnit.fahrenheit,
          child: Scaffold(
            body: DeviceCard(
              device: thermostat,
              roomName: 'Living Room',
              favourite: false,
              connected: true,
              onFavourite: () {},
              onControl: (value) => command = value,
            ),
          ),
        ),
      ),
    );
    expect(find.textContaining('°F'), findsWidgets);
    await tester.tap(find.byTooltip('Increase target temperature'));
    expect(command!['setpoint'], closeTo(23 + 5 / 9, .00001));
    expect(thermostat.state['setpoint'], 23);
  });
}
