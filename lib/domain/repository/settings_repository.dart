import '../entities/app_settings.dart';

// List the local preference operations available to Bloc/Cubit.
abstract class SettingsRepository {
  // Saved preferences

  // Read the current saved preferences.
  AppSettings get settings;

  // Restore saved preferences when the app starts.
  Future<void> loadSettings();

  // Save preferences and apply any connection changes.
  Future<void> saveSettings(AppSettings value);

  // Local storage

  // Clear downloaded home data while keeping preferences and favourites.
  Future<void> clearCache();
}
