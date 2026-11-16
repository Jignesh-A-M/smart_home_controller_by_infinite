import 'package:equatable/equatable.dart';

import '../../../domain/entities/app_settings.dart';

class SettingsState extends Equatable {
  final AppSettings saved;
  final AppSettings draft;
  final String portText;
  final String message;
  final String error;
  final int messageId;
  final bool isLoading, isSaving;

  const SettingsState({
    this.saved = const AppSettings(),
    this.draft = const AppSettings(),
    this.portText = '1883',
    this.isLoading = true,
    this.isSaving = false,
    this.message = '',
    this.messageId = 0,
    this.error = '',
  });

  // Replace changed form fields without applying unsaved connection values.
  SettingsState copyWith({
    AppSettings? saved,
    AppSettings? draft,
    String? portText,
    bool? isLoading,
    bool? isSaving,
    String? message,
    int? messageId,
    String? error,
  }) => SettingsState(
    saved: saved ?? this.saved,
    draft: draft ?? this.draft,
    portText: portText ?? this.portText,
    isLoading: isLoading ?? this.isLoading,
    isSaving: isSaving ?? this.isSaving,
    message: message ?? this.message,
    messageId: messageId ?? this.messageId,
    error: error ?? this.error,
  );

  @override
  List<Object?> get props => [saved, draft, portText, isLoading, isSaving, message, messageId, error];
}
