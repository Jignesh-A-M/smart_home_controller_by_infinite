import 'package:flutter/widgets.dart';

import '../../domain/entities/app_settings.dart';

// Share display units with all routes without coupling device widgets to SettingsCubit.
class TemperatureScope extends InheritedWidget {
  const TemperatureScope({super.key, required this.unit, required super.child});

  final TemperatureUnit unit;

  static TemperatureUnit of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TemperatureScope>()?.unit ?? TemperatureUnit.celsius;

  @override
  bool updateShouldNotify(TemperatureScope oldWidget) => unit != oldWidget.unit;
}
