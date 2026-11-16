import '../../domain/entities/temperature_reading.dart';
import 'model.dart';

class TemperatureHistoryModel extends Model {
  const TemperatureHistoryModel([this.readings = const {}]);
  final Map<String, List<TemperatureReading>> readings;

  // Restore valid actual samples, discarding corrupt entries and duplicate timestamps.
  Map<String, List<TemperatureReading>> fromJson(Map<String, dynamic> json) {
    final result = <String, List<TemperatureReading>>{};
    for (final entry in json.entries) {
      if (entry.value is! List) continue;
      final samples = <DateTime, TemperatureReading>{};
      for (final raw in entry.value as List) {
        if (raw is! Map || raw['at'] is! String || raw['celsius'] is! num) continue;
        final time = DateTime.tryParse(raw['at'] as String);
        final value = (raw['celsius'] as num).toDouble();
        if (time == null || !value.isFinite || value < -100 || value > 100) continue;
        samples[time] = TemperatureReading(time, value);
      }
      final sorted = samples.values.toList()..sort((a, b) => a.timestamp.compareTo(b.timestamp));
      result[entry.key] = sorted.skip(sorted.length > 360 ? sorted.length - 360 : 0).toList();
    }
    return result;
  }

  @override
  Map<String, dynamic> toJson() => {
    for (final entry in readings.entries)
      entry.key: [
        for (final reading in entry.value) {'at': reading.timestamp.toIso8601String(), 'celsius': reading.celsius},
      ],
  };
}
