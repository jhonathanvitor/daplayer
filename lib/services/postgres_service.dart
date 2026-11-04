import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/playlist.dart';
import '../models/track.dart';
import '../models/user_model.dart';

class _NeonEndpointConfig {
  final Uri sqlEndpoint;
  final String connectionString;

  const _NeonEndpointConfig({
    required this.sqlEndpoint,
    required this.connectionString,
  });
}

/// Serviço de conexão direta ao PostgreSQL (Neon.tech Serverless HTTP SQL na porta 443)
/// Funciona em qualquer rede Wi-Fi ou 4G/5G mobile sem bloqueio de porta 5432.
class PostgresService {
  static final PostgresService instance = PostgresService._internal();
  PostgresService._internal();

  static const String _envDatabaseUrl = String.fromEnvironment(
    'DATABASE_URL',
    defaultValue: '',
  );
  static const String _envPgHost = String.fromEnvironment('PGHOST', defaultValue: '');
  static const String _envPgDatabase = String.fromEnvironment('PGDATABASE', defaultValue: '');
  static const String _envPgUser = String.fromEnvironment('PGUSER', defaultValue: '');
  static const String _envPgPassword = String.fromEnvironment('PGPASSWORD', defaultValue: '');

  bool _schemaInitialized = false;
  Map<String, String>? _fileEnvCache;

  /// Lê variáveis do arquivo .env local (em Desktop/Dev) caso não tenham vindo via --dart-define
  Map<String, String> _loadDotEnvFromFile() {
    if (_fileEnvCache != null) return _fileEnvCache!;
    final map = <String, String>{};
    try {
      final execDir = File(Platform.resolvedExecutable).parent.path;
      final candidates = [
        File('.env'),
        File('$execDir/.env'),
      ];
      for (final file in candidates) {
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
          break;
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

  _NeonEndpointConfig? _resolveConfig() {
    final dbUrl = _getEnv('DATABASE_URL', _envDatabaseUrl);
    if (dbUrl.isNotEmpty) {
      try {
        final uri = Uri.parse(dbUrl);
        final userInfoParts = uri.userInfo.split(':');
        final password = userInfoParts.length > 1
            ? Uri.decodeComponent(userInfoParts.sublist(1).join(':'))
            : '';

        if (password.isEmpty ||
            password == 'MINHA-SENHA-AQUI' ||
            password == 'SUA_SENHA_AQUI') {
          return null;
        }

        final dbName = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : 'daplay';
        final cleanConnStr = 'postgresql://${uri.userInfo}@${uri.host}/$dbName?sslmode=require';
        return _NeonEndpointConfig(
          sqlEndpoint: Uri.parse('https://${uri.host}/sql'),
          connectionString: cleanConnStr,
        );
      } catch (e) {
        debugPrint('Erro ao interpretar DATABASE_URL: $e');
      }
    }

    final host = _getEnv('PGHOST', _envPgHost);
    final user = _getEnv('PGUSER', _envPgUser);
    final password = _getEnv('PGPASSWORD', _envPgPassword);
    final database = _getEnv('PGDATABASE', _envPgDatabase);

    if (host.isNotEmpty &&
        user.isNotEmpty &&
        password.isNotEmpty &&
        password != 'MINHA-SENHA-AQUI' &&
        password != 'SUA_SENHA_AQUI' &&
        database.isNotEmpty) {
      final encUser = Uri.encodeComponent(user);
      final encPass = Uri.encodeComponent(password);
      return _NeonEndpointConfig(
        sqlEndpoint: Uri.parse('https://$host/sql'),
        connectionString: 'postgresql://$encUser:$encPass@$host/$database?sslmode=require',
      );
    }

    return null;
  }

  bool get isConfigured => _resolveConfig() != null;

  /// Executa uma query parametrizada ($1, $2, ...) no PostgreSQL via HTTPS (porta 443)
  Future<List<Map<String, dynamic>>> query(
    String sql, [
    List<dynamic> params = const [],
  ]) async {
    final config = _resolveConfig();
    if (config == null) return [];

    if (!_schemaInitialized) {
      _schemaInitialized = true;
      await ensureSchema();
    }

    return _rawQuery(config, sql, params);
  }

  Future<List<Map<String, dynamic>>> _rawQuery(
    _NeonEndpointConfig config,
    String sql, [
    List<dynamic> params = const [],
  ]) async {
    final response = await http
        .post(
          config.sqlEndpoint,
          headers: {
            'Content-Type': 'application/json',
            'Neon-Connection-String': config.connectionString,
          },
          body: json.encode({
            'query': sql,
            'params': params,
          }),
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw Exception('PostgreSQL HTTP ${response.statusCode}: ${response.body}');
    }

    final data = json.decode(response.body) as Map<String, dynamic>;
    final rows = data['rows'] as List<dynamic>? ?? [];
    return rows.map((r) => Map<String, dynamic>.from(r as Map)).toList();
  }

  /// Garante que todas as tabelas existam no banco PostgreSQL (Neon)
  Future<void> ensureSchema() async {
    final config = _resolveConfig();
    if (config == null) return;

    try {
      await _rawQuery(config, '''
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

      // Garante colunas extras caso a tabela users tenha sido criada anteriormente com schema antigo
      await _rawQuery(config, 'ALTER TABLE users ADD COLUMN IF NOT EXISTS email_hash VARCHAR(128)');
      await _rawQuery(config, 'ALTER TABLE users ADD COLUMN IF NOT EXISTS salt VARCHAR(128)');
      await _rawQuery(config, 'ALTER TABLE users ADD COLUMN IF NOT EXISTS google_id VARCHAR(120)');
      await _rawQuery(config, 'ALTER TABLE users ADD COLUMN IF NOT EXISTS avatar_url TEXT');
      await _rawQuery(config, "ALTER TABLE users ADD COLUMN IF NOT EXISTS auth_provider VARCHAR(30) NOT NULL DEFAULT 'email'");
      await _rawQuery(config, 'ALTER TABLE users ADD COLUMN IF NOT EXISTS youtube_token TEXT');
      await _rawQuery(config, 'CREATE UNIQUE INDEX IF NOT EXISTS uq_users_email_hash ON users(email_hash)');

      await _rawQuery(config, '''
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

      await _rawQuery(config, '''
        CREATE TABLE IF NOT EXISTS playlists (
          id VARCHAR(100) PRIMARY KEY,
          user_id VARCHAR(100) NOT NULL REFERENCES users(id) ON DELETE CASCADE,
          name VARCHAR(150) NOT NULL,
          description TEXT DEFAULT '',
          updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
        )
      ''');

      await _rawQuery(config, '''
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

      await _rawQuery(
        config,
        'CREATE INDEX IF NOT EXISTS idx_playlists_user_id ON playlists(user_id)',
      );
      await _rawQuery(
        config,
        'CREATE INDEX IF NOT EXISTS idx_playlist_tracks_playlist_pos ON playlist_tracks(playlist_id, position)',
      );
    } catch (e) {
      debugPrint('Aviso ao verificar tabelas no PostgreSQL: $e');
    }
  }

  /// Salva ou atualiza o usuário diretamente no PostgreSQL (Neon) e cria assinatura inicial
  Future<void> upsertUser({
    required UserModel user,
    required String emailHash,
    String? passwordHash,
    String? salt,
  }) async {
    try {
      final rows = await query(
        '''
        INSERT INTO users (
          id, name, email, email_hash, password_hash, salt,
          google_id, avatar_url, auth_provider, youtube_token, created_at
        ) VALUES (
          \$1, \$2, \$3, \$4, \$5, \$6, \$7, \$8, \$9, \$10, \$11
        )
        ON CONFLICT (email_hash) DO UPDATE SET
          name = EXCLUDED.name,
          google_id = COALESCE(EXCLUDED.google_id, users.google_id),
          avatar_url = COALESCE(EXCLUDED.avatar_url, users.avatar_url),
          youtube_token = COALESCE(EXCLUDED.youtube_token, users.youtube_token)
        RETURNING id
        ''',
        [
          user.id,
          user.name,
          user.email,
          emailHash,
          passwordHash,
          salt,
          user.googleId,
          user.avatarUrl,
          user.authProvider,
          user.youtubeToken,
          user.createdAt.toUtc().toIso8601String(),
        ],
      );

      final actualUserId = rows.isNotEmpty ? (rows.first['id'] as String) : user.id;

      await query(
        '''
        INSERT INTO subscriptions (user_id, plan, is_active, max_playlists)
        VALUES (\$1, 'free', FALSE, 5)
        ON CONFLICT (user_id) DO NOTHING
        ''',
        [actualUserId],
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
    try {
      final rows = await query(
        '''
        SELECT id, name, email, email_hash, password_hash, salt,
               google_id, avatar_url, auth_provider, youtube_token, created_at
        FROM users
        WHERE email_hash = \$1
           OR (\$2::text IS NOT NULL AND google_id = \$2)
        LIMIT 1
        ''',
        [emailHash, googleId],
      );

      if (rows.isEmpty) return null;
      return rows.first;
    } catch (e) {
      debugPrint('Erro ao buscar usuário no PostgreSQL: $e');
      return null;
    }
  }

  /// Busca todas as playlists do usuário diretamente no PostgreSQL (Neon)
  Future<List<Playlist>?> fetchUserPlaylists(String userId) async {
    try {
      final plRows = await query(
        '''
        SELECT id, name, description
        FROM playlists
        WHERE user_id = \$1
        ORDER BY updated_at ASC
        ''',
        [userId],
      );

      final playlists = <Playlist>[];
      for (final map in plRows) {
        final plId = map['id'] as String;
        final trackRows = await query(
          '''
          SELECT video_id, title, artist, thumbnail_url, duration_seconds
          FROM playlist_tracks
          WHERE playlist_id = \$1
          ORDER BY position ASC
          ''',
          [plId],
        );

        final tracks = trackRows.map((tm) {
          final durSec = tm['duration_seconds'];
          final parsedSec = durSec is int
              ? durSec
              : int.tryParse(durSec?.toString() ?? '0') ?? 0;
          return Track(
            id: tm['video_id'] as String,
            title: tm['title'] as String,
            artist: tm['artist'] as String,
            thumbnailUrl: tm['thumbnail_url'] as String,
            duration: Duration(seconds: parsedSec),
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
    try {
      if (playlists.isEmpty) {
        await query('DELETE FROM playlists WHERE user_id = \$1', [userId]);
        return;
      }

      for (final pl in playlists) {
        await query(
          '''
          INSERT INTO playlists (id, user_id, name, description, updated_at)
          VALUES (\$1, \$2, \$3, \$4, NOW())
          ON CONFLICT (id) DO UPDATE SET
            name = EXCLUDED.name,
            description = EXCLUDED.description,
            updated_at = NOW()
          ''',
          [pl.id, userId, pl.name, pl.description],
        );

        await query('DELETE FROM playlist_tracks WHERE playlist_id = \$1', [pl.id]);

        for (int i = 0; i < pl.tracks.length; i++) {
          final t = pl.tracks[i];
          await query(
            '''
            INSERT INTO playlist_tracks (
              playlist_id, video_id, title, artist, thumbnail_url, duration_seconds, position
            ) VALUES (
              \$1, \$2, \$3, \$4, \$5, \$6, \$7
            )
            ''',
            [
              pl.id,
              t.id,
              t.title,
              t.artist,
              t.thumbnailUrl,
              t.duration.inSeconds,
              i,
            ],
          );
        }
      }
    } catch (e) {
      debugPrint('Erro ao salvar playlists no PostgreSQL: $e');
    }
  }

  /// Remove uma playlist específica no PostgreSQL
  Future<void> deleteUserPlaylist(String userId, String playlistId) async {
    try {
      await query(
        'DELETE FROM playlists WHERE id = \$1 AND user_id = \$2',
        [playlistId, userId],
      );
    } catch (e) {
      debugPrint('Erro ao excluir playlist no PostgreSQL: $e');
    }
  }
}
