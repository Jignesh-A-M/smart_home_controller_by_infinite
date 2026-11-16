import 'package:dio/dio.dart';

// USB adb reverse maps the phone's port 3000 to this computer's JSON Server.
const hubAddress = String.fromEnvironment('HUB_URL', defaultValue: 'http://127.0.0.1:3000');

Dio createApiClient() => Dio(
  BaseOptions(
    baseUrl: hubAddress,
    connectTimeout: const Duration(seconds: 5),
    receiveTimeout: const Duration(seconds: 5),
  ),
);
