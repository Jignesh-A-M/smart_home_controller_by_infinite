import '../entities/home_snapshot.dart';

// Define scene persistence separately from running device actions.
abstract class SceneRepository {
  Future<Scene> saveScene(Scene scene, {required bool isNew});
  Future<void> deleteScene(String id);
}
