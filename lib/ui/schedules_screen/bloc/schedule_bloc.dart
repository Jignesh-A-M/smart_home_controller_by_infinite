import '../../common/feedback_message.dart';
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../domain/entities/home_snapshot.dart';
import '../../../domain/entities/schedule.dart';
import '../../../domain/repository/home_repository.dart';
import 'schedule_events.dart';
import 'schedule_state.dart';

class ScheduleBloc extends Bloc<ScheduleEvent, ScheduleState> {
  final HomeRepository repository;
  late final StreamSubscription<HomeSnapshot> homeStreamSubscription;
  late final StreamSubscription<HubConnection> hubStreamSubscription;

  bool get _busy => state.isSaving || state.busyId.isNotEmpty;

  ScheduleBloc({required this.repository})
    : super(ScheduleState(snapshot: repository.current, restAvailable: repository.restAvailable)) {
    on<SuccessFetchSchedules>(onSuccessFetchSchedules);
    on<RefreshSchedules>(onRefreshSchedules);
    on<ScheduleRestChanged>(onRestChanged);
    on<OpenScheduleEditor>(onOpenScheduleEditor);
    on<ChangeScheduleDraft>(onChangeScheduleDraft);
    on<SaveSchedule>(onSaveSchedule);
    on<DeleteSchedule>(onDeleteSchedule);
    on<ToggleSchedule>(onToggleSchedule);
    hubStreamSubscription = repository.connections.listen((_) {
      if (!isClosed) add(ScheduleRestChanged(repository.restAvailable));
    });
    homeStreamSubscription = repository.changes.listen((snapshot) {
      if (!isClosed) add(SuccessFetchSchedules(snapshot));
    });
  }

  // Share confirmed data with Dashboard and Scenes without resetting an open draft.
  void onSuccessFetchSchedules(SuccessFetchSchedules event, Emitter<ScheduleState> emit) =>
      emit(state.copyWith(snapshot: event.snapshot, restAvailable: repository.restAvailable));

  // Keep configuration controls in sync with automatic REST recovery.
  void onRestChanged(ScheduleRestChanged event, Emitter<ScheduleState> emit) =>
      emit(state.copyWith(restAvailable: event.available));

  // Refresh configuration through REST even when the public broker is disconnected.
  Future<void> onRefreshSchedules(RefreshSchedules event, Emitter<ScheduleState> emit) async {
    if (state.isLoading) return;
    emit(state.copyWith(isLoading: true));
    try {
      await repository.refresh();
      emit(state.copyWith(snapshot: repository.current, isLoading: false, restAvailable: true));
    } catch (error) {
      emit(
        state.copyWith(isLoading: false, restAvailable: false, message: _error(error), messageId: state.messageId + 1),
      );
    }
  }

  // Create an isolated draft with a stable ID so a retry cannot create duplicates.
  void onOpenScheduleEditor(OpenScheduleEditor event, Emitter<ScheduleState> emit) {
    if (_busy) return;
    final source = event.schedule;
    emit(
      state.copyWith(
        draft: Schedule(
          id: source?.id ?? 'schedule-${DateTime.now().microsecondsSinceEpoch}',
          name: source?.name ?? '',
          time: source?.time ?? '06:30',
          days: List.of(source?.days ?? []),
          enabled: source?.enabled ?? false,
          target: source == null
              ? const ScheduleTarget(type: 'scene', id: '')
              : ScheduleTarget(type: source.target.type, id: source.target.id, state: Map.of(source.target.state)),
        ),
        isNew: source == null,
        isDirty: false,
        showValidation: false,
      ),
    );
  }

  // Keep edits in memory until the user explicitly saves the schedule.
  void onChangeScheduleDraft(ChangeScheduleDraft event, Emitter<ScheduleState> emit) {
    final draft = state.draft;
    if (draft == null || _busy) return;
    emit(
      state.copyWith(
        draft: Schedule(
          id: draft.id,
          name: event.name ?? draft.name,
          time: event.time ?? draft.time,
          days: event.days ?? draft.days,
          target: event.target ?? draft.target,
          enabled: event.enabled ?? draft.enabled,
        ),
        isDirty: true,
      ),
    );
  }

  // Save the definition; timed execution remains the backend's responsibility.
  Future<void> onSaveSchedule(SaveSchedule event, Emitter<ScheduleState> emit) async {
    final draft = state.draft;
    if (draft == null || _busy || !state.restAvailable) return;
    if (draft.name.trim().isEmpty || draft.name.trim().length > 60 || draft.days.isEmpty || draft.target.id.isEmpty) {
      emit(state.copyWith(showValidation: true));
      return;
    }
    emit(state.copyWith(isSaving: true));
    try {
      await repository.saveSchedule(draft, isNew: state.isNew);
      emit(
        state.copyWith(
          snapshot: repository.current,
          isSaving: false,
          isDirty: false,
          savedVersion: state.savedVersion + 1,
          message: 'Schedule saved.',
          messageId: state.messageId + 1,
        ),
      );
    } catch (error) {
      emit(
        state.copyWith(
          isSaving: false,
          restAvailable: error is DioException ? false : state.restAvailable,
          message: _error(error),
          messageId: state.messageId + 1,
        ),
      );
    }
  }

  // Change enabled status only after REST confirms the new definition.
  Future<void> onToggleSchedule(ToggleSchedule event, Emitter<ScheduleState> emit) async {
    if (_busy || !state.restAvailable) return;
    final original = event.schedule;
    emit(state.copyWith(busyId: original.id));
    try {
      await repository.saveSchedule(
        Schedule(
          id: original.id,
          name: original.name,
          target: original.target,
          time: original.time,
          days: original.days,
          enabled: event.enabled,
        ),
        isNew: false,
      );
      emit(state.copyWith(snapshot: repository.current, busyId: ''));
    } catch (error) {
      emit(
        state.copyWith(
          busyId: '',
          restAvailable: error is DioException ? false : state.restAvailable,
          message: _error(error),
          messageId: state.messageId + 1,
        ),
      );
    }
  }

  // Delete a confirmed schedule without removing the target scene or device.
  Future<void> onDeleteSchedule(DeleteSchedule event, Emitter<ScheduleState> emit) async {
    if (_busy || !state.restAvailable) return;
    emit(state.copyWith(busyId: event.schedule.id));
    try {
      await repository.deleteSchedule(event.schedule.id);
      emit(
        state.copyWith(
          snapshot: repository.current,
          busyId: '',
          message: 'Schedule deleted.',
          messageId: state.messageId + 1,
        ),
      );
    } catch (error) {
      emit(
        state.copyWith(
          busyId: '',
          restAvailable: error is DioException ? false : state.restAvailable,
          message: _error(error),
          messageId: state.messageId + 1,
        ),
      );
    }
  }

  String _error(Object error) => error is DioException
      ? 'Cannot reach the REST hub. Check the server and retry. Your changes are preserved.'
      : feedbackMessage(error);

  // Cancel this module's listener while leaving the shared repository owner intact.
  @override
  Future<void> close() async {
    await hubStreamSubscription.cancel();
    await homeStreamSubscription.cancel();
    return super.close();
  }
}
