import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../domain/entities/app_settings.dart';
import '../../../domain/repository/home_repository.dart';
import '../../common/connection_status_banner.dart';
import '../../common/temperature_scope.dart';
import '../bloc/history_cubit.dart';
import '../widgets/temperature_chart.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key, required this.deviceId});
  final String deviceId;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (context) => HistoryCubit(context.read<HomeRepository>(), deviceId),
    child: BlocBuilder<HistoryCubit, HistoryState>(
      builder: (context, state) {
        final unit = TemperatureScope.of(context);
        final readings = state.readings;
        final device = state.device;
        return Scaffold(
          appBar: AppBar(title: const Text('Temperature history')),
          body: ConnectionStatusBody(
            child: SafeArea(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Text(device?.name ?? 'Sensor unavailable', style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  const Text('Last 360 received readings. Gaps show periods without sensor updates.'),
                  if (device?.online == false)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text('Sensor offline · saved history remains available.'),
                    ),
                  const SizedBox(height: 20),
                  if (readings.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('No temperature readings yet. New readings appear while this sensor is online.'),
                      ),
                    )
                  else ...[
                    Text(
                      'Temperature (${unit == TemperatureUnit.celsius ? '°C' : '°F'})',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Semantics(
                          label:
                              '${readings.length} recorded readings. Latest ${formatTemperature(readings.last.celsius, unit)} at ${readingTime(readings.last.timestamp)}.',
                          child: TemperatureChart(readings: readings, unit: unit),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 24,
                      runSpacing: 12,
                      children: [
                        Text('Latest: ${formatTemperature(readings.last.celsius, unit)}'),
                        Text(
                          'Lowest: ${formatTemperature(readings.map((r) => r.celsius).reduce((a, b) => a < b ? a : b), unit)}',
                        ),
                        Text(
                          'Highest: ${formatTemperature(readings.map((r) => r.celsius).reduce((a, b) => a > b ? a : b), unit)}',
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text('${readings.length} readings · last received ${readingTime(readings.last.timestamp)}'),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}
