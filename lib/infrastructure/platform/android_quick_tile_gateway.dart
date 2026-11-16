import 'dart:async';

import 'package:flutter/services.dart';

import '../../domain/transport/quick_tile_gateway.dart';

class AndroidQuickTileGateway implements QuickTileGateway {
  static const _channel = MethodChannel('infinite_home/quick_tile');
  final _requests = StreamController<void>.broadcast();

  @override
  Stream<void> get requests => _requests.stream;

  // Register the Android callback while keeping unsupported platforms harmless.
  @override
  Future<bool> initialize() async {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'quickSceneRequested' && !_requests.isClosed) {
        _requests.add(null);
      }
    });
    try {
      return await _channel.invokeMethod<bool>('isSupported') ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  // Consume each explicit tile tap once, including a cold application launch.
  @override
  Future<QuickSceneRequest?> takeRequest() async {
    final raw = await _channel.invokeMapMethod<String, dynamic>('consumeRequest');
    if (raw == null || raw['sceneId'] is! String || raw['token'] is! String) {
      return null;
    }
    return QuickSceneRequest(raw['sceneId'] as String, raw['token'] as String);
  }

  @override
  Future<void> configure(String sceneId, String sceneName) =>
      _channel.invokeMethod<void>('setSelection', {'sceneId': sceneId, 'sceneName': sceneName});

  @override
  Future<void> dispose() async {
    _channel.setMethodCallHandler(null);
    await _requests.close();
  }
}
