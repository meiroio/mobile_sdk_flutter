import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'configuration.dart';
import 'events_api.dart';

/// Offline queue and synchronization manager.
class MeiroSyncManager {
  /// Creates a sync manager.
  MeiroSyncManager({
    required MeiroEventsApi api,
    required MeiroLogger logger,
    Connectivity? connectivity,
    Future<Database> Function()? databaseProvider,
    DateTime Function()? clock,
  })  : _api = api,
        _logger = logger,
        _connectivity = connectivity ?? Connectivity(),
        _databaseProvider = databaseProvider ?? _openDatabase,
        _clock = clock ?? DateTime.now;

  final MeiroEventsApi _api;
  final MeiroLogger _logger;
  final Connectivity _connectivity;
  final Future<Database> Function() _databaseProvider;
  final DateTime Function() _clock;

  Database? _database;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  bool _syncRunning = false;

  /// Initializes the sync manager.
  Future<void> init() async {
    _database = await _databaseProvider();
    _connectivitySubscription =
        _connectivity.onConnectivityChanged.listen((results) {
      if (results.any((result) => result != ConnectivityResult.none)) {
        unawaited(sync());
      }
    });
  }

  /// Disposes subscriptions.
  Future<void> dispose() async {
    await _connectivitySubscription?.cancel();
    await _database?.close();
    _database = null;
  }

  /// Saves an event payload for later delivery.
  Future<void> savePayload(Map<String, Object?> payload) async {
    final database = await _requireDatabase();
    await database.insert(_tableName, {
      'created_at': _clock().millisecondsSinceEpoch,
      'payload': jsonEncode(payload),
    });
  }

  /// Sends queued events and removes events older than 24 hours.
  Future<void> sync() async {
    if (_syncRunning) {
      return;
    }
    _syncRunning = true;
    try {
      final database = await _requireDatabase();
      final oldestAllowed =
          _clock().subtract(_eventLifetime).millisecondsSinceEpoch;
      await database.delete(
        _tableName,
        where: 'created_at < ?',
        whereArgs: [oldestAllowed],
      );

      final rows = await database.query(_tableName, orderBy: 'id ASC');
      for (final row in rows) {
        final id = row['id']! as int;
        final payload = jsonDecode(row['payload']! as String);
        await _api.sendPayload((payload as Map).cast<String, Object?>());
        await database.delete(_tableName, where: 'id = ?', whereArgs: [id]);
      }
    } catch (error, stackTrace) {
      _logger.log('Event sync failed', error, stackTrace);
    } finally {
      _syncRunning = false;
    }
  }

  Future<Database> _requireDatabase() async {
    final existing = _database;
    if (existing != null) {
      return existing;
    }
    return _database = await _databaseProvider();
  }

  static Future<Database> _openDatabase() async {
    final databasePath = await getDatabasesPath();
    return openDatabase(
      p.join(databasePath, 'meiro_events.db'),
      // Each Flutter engine owns its connection; background cleanup must not
      // close the foreground SDK's connection to the same durable queue.
      singleInstance: false,
      version: 1,
      onCreate: (database, version) async {
        await database.execute('''
          CREATE TABLE $_tableName (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            created_at INTEGER NOT NULL,
            payload TEXT NOT NULL
          )
        ''');
      },
    );
  }

  static const _tableName = 'events';
  static const _eventLifetime = Duration(hours: 24);
}
