import 'package:flutter/material.dart';
import 'app.dart';
import 'core/di/injector.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  configureDependencies();
  runApp(const EggFarmApp());
}
