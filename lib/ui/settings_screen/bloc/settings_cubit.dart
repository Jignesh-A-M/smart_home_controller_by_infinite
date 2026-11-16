import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../domain/entities/app_settings.dart';
import '../../../domain/repository/settings_repository.dart';
import 'settings_state.dart';

class SettingsCubit extends Cubit<SettingsState> {
  final SettingsRepository repository;

  SettingsCubit({required this.repository}) : super(const SettingsState());

  // Restore preferences before the normal app screens start their connections.
  Future<void> load() async {
    try {
      await repository.loadSettings();
      emit(
        state.copyWith(
          saved: repository.settings,
          draft: repository.settings,
          portText: '${repository.settings.mqttPort}',
          isLoading: false,
        ),
      );
    } catch (_) {
      emit(
        state.copyWith(
          isLoading: false,
          message: 'Could not restore preferences. Default settings are shown.',
          messageId: state.messageId + 1,
        ),
      );
    }
  }

  // Keep connection form changes separate from saved runtime settings.
  void changeConnection({String? restUrl, String? mqttHost, String? port, String? topicPrefix}) {
    if (state.isSaving) return;
    emit(
      state.copyWith(
        draft: state.draft.copyWith(restUrl: restUrl, mqttHost: mqttHost, topicPrefix: topicPrefix),
        portText: port,
        error: '',
      ),
    );
  }

  // Persist appearance immediately without applying an unfinished connection form.
  Future<void> setDarkMode(bool value) => _saveDisplay(darkMode: value);

  // Change display/input units without sending commands or modifying canonical data.
  Future<void> setTemperatureUnit(TemperatureUnit value) => _saveDisplay(unit: value);

  // Select the favourite scene used by the Android Quick Settings tile.
  Future<void> setQuickScene(String id) => _saveDisplay(quickSceneId: id);

  Future<void> _saveDisplay({bool? darkMode, TemperatureUnit? unit, String? quickSceneId}) async {
    if (state.isSaving) return;
    emit(state.copyWith(isSaving: true));
    try {
      await repository.saveSettings(
        state.saved.copyWith(darkMode: darkMode, temperatureUnit: unit, quickSceneId: quickSceneId),
      );
      emit(
        state.copyWith(
          saved: repository.settings,
          draft: state.draft.copyWith(darkMode: darkMode, temperatureUnit: unit, quickSceneId: quickSceneId),
          isSaving: false,
          error: '',
        ),
      );
    } catch (error) {
      emit(state.copyWith(isSaving: false, message: _error(error), messageId: state.messageId + 1));
    }
  }

  // Apply validated connection fields and let the repository replace the old client.
  Future<void> applyConnection() async {
    if (state.isSaving) return;
    final port = int.tryParse(state.portText.trim());
    if (port == null) {
      emit(state.copyWith(error: 'Enter a port between 1 and 65535.'));
      return;
    }
    emit(state.copyWith(isSaving: true, error: ''));
    try {
      await repository.saveSettings(
        state.draft.copyWith(
          restUrl: state.draft.restUrl.trim().replaceFirst(RegExp(r'/$'), ''),
          mqttHost: state.draft.mqttHost.trim(),
          topicPrefix: state.draft.topicPrefix.trim(),
          mqttPort: port,
        ),
      );
      emit(
        state.copyWith(
          saved: repository.settings,
          draft: repository.settings,
          portText: '${repository.settings.mqttPort}',
          isSaving: false,
          message: 'Connection settings saved. Reconnecting to the hub.',
          messageId: state.messageId + 1,
        ),
      );
    } catch (error) {
      emit(state.copyWith(isSaving: false, error: _error(error)));
    }
  }

  // Clear only downloaded data after the screen obtains explicit confirmation.
  Future<void> clearCache() async {
    if (state.isSaving) return;
    emit(state.copyWith(isSaving: true));
    try {
      await repository.clearCache();
      emit(
        state.copyWith(
          isSaving: false,
          message: 'Downloaded cache cleared. Settings and stars are preserved. Refresh to load hub data.',
          messageId: state.messageId + 1,
        ),
      );
    } catch (error) {
      emit(state.copyWith(isSaving: false, message: _error(error), messageId: state.messageId + 1));
    }
  }

  String _error(Object error) => error is FormatException
      ? error.message
      : error is StateError
      ? error.message
      : 'Could not save locally. Your previous settings are preserved. Retry.';
}
