import 'dart:async';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../domain/entities/home_snapshot.dart';
import '../../../domain/entities/temperature_reading.dart';
import '../../../domain/repository/home_repository.dart';

class HistoryState extends Equatable {
  const HistoryState(this.device, this.readings);
  final Device? device;
  final List<TemperatureReading> readings;
  @override
  List<Object?> get props => [device, readings];
}

class HistoryCubit extends Cubit<HistoryState> {
  HistoryCubit(this.repository, this.deviceId)
    : super(
        HistoryState(
          repository.current.devices.where((d) => d.id == deviceId).firstOrNull,
          repository.temperatureHistory(deviceId),
        ),
      ) {
    _subscription = repository.changes.listen((_) {
      if (!isClosed) {
        emit(
          HistoryState(
            repository.current.devices.where((d) => d.id == deviceId).firstOrNull,
            repository.temperatureHistory(deviceId),
          ),
        );
      }
    });
  }
  final HomeRepository repository;
  final String deviceId;
  late final StreamSubscription<HomeSnapshot> _subscription;

  // Release this screen's listener without closing the shared repository.
  @override
  Future<void> close() async {
    await _subscription.cancel();
    return super.close();
  }
}
