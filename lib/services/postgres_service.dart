import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:postgres/postgres.dart';
import '../models/playlist.dart';
import '../models/track.dart';
import '../models/user_model.dart';

class PostgresService {
  static final PostgresService instance = PostgresService._internal();
  PostgresService._internal();

  static const String _envDatabaseUrl = String.fromEnvironment(
    'DATABASE_URL',
    defaultValue: '',
  );
  static const String _envPgHost = String.fromEnvironment('PGHOST', defaultValue: '');
  static const String _envPgPort = String.fromEnvironment('PGPORT', defaultValue: '5432');
  static const String _envPgDatabase = String.fromEnvironment('PGDATABASE', defaultValue: '');
  static const String _envPgUser = String.fromEnvironment('PGUSER', defaultValue: '');
  static const String _envPgPassword = String.fromEnvironment('PGPASSWORD', defaultValue: '');

  Connection? _connection;
  bool _schemaInitialized = false;
  Map<String, String>? _fileEnvCache;

  /// Lê variáveis do arquivo .env local (em Desktop/Dev) caso não tenham vindo via --dart-define
  Map<String, String> _loadDotEnvFromFile() {
    if (_fileEnvCache != null) return _fileEnvCache!;
    final map = <String, String>{};
    try {
      final file = File('.env');
      if (file.existsSync()) {
        for (final rawLine in file.readAsLinesSync()) {
          final line = rawLine.trim();
          if (line.isEmpty || line.startsWith('#')) continue;
          final idx = line.indexOf('=');
          if (idx <= 0) continue;
          final key = line.substring(0, idx).trim();
          var val = line.substring(idx + 1).trim();
          if ((val.startsWith('"') && val.endsWith('"')) ||
              (val.startsWith("'") && val.endsWith("'"))) {
            val = val.substring(1, val.length - 1);
          }
          map[key] = val;
        }
      }
    } catch (_) {}
    _fileEnvCache = map;
    return map;
  }

  String _getEnv(String key, String compileTimeValue) {
    if (compileTimeValue.trim().isNotEmpty) return compileTimeValue.trim();
    final fileEnv = _loadDotEnvFromFile();
    return (fileEnv[key] ?? '').trim();
  }

  Endpoint? _resolveEndpoint() {
    final dbUrl = _getEnv('DATABASE_URL', _envDatabaseUrl);
    if (dbUrl.isNotEmpty) {
      try {
        final uri = Uri.parse(dbUrl);
        final userInfoParts = uri.userInfo.split(':');
        final username = userInfoParts.isNotEmpty ? Uri.decodeComponent(userInfoParts[0]) : '';
        final password = userInfoParts.length > 1
            ? Uri.decodeComponent(userInfoParts.sublist(1).join(':'))
            : '';

        if (password.isEmpty ||
            password == 'MINHA-SENHA-AQUI' ||
            password == 'SUA_SENHA_AQUI') {
          return null;
        }

        final dbName = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : 'daplay';
        return Endpoint(
          host: uri.host,
          port: uri.port > 0 ? uri.port : 5432,
          database: dbName,
          username: username,
          password: password,
        );
      } catch (e) {
        debugPrint('Erro ao interpretar DATABASE_URL: $e');
      }
    }

    final host = _getEnv('PGHOST', _envPgHost);
    final user = _getEnv('PGUSER', _envPgUser);
    final password = _getEnv('PGPASSWORD', _envPgPassword);
    final database = _getEnv('PGDATABASE', _envPgDatabase);
    final port = int.tryParse(_getEnv('PGPORT', _envPgPort)) ?? 5432;

    if (host.isNotEmpty &&
        user.isNotEmpty &&
        password.isNotEmpty &&
        password != 'MINHA-SENHA-AQUI' &&
        password != 'SUA_SENHA_AQUI' &&
        database.isNotEmpty) {
      return Endpoint(
        host: host,
        port: port,
        database: database,
        username: user,
        password: password,
      );
    }

    return null;
  }

  bool get isConfigured => _resolveEndpoint() != null;

  Future<Connection?> getConnection() async {
    final endpoint = _resolveEndpoint();
    if (endpoint == null) return null;

    if (_connection != null && _connection!.isOpen) {
      return _connection;
    }

    try {
      _connection = await Connection.open(
        endpoint,
        settings: const ConnectionSettings(
          sslMode: SslMode.require,
          connectTimeout: Duration(seconds: 12),
          queryTimeout: Duration(seconds: 15),
        ),
      );

      if (!_schemaInitialized) {
        await _ensureSchema(_connection!);
        _schemaInitialized = true;
      }

      return _connection;
    } catch (e) {
      debugPrint('Aviso: falha ao conectar no PostgreSQL (Neon): $e');
      _connection = null;
      return null;
    }
  }

  /// Garante que todas as tabelas existam no banco PostgreSQL (Neon)
  Future<void> _ensureSchema(Connection conn) async {
    await conn.execute('''
      CREATE TABLE IF NOT EXISTS users (
        id VARCHAR(100) PRIMARY KEY,
        name VARCHAR(120) NOT NULL,
        email VARCHAR(180) UNIQUE NOT NULL,
        email_hash VARCHAR(128) UNIQUE NOT NULL,
        password_hash VARCHAR(255),
        salt VARCHAR(128),
        google_id VARCHAR(120),
        avatar_url TEXT,
        auth_provider VARCHAR(30) NOT NULL DEFAULT 'email',
        youtube_token TEXT,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      )
    ''');

    await conn.execute('''
      CREATE TABLE IF NOT EXISTS subscriptions (
        id BIGSERIAL PRIMARY KEY,
        user_id VARCHAR(100) NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        plan VARCHAR(30) NOT NULL DEFAULT 'free',
        is_active BOOLEAN NOT NULL DEFAULT FALSE,
        max_playlists INT NOT NULL DEFAULT 5,
        gateway_subscription_id VARCHAR(120),
        expires_at TIMESTAMPTZ,
        updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        CONSTRAINT uq_subscription_user UNIQUE (user_id)
      )
    ''');

    await conn.execute('''
      CREATE TABLE IF NOT EXISTS playlists (
        id VARCHAR(100) PRIMARY KEY,
        user_id VARCHAR(100) NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        name VARCHAR(150) NOT NULL,
        description TEXT DEFAULT '',
        updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      )
    ''');

    await conn.execute('''
      CREATE TABLE IF NOT EXISTS playlist_tracks (
        id BIGSERIAL PRIMARY KEY,
        playlist_id VARCHAR(100) NOT NULL REFERENCES playlists(id) ON DELETE CASCADE,
        video_id VARCHAR(32) NOT NULL,
        title VARCHAR(255) NOT NULL,
        artist VARCHAR(180) NOT NULL,
        thumbnail_url TEXT NOT NULL,
        duration_seconds INT NOT NULL DEFAULT 0,
        position INT NOT NULL DEFAULT 0
      )
    ''');

    await conn.execute(
      'CREATE INDEX IF NOT EXISTS idx_playlists_user_id ON playlists(user_id)',
    );
    await conn.execute(
      'CREATE INDEX IF NOT EXISTS idx_playlist_tracks_playlist_pos ON playlist_tracks(playlist_id, position)',
    );
  }

  /// Salva ou atualiza o usuário diretamente no PostgreSQL (Neon) e cria assinatura inicial
  Future<void> upsertUser({
    required UserModel user,
    required String emailHash,
    String? passwordHash,
    String? salt,
  }) async {
    final conn = await getConnection();
    if (conn == null) return;

    try {
      await conn.execute(
        Sql.named('''
          INSERT INTO users (
            id, name, email, email_hash, password_hash, salt,
            google_id, avatar_url, auth_provider, youtube_token, created_at
          ) VALUES (
            @id, @name, @email, @emailHash, @passwordHash, @salt,
            @googleId, @avatarUrl, @authProvider, @youtubeToken, @createdAt
          )
          ON CONFLICT (email_hash) DO UPDATE SET
            name = EXCLUDED.name,
            google_id = COALESCE(EXCLUDED.google_id, users.google_id),
            avatar_url = COALESCE(EXCLUDED.avatar_url, users.avatar_url),
            youtube_token = COALESCE(EXCLUDED.youtube_token, users.youtube_token)
        '''),
        parameters: {
          'id': user.id,
          'name': user.name,
          'email': user.email,
          'emailHash': emailHash,
          'passwordHash': passwordHash,
          'salt': salt,
          'googleId': user.googleId,
          'avatarUrl': user.avatarUrl,
          'authProvider': user.authProvider,
          'youtubeToken': user.youtubeToken,
          'createdAt': user.createdAt.toUtc(),
        },
      );

      await conn.execute(
        Sql.named('''
          INSERT INTO subscriptions (user_id, plan, is_active, max_playlists)
          VALUES (@userId, 'free', FALSE, 5)
          ON CONFLICT (user_id) DO NOTHING
        '''),
        parameters: {'userId': user.id},
      );
    } catch (e) {
      debugPrint('Erro ao sincronizar usuário no PostgreSQL: $e');
    }
  }

  /// Busca usuário no PostgreSQL por e-mail hash ou google_id
  Future<Map<String, dynamic>?> findUserByEmailOrGoogle({
    required String emailHash,
    String? googleId,
  }) async {
    final conn = await getConnection();
    if (conn == null) return null;

    try {
      final result = await conn.execute(
        Sql.named('''
          SELECT id, name, email, email_hash, password_hash, salt,
                 google_id, avatar_url, auth_provider, youtube_token, created_at
          FROM users
          WHERE email_hash = @emailHash
             OR (@googleId IS NOT NULL AND google_id = @googleId)
          LIMIT 1
        '''),
        parameters: {
          'emailHash': emailHash,
          'googleId': googleId,
        },
      );

      if (result.isEmpty) return null;
      return result.first.toColumnMap();
    } catch (e) {
      debugPrint('Erro ao buscar usuário no PostgreSQL: $e');
      return null;
    }
  }

  /// Busca todas as playlists do usuário diretamente no PostgreSQL (Neon)
  Future<List<Playlist>?> fetchUserPlaylists(String userId) async {
    final conn = await getConnection();
    if (conn == null) return null;

    try {
      final plRows = await conn.execute(
        Sql.named('''
          SELECT id, name, description
          FROM playlists
          WHERE user_id = @userId
          ORDER BY updated_at ASC
        '''),
        parameters: {'userId': userId},
      );

      final playlists = <Playlist>[];
      for (final row in plRows) {
        final map = row.toColumnMap();
        final plId = map['id'] as String;
        final trackRows = await conn.execute(
          Sql.named('''
            SELECT video_id, title, artist, thumbnail_url, duration_seconds
            FROM playlist_tracks
            WHERE playlist_id = @playlistId
            ORDER BY position ASC
          '''),
          parameters: {'playlistId': plId},
        );

        final tracks = trackRows.map((tr) {
          final tm = tr.toColumnMap();
          return Track(
            id: tm['video_id'] as String,
            title: tm['title'] as String,
            artist: tm['artist'] as String,
            thumbnailUrl: tm['thumbnail_url'] as String,
            duration: Duration(seconds: (tm['duration_seconds'] as int?) ?? 0),
          );
        }).toList();

        playlists.add(
          Playlist(
            id: plId,
            name: (map['name'] as String?) ?? 'Coletânea',
            description: (map['description'] as String?) ?? '',
            tracks: tracks,
          ),
        );
      }

      return playlists;
    } catch (e) {
      debugPrint('Erro ao buscar playlists do PostgreSQL: $e');
      return null;
    }
  }

  /// Salva / sincroniza todas as playlists de um usuário diretamente no PostgreSQL
  Future<void> syncUserPlaylists(String userId, List<Playlist> playlists) async {
    final conn = await getConnection();
    if (conn == null) return;

    try {
      await conn.runTx((tx) async {
        // Remove playlists que foram excluídas pelo usuário
        final currentIds = playlists.map((p) => p.id).toList();
        if (currentIds.isEmpty) {
          await tx.execute(
            Sql.named('DELETE FROM playlists WHERE user_id = @userId'),
            parameters: {'userId': userId},
          );
          return;
        }

        for (final pl in playlists) {
          await tx.execute(
            Sql.named('''
              INSERT INTO playlists (id, user_id, name, description, updated_at)
              VALUES (@id, @userId, @name, @description, NOW())
              ON CONFLICT (id) DO UPDATE SET
                name = EXCLUDED.name,
                description = EXCLUDED.description,
                updated_at = NOW()
            '''),
            parameters: {
              'id': pl.id,
              'userId': userId,
              'name': pl.name,
              'description': pl.description,
            },
          );

          await tx.execute(
            Sql.named('DELETE FROM playlist_tracks WHERE playlist_id = @playlistId'),
            parameters: {'playlistId': pl.id},
          );

          for (int i = 0; i < pl.tracks.length; i++) {
            final t = pl.tracks[i];
            await tx.execute(
              Sql.named('''
                INSERT INTO playlist_tracks (
                  playlist_id, video_id, title, artist, thumbnail_url, duration_seconds, position
                ) VALUES (
                  @playlistId, @videoId, @title, @artist, @thumbnailUrl, @durationSeconds, @position
                )
              '''),
              parameters: {
                'playlistId': pl.id,
                'videoId': t.id,
                'title': t.title,
                'artist': t.artist,
                'thumbnailUrl': t.thumbnailUrl,
                'durationSeconds': t.duration.inSeconds,
                'position': i,
              },
            );
          }
        }
      });
    } catch (e) {
      debugPrint('Erro ao salvar playlists no PostgreSQL: $e');
    }
  }

  /// Remove uma playlist específica no PostgreSQL
  Future<void> deleteUserPlaylist(String userId, String playlistId) async {
    final conn = await getConnection();
    if (conn == null) return;

    try {
      await conn.execute(
        Sql.named(
          'DELETE FROM playlists WHERE id = @playlistId AND user_id = @userId',
        ),
        parameters: {'playlistId': playlistId, 'userId': userId},
      );
    } catch (e) {
      debugPrint('Erro ao excluir playlist no PostgreSQL: $e');
    }
  }
}
