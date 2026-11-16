import '../entities/home_snapshot.dart';

// List the scene configuration operations available to Bloc/Cubit.
abstract class SceneRepository {
  // Scenes

  // Create or update a scene without running its device actions.
  Future<Scene> saveScene(Scene scene, {required bool isNew});

  // Delete a scene after checking its schedule references.
  Future<void> deleteScene(String id);
}
