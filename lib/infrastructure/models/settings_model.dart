import '../../domain/entities/app_settings.dart';
import 'model.dart';

class SettingsModel extends Model {
  const SettingsModel(this.settings);
  final AppSettings settings;

  // Reject invalid local settings before they can replace active connections.
  AppSettings fromJson(Map<String, dynamic> json) {
    if (json['restUrl'] is! String ||
        json['mqttHost'] is! String ||
        json['topicPrefix'] is! String ||
        json['mqttPort'] is! int ||
        json['darkMode'] is! bool ||
        !TemperatureUnit.values.any((unit) => unit.name == json['temperatureUnit'])) {
      throw const FormatException('Invalid saved preferences.');
    }
    if (json['quickSceneId'] != null && json['quickSceneId'] is! String) {
      throw const FormatException('Invalid quick-tile scene.');
    }
    final value = AppSettings(
      quickSceneId: json['quickSceneId'] as String? ?? '',
      restUrl: json['restUrl'] as String,
      mqttHost: json['mqttHost'] as String,
      topicPrefix: json['topicPrefix'] as String,
      mqttPort: json['mqttPort'] as int,
      darkMode: json['darkMode'] as bool,
      temperatureUnit: TemperatureUnit.values.firstWhere((unit) => unit.name == json['temperatureUnit']),
    );
    validate(value);
    return value;
  }

  // Validate the simple HTTP and MQTT TCP settings required by this assignment.
  static void validate(AppSettings value) {
    final uri = Uri.tryParse(value.restUrl);
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        (uri.hasPort && (uri.port < 1 || uri.port > 65535)) ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      throw const FormatException('Enter a REST server URL such as http://127.0.0.1:3000.');
    }
    if (!RegExp(r'^[a-zA-Z0-9.-]+$').hasMatch(value.mqttHost) || value.mqttPort < 1 || value.mqttPort > 65535) {
      throw const FormatException('Enter a broker hostname and port between 1 and 65535.');
    }
    if (value.topicPrefix.isEmpty ||
        value.topicPrefix.startsWith('/') ||
        value.topicPrefix.endsWith('/') ||
        value.topicPrefix.contains('//') ||
        RegExp(r'[+#<>\s]').hasMatch(value.topicPrefix)) {
      throw const FormatException('Use a unique topic prefix without spaces, placeholders, + or #.');
    }
  }

  @override
  Map<String, dynamic> toJson() => {
    'restUrl': settings.restUrl,
    'mqttHost': settings.mqttHost,
    'mqttPort': settings.mqttPort,
    'topicPrefix': settings.topicPrefix,
    'darkMode': settings.darkMode,
    'quickSceneId': settings.quickSceneId,
    'temperatureUnit': settings.temperatureUnit.name,
  };
}
