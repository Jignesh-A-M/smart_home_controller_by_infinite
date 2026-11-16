import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_home_controller_by_infinite/app/app.dart';
import 'package:smart_home_controller_by_infinite/domain/entities/home_snapshot.dart';
import 'package:smart_home_controller_by_infinite/domain/repository/home_repository.dart';
import 'package:smart_home_controller_by_infinite/domain/transport/device_transport.dart';
import 'package:smart_home_controller_by_infinite/infrastructure/models/home_model.dart';
import 'package:smart_home_controller_by_infinite/infrastructure/repository/home_repository_impl.dart';
import 'package:smart_home_controller_by_infinite/ui/common/connection_status_banner.dart';
import 'package:smart_home_controller_by_infinite/ui/home_screen/bloc/home_cubit.dart';
import 'package:smart_home_controller_by_infinite/ui/home_screen/bloc/home_state.dart';
import 'package:smart_home_controller_by_infinite/ui/home_screen/presentation/home_screen.dart';
import 'package:smart_home_controller_by_infinite/ui/home_screen/widgets/device_card.dart';
import 'helpers/home_fakes.dart';

void main() {
  group('Dashboard', () {
    late Map<String, dynamic> fixture;
    late FakeTransport transport;
    late MemoryStore store;
    late FixtureAdapter adapter;
    late HomeRepositoryImpl repository;

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
    });
    tearDown(() async {
      await repository.dispose();
    });

    Future<void> connect() async {
      // Wait for completed resync instead of depending on machine speed.
      final ready = repository.connections.firstWhere((state) => state == HubConnection.connected);
      await repository.connect();
      await ready.timeout(const Duration(seconds: 2));
    }

    test('fixture models preserve unknown devices and off dimmer brightness', () {
      expect(repository.current.rooms.length, 5);
      expect(repository.current.devices.length, 18);
      expect(repository.current.devices.firstWhere((d) => d.id == 'd18').type, DeviceType.unknown);
      final dimmer = repository.current.devices.firstWhere((d) => d.id == 'd9');
      expect(dimmer.state['on'], false);
      expect(dimmer.state['level'], 30);
    });

    test('offline favourite overrides survive refresh and repository restart', () async {
      await repository.setFavourite('d1', false);
      await repository.refresh();
      expect(repository.isFavourite('d1', true), false);
      final restored = HomeRepositoryImpl(
        api: Dio()..httpClientAdapter = FixtureAdapter(fixture),
        transport: FakeTransport(),
        store: store,
      );
      await restored.loadCache();
      expect(restored.current.devices.length, 18);
      expect(restored.isFavourite('d1', true), false);
      await restored.dispose();
    });

    test('a failed refresh preserves confirmed cached data', () async {
      adapter.fail = true;
      await expectLater(repository.refresh(), throwsA(isA<DioException>()));
      expect(repository.current.rooms.length, 5);
    });

    test('only the matching request confirms a pending command', () async {
      await connect();
      transport.onSend = (device, patch, id) {
        transport.incoming.add(DeviceUpdate(device, patch, commandId: 'old-request'));
        transport.incoming.add(DeviceUpdate(device, patch, commandId: id));
      };
      await repository.command('d1', {'on': false});
      expect(repository.current.devices.firstWhere((d) => d.id == 'd1').state['on'], false);
    });

    test('offline and unsupported devices cannot publish commands', () async {
      await connect();
      for (final id in ['d14', 'd18', 'd5']) {
        await expectLater(repository.command(id, {'on': true}), throwsA(isA<StateError>()));
      }
      expect(transport.sent, isEmpty);
    });

    test('older REST response cannot overwrite a live MQTT change', () async {
      adapter.devicesGate = Completer<void>();
      final refresh = repository.refresh();
      transport.incoming.add(const DeviceUpdate('d1', {'on': false}));
      await Future<void>.delayed(Duration.zero);
      adapter.devicesGate!.complete();
      await refresh;
      expect(repository.current.devices.firstWhere((d) => d.id == 'd1').state['on'], false);
    });

    test('device timeout shows plain feedback, rolls back and keeps retry working', () async {
      await connect();
      final cubit = HomeCubit(repository);
      await repository.refresh();
      final device = repository.current.devices.firstWhere((d) => d.id == 'd1');
      final result = cubit.control(device, {'on': false});
      expect(cubit.state.pending['d1']?['on'], isFalse);
      expect(await result, isFalse);
      expect(cubit.state.feedback, 'Ceiling Light did not respond. Retry.');
      expect(cubit.state.pending, isEmpty);
      expect(repository.current.devices.firstWhere((d) => d.id == 'd1').state['on'], isTrue);
      expect(cubit.state.retryActions.single.deviceId, 'd1');
      final cached = const HomeModel(HomeSnapshot()).fromJson(store.entries['snapshot']!);
      expect(cached.devices.firstWhere((d) => d.id == 'd1').state['on'], isTrue);
      transport.onSend = (id, patch, commandId) {
        transport.incoming.add(DeviceUpdate(id, patch, commandId: commandId));
      };
      await cubit.runActions(cubit.state.retryActions, 'Retry');
      expect(cubit.state.retryActions, isEmpty);
      expect(cubit.state.pending, isEmpty);
      expect(repository.current.devices.firstWhere((d) => d.id == 'd1').state['on'], isFalse);
      await cubit.close();
    });

    test('invalid updates offer refresh and preserve confirmed data and failed actions', () async {
      await connect();
      final cubit = HomeCubit(repository);
      await repository.refresh();
      await cubit.control(repository.current.devices.first, {'on': false});
      final before = repository.current;
      final message = cubit.stream.firstWhere((s) => s.feedbackAction == FeedbackAction.refresh);
      transport.incoming.addError(const FormatException('raw malformed JSON'));
      await message;
      expect(cubit.state.feedback, contains('Last confirmed values are unchanged'));
      expect(cubit.state.feedback, isNot(contains('FormatException')));
      expect(repository.current, same(before));
      expect(cubit.state.retryActions.single.deviceId, 'd1');
      final invalidState = cubit.stream.firstWhere((s) => s.feedback?.contains('Kitchen Temperature') == true);
      transport.incoming.add(const DeviceUpdate('d8', {'temperature': 'bad'}));
      await invalidState;
      expect(repository.current, same(before));
      expect(cubit.state.feedbackAction, FeedbackAction.refresh);
      await cubit.close();
    });

    testWidgets('dashboard search finds all office devices while offline', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final cubit = HomeCubit(repository);
      await tester.pumpWidget(
        BlocProvider.value(
          value: cubit,
          child: const MaterialApp(home: HomeScreen()),
        ),
      );
      await tester.runAsync(() => repository.refresh());
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'office');
      await tester.pump();
      expect(find.text('Search results (3)'), findsOneWidget);
      expect(find.text('Desk Light'), findsOneWidget);
      expect(find.text('Office Blinds'), findsOneWidget);
      expect(find.text('Office Temperature'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => cubit.close());
    });
  });

  testWidgets('room route shows only its devices and preserves dashboard favourites and scroll', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final transport = FakeTransport();
    final repository = HomeRepositoryImpl(
      api: Dio()
        ..httpClientAdapter = FixtureAdapter(
          Map<String, dynamic>.from(jsonDecode(File('docs/db.json').readAsStringSync()) as Map),
        ),
      transport: transport,
      store: MemoryStore(),
    );
    await tester.pumpWidget(InfiniteHomeApp(repository: repository));
    await tester.pumpAndSettle();
    final roomCard = find.byKey(const ValueKey('room-card-r1'));
    await tester.ensureVisible(roomCard);
    await tester.pumpAndSettle();
    final dashboardScroll = tester.state<ScrollableState>(
      find.descendant(of: find.byKey(const PageStorageKey('home-dashboard')), matching: find.byType(Scrollable)).first,
    );
    final offset = dashboardScroll.position.pixels;
    await tester.tap(roomCard);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Living Room'), findsOneWidget);
    expect(tester.widgetList<DeviceCard>(find.byType(DeviceCard)).map((card) => card.device.id), [
      'd1',
      'd2',
      'd3',
      'd4',
      'd5',
    ]);
    expect(find.text('Favourite scenes'), findsNothing);
    final light = find.byKey(const ValueKey('d1')).last;
    final toggle = find.descendant(of: light, matching: find.byType(Switch));
    await tester.tap(toggle);
    await tester.pump();
    expect(tester.widget<Switch>(toggle).value, isFalse);
    expect(find.byKey(const ValueKey('pending-d1-on')), findsOneWidget);
    final sent = transport.sent.single;
    transport.incoming.add(DeviceUpdate('d1', {'on': false}, commandId: sent.id));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pending-d1-on')), findsNothing);
    expect(tester.widget<Switch>(toggle).value, isFalse);
    await tester.tap(find.byTooltip('Favourite Feature Wall Dimmer'));
    await tester.pumpAndSettle();
    expect(repository.isFavourite('d2', false), isTrue);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Infinite Home'), findsOneWidget);
    expect(find.text('Favourite scenes'), findsOneWidget);
    expect(find.text('Favourite devices'), findsOneWidget);
    expect(dashboardScroll.position.pixels, offset);
    expect(tester.widgetList<DeviceCard>(find.byType(DeviceCard)).any((card) => card.device.id == 'd2'), isTrue);
    await tester.ensureVisible(roomCard);
    await tester.pumpAndSettle();
    await tester.tap(roomCard);
    await tester.pumpAndSettle();
    transport.online = false;
    transport.status.add(HubConnection.offline);
    await tester.pumpAndSettle();
    expect(find.text('Offline \u00b7 Showing saved data'), findsOneWidget);
    expect(
      tester
          .widget<Switch>(find.descendant(of: find.byKey(const ValueKey('d1')).last, matching: find.byType(Switch)))
          .onChanged,
      isNull,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(repository.dispose);
  });

  group('Connection banner placement', () {
    testWidgets('banner below app bar follows status across tabs and editor routes', (tester) async {
      final transport = FakeTransport();
      final repository = HomeRepositoryImpl(
        api: Dio()
          ..httpClientAdapter = FixtureAdapter(
            Map<String, dynamic>.from(jsonDecode(File('docs/db.json').readAsStringSync()) as Map),
          ),
        transport: transport,
        store: MemoryStore(),
      );
      addTearDown(repository.dispose);
      await tester.pumpWidget(InfiniteHomeApp(repository: repository));
      await tester.pumpAndSettle();
      final banner = find.byKey(const ValueKey('connection-status-banner'));
      expect(find.descendant(of: banner, matching: find.text('Connected')), findsOneWidget);
      expect(tester.getRect(banner).top, greaterThanOrEqualTo(tester.getRect(find.byType(AppBar)).bottom));
      expect(tester.getRect(banner).bottom, lessThan(tester.getRect(find.byType(NavigationBar)).top));
      for (final tab in ['Scenes', 'Schedules', 'Settings']) {
        await tester.tap(find.text(tab));
        await tester.pumpAndSettle();
        expect(banner, findsOneWidget);
        expect(tester.getRect(banner).top, greaterThanOrEqualTo(tester.getRect(find.byType(AppBar)).bottom));
        expect(find.descendant(of: banner, matching: find.text('Connected')), findsOneWidget);
      }
      await tester.tap(find.text('Scenes'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create scene'));
      await tester.pumpAndSettle();
      expect(find.text('Save scene'), findsOneWidget);
      expect(tester.getRect(banner).top, greaterThanOrEqualTo(tester.getRect(find.byType(AppBar)).bottom));
      expect(banner, findsOneWidget);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      transport.status.add(HubConnection.reconnecting);
      await tester.pump();
      await tester.pump();
      expect(find.text('Reconnecting to hub…'), findsOneWidget);
      transport.online = false;
      transport.status.add(HubConnection.offline);
      await tester.pump();
      await tester.pump();
      expect(find.text('Offline · Showing saved data'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(repository.dispose);
    });
  });

  group('Connection banner timing', () {
    Future<({HomeCubit cubit, BannerRepository repository})> mount(WidgetTester tester) async {
      final repository = BannerRepository();
      final cubit = HomeCubit(repository);
      addTearDown(cubit.close);
      await tester.pumpWidget(
        BlocProvider.value(
          value: cubit,
          child: const MaterialApp(
            home: Scaffold(body: ConnectionStatusBody(child: Text('Content'))),
          ),
        ),
      );
      return (cubit: cubit, repository: repository);
    }

    testWidgets('Connected hides at five seconds and duplicate status does not restart countdown', (tester) async {
      final (:cubit, :repository) = await mount(tester);
      repository.statuses.add(HubConnection.connected);
      await tester.pump();
      expect(find.text('Connected'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
      expect(find.text('Connected'), findsOneWidget);
      repository.statuses.add(HubConnection.connected);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byKey(const ValueKey('connection-status-banner')), findsNothing);
      expect(cubit.state.connection, HubConnection.connected);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(cubit.close);
    });
  });
}

class BannerRepository extends Fake implements HomeRepository {
  final statuses = StreamController<HubConnection>.broadcast(sync: true);
  final snapshots = StreamController<HomeSnapshot>.broadcast(sync: true);
  @override
  Stream<String> get messages => const Stream.empty();
  @override
  Stream<HubConnection> get connections => statuses.stream;
  @override
  Stream<HomeSnapshot> get changes => snapshots.stream;
  @override
  Future<void> dispose() async {
    await statuses.close();
    await snapshots.close();
  }
}
