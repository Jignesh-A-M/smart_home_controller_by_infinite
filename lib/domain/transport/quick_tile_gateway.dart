class QuickSceneRequest {
  const QuickSceneRequest(this.sceneId, this.token);

  final String sceneId, token;
}

abstract class QuickTileGateway {
  Stream<void> get requests;

  Future<bool> initialize();

  Future<QuickSceneRequest?> takeRequest();

  Future<void> configure(String sceneId, String sceneName);

  Future<void> dispose();
}
