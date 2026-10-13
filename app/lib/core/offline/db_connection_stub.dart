// Stub for web — returns an in-memory database.
import 'package:drift/drift.dart';
import 'package:drift/native.dart';

QueryExecutor openAppDatabase() => NativeDatabase.memory();
