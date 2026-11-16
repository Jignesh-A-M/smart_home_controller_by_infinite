import '../entities/app_settings.dart';

abstract class SettingsRepository {
  AppSettings get settings;
  Future<void> loadSettings();
  Future<void> saveSettings(AppSettings value);
  Future<void> clearCache();
}
