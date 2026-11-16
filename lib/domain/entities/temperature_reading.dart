import 'package:equatable/equatable.dart';

class TemperatureReading extends Equatable {
  const TemperatureReading(this.timestamp, this.celsius);
  final DateTime timestamp;
  final double celsius;

  @override
  List<Object?> get props => [timestamp, celsius];
}
