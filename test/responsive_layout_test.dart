import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_home_controller_by_infinite/app/app.dart';
import 'package:smart_home_controller_by_infinite/infrastructure/repository/home_repository_impl.dart';
import 'package:smart_home_controller_by_infinite/ui/home_screen/widgets/device_card.dart';
import 'package:smart_home_controller_by_infinite/infrastructure/models/home_model.dart';
import 'package:smart_home_controller_by_infinite/domain/entities/home_snapshot.dart';
import 'helpers/home_fakes.dart';
import 'helpers/quick_tile_fake.dart';

void main() {
  Map<String, dynamic> fixture() =>
      Map<String, dynamic>.from(jsonDecode(File('docs/db.json').readAsStringSync()) as Map);

  testWidgets('wall panel navigation and phone resize preserve dashboard search', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = HomeRepositoryImpl(
      api: Dio()..httpClientAdapter = FixtureAdapter(fixture()),
      transport: FakeTransport(),
      store: MemoryStore(),
    );
    final gateway = FakeQuickTileGateway();
    await tester.pumpWidget(InfiniteHomeApp(repository: repository, quickTileGateway: gateway));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    await tester.enterText(find.byType(TextField).first, 'Office');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('Office Blinds'), findsOneWidget);
    for (final tab in ['Scenes', 'Schedules', 'Settings', 'Home']) {
      await tester.tap(find.text(tab));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(tester.takeException(), isNull);
    }
    expect(tester.widget<TextField>(find.byType(TextField).first).controller!.text, 'Office');
    tester.view.physicalSize = const Size(360, 780);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    expect(tester.widget<TextField>(find.byType(TextField).first).controller!.text, 'Office');
    expect(tester.takeException(), isNull);
    await tester.enterText(find.byType(TextField).first, 'Kitchen Temperature');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Temperature history'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Temperature history'));
    await tester.pumpAndSettle();
    expect(find.text('Temperature history'), findsOneWidget);
    gateway.tap('', 'from-history');
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Scenes'), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Temperature history'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(repository.dispose);
  });

  testWidgets('large text and reduced motion keep thermostat controls readable', (tester) async {
    tester.view.physicalSize = const Size(360, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final home = const HomeModel(HomeSnapshot()).fromJson(fixture());
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(360, 1000),
            disableAnimations: true,
            textScaler: TextScaler.linear(1.8),
          ),
          child: Scaffold(
            body: SingleChildScrollView(
              child: DeviceCard(
                device: home.devices.firstWhere((d) => d.id == 'd4'),
                roomName: 'Living Room',
                favourite: true,
                connected: true,
                pending: const {'setpoint': 22},
                onFavourite: () {},
                onControl: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(tester.widget<CircularProgressIndicator>(find.byType(CircularProgressIndicator)).value, .65);
    for (final animation in tester.widgetList<AnimatedSize>(find.byType(AnimatedSize))) {
      expect(animation.duration, Duration.zero);
    }
    expect(tester.takeException(), isNull);
  });
}
