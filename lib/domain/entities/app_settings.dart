import 'package:equatable/equatable.dart';

enum TemperatureUnit { celsius, fahrenheit }

class AppSettings extends Equatable {
  const AppSettings({
    this.restUrl = const String.fromEnvironment('HUB_URL', defaultValue: 'http://127.0.0.1:3000'),
    this.mqttHost = 'broker.hivemq.com',
    this.mqttPort = 1883,
    this.topicPrefix = const String.fromEnvironment('MQTT_PREFIX', defaultValue: 'ia/jignesh-08dev808'),
    this.darkMode = false,
    this.quickSceneId = '',
    this.temperatureUnit = TemperatureUnit.celsius,
  });
  final String restUrl, mqttHost, topicPrefix;
  final int mqttPort;
  final String quickSceneId;
  final bool darkMode;
  final TemperatureUnit temperatureUnit;

  // Change selected preferences while preserving the remaining configuration.
  AppSettings copyWith({
    String? restUrl,
    String? mqttHost,
    int? mqttPort,
    String? topicPrefix,
    bool? darkMode,
    String? quickSceneId,
    TemperatureUnit? temperatureUnit,
  }) => AppSettings(
    restUrl: restUrl ?? this.restUrl,
    mqttHost: mqttHost ?? this.mqttHost,
    mqttPort: mqttPort ?? this.mqttPort,
    topicPrefix: topicPrefix ?? this.topicPrefix,
    darkMode: darkMode ?? this.darkMode,
    quickSceneId: quickSceneId ?? this.quickSceneId,
    temperatureUnit: temperatureUnit ?? this.temperatureUnit,
  );

  bool sameConnection(AppSettings other) =>
      restUrl == other.restUrl &&
      mqttHost == other.mqttHost &&
      mqttPort == other.mqttPort &&
      topicPrefix == other.topicPrefix;

  @override
  List<Object?> get props => [restUrl, mqttHost, mqttPort, topicPrefix, darkMode, quickSceneId, temperatureUnit];
}

// Convert for display and input while keeping every stored command in Celsius.
double displayTemperature(num celsius, TemperatureUnit unit) =>
    unit == TemperatureUnit.fahrenheit ? celsius * 9 / 5 + 32 : celsius.toDouble();
double canonicalTemperature(num value, TemperatureUnit unit) =>
    unit == TemperatureUnit.fahrenheit ? (value - 32) * 5 / 9 : value.toDouble();
String formatTemperature(num celsius, TemperatureUnit unit) =>
    '${displayTemperature(celsius, unit).toStringAsFixed(1)} °${unit == TemperatureUnit.fahrenheit ? 'F' : 'C'}';
