import 'package:flutter/material.dart';
import 'app/app.dart';

// Initialize platform bindings before starting the dashboard.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const InfiniteHomeApp());
}
