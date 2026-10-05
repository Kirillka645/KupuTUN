import 'dart:io';

import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;

import '../core/models/test_result.dart';

/// Test history in SQLite.
/// Decision: only metrics + server ids are stored (no credentials), so the
/// DB is not encrypted; retention is capped to keep it small.
class HistoryDb {
  static const _version = 1;
  static const keepPerServer = 50;
  final Database db;
  HistoryDb._(this.db);

  static Future<HistoryDb> open(String path) async {
    final DatabaseFactory factory;
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      ffi.sqfliteFfiInit();
      factory = ffi.databaseFactoryFfi;
    } else {
      factory = databaseFactory;
    }
    final db = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: _version,
        onCreate: (db, v) async {
          await db.execute('''
            CREATE TABLE test_results(
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              server_id TEXT NOT NULL,
              ts INTEGER NOT NULL,
              mode TEXT NOT NULL,
              samples TEXT,
              median_ms INTEGER,
              jitter_ms REAL,
              loss REAL,
              tls_ms INTEGER,
              down_mbps REAL,
              up_mbps REAL,
              bytes INTEGER,
              exit_ip TEXT,
              exit_country TEXT,
              services TEXT,
              error TEXT
            )''');
          await db.execute('CREATE INDEX idx_results_server_ts ON test_results(server_id, ts DESC)');
        },
      ),
    );
    return HistoryDb._(db);
  }

  Future<void> insert(TestResult r) async {
    final row = r.toRow()..remove('id');
    await db.insert('test_results', row);
    // trim old rows for this server
    await db.rawDelete('''
      DELETE FROM test_results WHERE server_id = ? AND id NOT IN (
        SELECT id FROM test_results WHERE server_id = ? ORDER BY ts DESC LIMIT ?
      )''', [r.serverId, r.serverId, keepPerServer]);
  }

  Future<void> insertAll(Iterable<TestResult> rs) async {
    final batch = db.batch();
    final ids = <String>{};
    for (final r in rs) {
      batch.insert('test_results', r.toRow()..remove('id'));
      ids.add(r.serverId);
    }
    for (final id in ids) {
      batch.rawDelete('''
        DELETE FROM test_results WHERE server_id = ? AND id NOT IN (
          SELECT id FROM test_results WHERE server_id = ? ORDER BY ts DESC LIMIT ?
        )''', [id, id, keepPerServer]);
    }
    await batch.commit(noResult: true);
  }

  Future<List<TestResult>> history(String serverId, {int limit = 30}) async {
    final rows = await db.query('test_results', where: 'server_id = ?', whereArgs: [serverId], orderBy: 'ts DESC', limit: limit);
    return rows.map(TestResult.fromRow).toList().reversed.toList();
  }

  /// Latest result per server (for list rendering at startup).
  Future<Map<String, TestResult>> latestAll() async {
    final rows = await db.rawQuery('''
      SELECT t.* FROM test_results t
      JOIN (SELECT server_id, MAX(ts) AS mts FROM test_results GROUP BY server_id) m
        ON t.server_id = m.server_id AND t.ts = m.mts''');
    return {for (final r in rows) r['server_id'] as String: TestResult.fromRow(r)};
  }

  Future<void> deleteServer(String serverId) => db.delete('test_results', where: 'server_id = ?', whereArgs: [serverId]);

  Future<void> close() => db.close();
}
