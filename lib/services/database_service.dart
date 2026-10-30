import 'dart:ffi';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqlite3/open.dart';

/// Inicialização do FFI para SQLite em sistemas Desktop
void _linuxSqliteFfiInit() {
  if (Platform.isLinux) {
    open.overrideFor(OperatingSystem.linux, () {
      final candidates = [
        '/usr/lib/x86_64-linux-gnu/libsqlite3.so.0',
        '/usr/lib/aarch64-linux-gnu/libsqlite3.so.0',
        '/usr/lib/libsqlite3.so.0',
        '${Platform.environment['HOME']}/.local/lib/libsqlite3.so',
        'libsqlite3.so.0',
        'libsqlite3.so',
      ];
      for (final candidate in candidates) {
        try {
          return DynamicLibrary.open(candidate);
        } catch (_) {}
      }
      return DynamicLibrary.open('libsqlite3.so.0');
    });
  }
}

class DatabaseService {
  static Database? _database;
  static bool _initializedFactory = false;

  /// Inicializa a fábrica de banco de dados FFI para Desktop
  static void initialize() {
    if (_initializedFactory) return;

    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      _linuxSqliteFfiInit();
      sqfliteFfiInit();
      databaseFactory = createDatabaseFactoryFfi(ffiInit: _linuxSqliteFfiInit);
    }
    _initializedFactory = true;
  }

  static Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  static Future<Database> _initDatabase() async {
    initialize();

    try {
      final directory = await getApplicationSupportDirectory();
      final dbPath = p.join(directory.path, 'daplayer_encrypted.db');

      return await openDatabase(
        dbPath,
        version: 2,
        onCreate: (db, version) async {
          // Tabela de Usuários com dados e credenciais criptografados
          await db.execute('''
            CREATE TABLE users (
              id TEXT PRIMARY KEY,
              name_encrypted TEXT NOT NULL,
              email_encrypted TEXT NOT NULL,
              email_hash TEXT UNIQUE NOT NULL,
              password_hash TEXT,
              salt TEXT,
              google_id TEXT,
              avatar_url_encrypted TEXT,
              auth_provider TEXT NOT NULL DEFAULT 'email',
              youtube_token_encrypted TEXT,
              created_at TEXT NOT NULL
            )
          ''');

          // Tabela de Sessão ativa para manter o usuário conectado
          await db.execute('''
            CREATE TABLE sessions (
              id TEXT PRIMARY KEY,
              user_id TEXT NOT NULL,
              logged_in_at TEXT NOT NULL,
              FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
            )
          ''');
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            try {
              await db.execute("ALTER TABLE users ADD COLUMN google_id TEXT");
              await db.execute("ALTER TABLE users ADD COLUMN avatar_url_encrypted TEXT");
              await db.execute("ALTER TABLE users ADD COLUMN auth_provider TEXT NOT NULL DEFAULT 'email'");
            } catch (_) {}
          }
        },
      );
    } catch (e) {
      debugPrint('Erro ao inicializar SQLite: $e');
      rethrow;
    }
  }

  static Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
    }
  }
}
