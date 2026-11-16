import 'package:equatable/equatable.dart';

import '../../../domain/entities/home_snapshot.dart';
import '../../../domain/entities/schedule.dart';

class ScheduleState extends Equatable {
  final HomeSnapshot snapshot;
  final bool isLoading;
  final bool restAvailable;
  final bool isSaving;
  final bool isNew;
  final bool isDirty;
  final bool showValidation;
  final String busyId, message;
  final Schedule? draft;
  final int savedVersion, messageId;

  const ScheduleState({
    this.snapshot = const HomeSnapshot(),
    this.isLoading = false,
    this.restAvailable = false,
    this.isSaving = false,
    this.busyId = '',
    this.draft,
    this.isNew = true,
    this.isDirty = false,
    this.showValidation = false,
    this.savedVersion = 0,
    this.message = '',
    this.messageId = 0,
  });

  // Replace changed fields while preserving the draft and confirmed schedule list.
  ScheduleState copyWith({
    HomeSnapshot? snapshot,
    bool? isLoading,
    bool? restAvailable,
    bool? isSaving,
    String? busyId,
    Schedule? draft,
    bool? isNew,
    bool? isDirty,
    bool? showValidation,
    int? savedVersion,
    String? message,
    int? messageId,
  }) => ScheduleState(
    snapshot: snapshot ?? this.snapshot,
    isLoading: isLoading ?? this.isLoading,
    restAvailable: restAvailable ?? this.restAvailable,
    isSaving: isSaving ?? this.isSaving,
    busyId: busyId ?? this.busyId,
    draft: draft ?? this.draft,
    isNew: isNew ?? this.isNew,
    isDirty: isDirty ?? this.isDirty,
    showValidation: showValidation ?? this.showValidation,
    savedVersion: savedVersion ?? this.savedVersion,
    message: message ?? this.message,
    messageId: messageId ?? this.messageId,
  );

  @override
  List<Object?> get props => [
    snapshot,
    isLoading,
    restAvailable,
    isSaving,
    busyId,
    draft,
    isNew,
    isDirty,
    showValidation,
    savedVersion,
    message,
    messageId,
  ];
}
