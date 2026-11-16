import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'home_store.dart';

// Persist the confirmed snapshot and local favourite overrides in SQLite.
class SqliteHomeStore implements HomeStore {
  Database? _database;

  Future<Database> _open() async => _database ??= await openDatabase(
    '${await getDatabasesPath()}/infinite_home.db',
    version: 1,
    onCreate: (db, _) => db.execute('CREATE TABLE entries (key TEXT PRIMARY KEY, value TEXT NOT NULL)'),
  );

  @override
  Future<Map<String, dynamic>?> read(String key) async {
    final rows = await (await _open()).query('entries', where: 'key = ?', whereArgs: [key]);
    return rows.isEmpty ? null : Map<String, dynamic>.from(jsonDecode(rows.first['value'] as String) as Map);
  }

  @override
  Future<void> write(String key, Map<String, dynamic> value) async {
    await (await _open()).insert('entries', {
      'key': key,
      'value': jsonEncode(value),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<void> close() async {
    await _database?.close();
  }
}
