// Allow repository tests to replace SQLite with a memory store.
abstract class HomeStore {
  Future<Map<String, dynamic>?> read(String key);

  Future<void> write(String key, Map<String, dynamic> value);

  Future<void> close();
}
