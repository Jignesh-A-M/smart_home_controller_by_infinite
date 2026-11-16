import 'package:equatable/equatable.dart';
import '../../../domain/entities/home_snapshot.dart';
import '../../../domain/entities/schedule.dart';

abstract class ScheduleEvent extends Equatable {
  const ScheduleEvent();
  @override
  List<Object?> get props => [];
}

class RefreshSchedules extends ScheduleEvent {}

class SuccessFetchSchedules extends ScheduleEvent {
  const SuccessFetchSchedules(this.snapshot);
  final HomeSnapshot snapshot;
  @override
  List<Object?> get props => [snapshot];
}

class OpenScheduleEditor extends ScheduleEvent {
  const OpenScheduleEditor([this.schedule]);
  final Schedule? schedule;
  @override
  List<Object?> get props => [schedule];
}

class ChangeScheduleDraft extends ScheduleEvent {
  const ChangeScheduleDraft({
    this.name,
    this.time,
    this.days,
    this.target,
    this.enabled,
  });
  final String? name, time;
  final List<String>? days;
  final ScheduleTarget? target;
  final bool? enabled;
  @override
  List<Object?> get props => [name, time, days, target, enabled];
}

class SaveSchedule extends ScheduleEvent {}

class DeleteSchedule extends ScheduleEvent {
  const DeleteSchedule(this.schedule);
  final Schedule schedule;
  @override
  List<Object?> get props => [schedule];
}

class ToggleSchedule extends ScheduleEvent {
  const ToggleSchedule(this.schedule, this.enabled);
  final Schedule schedule;
  final bool enabled;
  @override
  List<Object?> get props => [schedule, enabled];
}

class ScheduleRestChanged extends ScheduleEvent {
  const ScheduleRestChanged(this.available);
  final bool available;
  @override
  List<Object?> get props => [available];
}
