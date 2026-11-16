import 'dart:async';
import 'package:smart_home_controller_by_infinite/domain/transport/quick_tile_gateway.dart';

class FakeQuickTileGateway implements QuickTileGateway {
  final events = StreamController<void>.broadcast();
  QuickSceneRequest? pending;
  final selections = <String>[];
  bool supported = true;
  Completer<void>? configurationGate;
  @override
  Stream<void> get requests => events.stream;
  @override
  Future<bool> initialize() async => supported;
  @override
  Future<QuickSceneRequest?> takeRequest() async {
    final request = pending;
    pending = null;
    return request;
  }

  @override
  Future<void> configure(String sceneId, String sceneName) async {
    await configurationGate?.future;
    selections.add(sceneId);
  }

  @override
  Future<void> dispose() => events.close();
  void tap(String sceneId, String token) {
    pending = QuickSceneRequest(sceneId, token);
    events.add(null);
  }
}
