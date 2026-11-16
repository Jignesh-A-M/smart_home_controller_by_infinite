import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_home_controller_by_infinite/domain/entities/home_snapshot.dart';
import 'package:smart_home_controller_by_infinite/infrastructure/models/home_model.dart';
import 'package:smart_home_controller_by_infinite/ui/home_screen/widgets/device_card.dart';

void main() {
  group('Pending Control', () {
    final home = const HomeModel(
      HomeSnapshot(),
    ).fromJson(Map<String, dynamic>.from(jsonDecode(File('docs/db.json').readAsStringSync()) as Map));
    Widget card(String id, Map<String, dynamic>? pending) => MaterialApp(
      home: Scaffold(
        body: DeviceCard(
          device: home.devices.firstWhere((device) => device.id == id),
          roomName: 'Living Room',
          favourite: false,
          connected: true,
          pending: pending,
          onFavourite: () {},
          onControl: (_) {},
        ),
      ),
    );

    testWidgets('power progress appears beside switch and clears after pending ends', (tester) async {
      await tester.pumpWidget(card('d1', {'on': false}));
      final progress = find.byKey(const ValueKey('pending-d1-on'));
      final toggle = find.byType(Switch);
      expect(progress, findsOneWidget);
      expect(tester.widget<Switch>(toggle).value, isFalse);
      expect(tester.widget<Switch>(toggle).onChanged, isNull);
      expect((tester.getCenter(progress).dy - tester.getCenter(toggle).dy).abs(), lessThan(2));
      await tester.pumpWidget(card('d1', null));
      await tester.pump(const Duration(milliseconds: 200));
      expect(progress, findsNothing);
      expect(tester.widget<Switch>(toggle).value, isTrue);
      expect(tester.widget<Switch>(toggle).onChanged, isNotNull);
    });

    testWidgets('brightness progress stays beside slider without marking power pending', (tester) async {
      await tester.pumpWidget(card('d2', {'level': 80}));
      expect(find.byKey(const ValueKey('pending-d2-level')), findsOneWidget);
      expect(find.byKey(const ValueKey('pending-d2-on')), findsNothing);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
      expect(tester.widget<Slider>(find.byType(Slider)).value, 80);
      expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNull);
      await tester.pumpWidget(card('d2', null));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.widget<Slider>(find.byType(Slider)).value, 60);
      expect(tester.takeException(), isNull);
    });

    testWidgets('blind progress appears at its position slider', (tester) async {
      await tester.pumpWidget(card('d3', {'position': 50}));
      expect(find.byKey(const ValueKey('pending-d3-position')), findsOneWidget);
      expect(tester.widget<Slider>(find.byType(Slider)).value, 50);
      expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNull);
    });

    testWidgets('thermostat target progress preserves power, current reading and mode', (tester) async {
      await tester.pumpWidget(card('d4', {'setpoint': 20}));
      expect(find.byKey(const ValueKey('pending-d4-setpoint')), findsOneWidget);
      expect(find.byKey(const ValueKey('pending-d4-on')), findsNothing);
      expect(find.byKey(const ValueKey('pending-d4-mode')), findsNothing);
      expect(
        tester.widget<Switch>(find.byType(Switch)).value,
        home.devices.firstWhere((d) => d.id == 'd4').state['on'],
      );
      expect(find.byType(DropdownButton<String>), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(card('d4', null));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });

  group('Slider preview', () {
    testWidgets('drag previews locally and sends exactly one command on release', (tester) async {
      final snapshot = const HomeModel(
        HomeSnapshot(),
      ).fromJson(Map<String, dynamic>.from(jsonDecode(File('docs/db.json').readAsStringSync()) as Map));
      final device = snapshot.devices.firstWhere((device) => device.id == 'd2');
      final commands = <Map<String, dynamic>>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DeviceCard(
              device: device,
              roomName: 'Living Room',
              favourite: false,
              connected: true,
              onFavourite: () {},
              onControl: commands.add,
            ),
          ),
        ),
      );
      final slider = find.byType(Slider);
      final gesture = await tester.startGesture(tester.getCenter(slider));
      await gesture.moveBy(const Offset(100, 0));
      await tester.pump();
      expect(commands, isEmpty);
      expect(tester.widget<Slider>(slider).value, isNot(device.state['level']));
      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(commands, hasLength(1));
      expect(commands.single['level'], inInclusiveRange(0, 100));
      expect(tester.widget<Slider>(slider).value, device.state['level']);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    });
  });
}
