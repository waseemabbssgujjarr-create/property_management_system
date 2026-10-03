import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/config/app_config.dart';
import 'app.dart';

/// Production entry point.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppConfig.load(AppEnvironment.production);
  runApp(const ProviderScope(child: MunshiApp()));
}
