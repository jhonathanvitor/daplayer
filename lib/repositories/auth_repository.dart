import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../models/user_model.dart';
import '../services/database_service.dart';
import '../services/crypto_service.dart';
import '../services/google_auth_service.dart';

/// Interface abstrata para autenticação
/// Permite alternar facilmente entre SQLite local e uma API REST remota no futuro!
abstract class AuthRepository {
  Future<UserModel?> login({required String email, required String password});
  Future<UserModel> register({
    required String name,
    required String email,
    required String password,
  });
  Future<UserModel> signInWithGoogle(GoogleAuthResult result);
  Future<UserModel> linkGoogleAccount({
    required String userId,
    required GoogleAuthResult result,
  });
  Future<void> unlinkGoogleAccount({required String userId});
  Future<UserModel?> getCurrentUser();
  Future<void> logout();
}

/// Implementação Local em SQLite com Criptografia Completa
class LocalSqliteAuthRepository implements AuthRepository {
  @override
  Future<UserModel> register({
    required String name,
    required String email,
    required String password,
  }) async {
    final db = await DatabaseService.database;
    final normalizedEmail = email.trim().toLowerCase();
    final emailHash = CryptoService.searchHash(normalizedEmail);

    // 1. Verifica se já existe um usuário com o mesmo hash de e-mail
    final existing = await db.query(
      'users',
      where: 'email_hash = ?',
      whereArgs: [emailHash],
      limit: 1,
    );

    if (existing.isNotEmpty) {
      throw Exception('Este e-mail já está cadastrado no sistema.');
    }

    // 2. Criptografa dados sensíveis e gera o salt da senha
    final salt = CryptoService.generateSalt();
    final passwordHash = CryptoService.hashPassword(password, salt);
    final nameEncrypted = CryptoService.encrypt(name.trim());
    final emailEncrypted = CryptoService.encrypt(normalizedEmail);
    final now = DateTime.now();
    final userId = 'usr_${now.millisecondsSinceEpoch}';

    // 3. Insere o registro criptografado no SQLite
    await db.insert('users', {
      'id': userId,
      'name_encrypted': nameEncrypted,
      'email_encrypted': emailEncrypted,
      'email_hash': emailHash,
      'password_hash': passwordHash,
      'salt': salt,
      'google_id': null,
      'avatar_url_encrypted': null,
      'auth_provider': 'email',
      'youtube_token_encrypted': null,
      'created_at': now.toIso8601String(),
    });

    // 4. Salva a sessão ativa
    await _saveActiveSession(db, userId);

    return UserModel(
      id: userId,
      name: name.trim(),
      email: normalizedEmail,
      authProvider: 'email',
      createdAt: now,
    );
  }

  @override
  Future<UserModel?> login({
    required String email,
    required String password,
  }) async {
    final db = await DatabaseService.database;
    final normalizedEmail = email.trim().toLowerCase();
    final emailHash = CryptoService.searchHash(normalizedEmail);

    // 1. Busca pelo hash indexado
    final results = await db.query(
      'users',
      where: 'email_hash = ?',
      whereArgs: [emailHash],
      limit: 1,
    );

    if (results.isEmpty) {
      throw Exception('Usuário não encontrado. Verifique seu e-mail.');
    }

    final row = results.first;
    final storedSalt = row['salt'] as String?;
    final storedHash = row['password_hash'] as String?;

    if (storedHash == null || storedSalt == null) {
      throw Exception('Esta conta foi criada com o Google. Por favor, clique em "Continuar com o Google".');
    }

    // 2. Valida a senha usando o salt criptográfico
    final isValid = CryptoService.verifyPassword(
      password: password,
      salt: storedSalt,
      storedHash: storedHash,
    );

    if (!isValid) {
      throw Exception('Senha incorreta.');
    }

    return _mapRowToUserModel(row, db);
  }

  @override
  Future<UserModel> signInWithGoogle(GoogleAuthResult result) async {
    final db = await DatabaseService.database;
    final normalizedEmail = result.email.trim().toLowerCase();
    final emailHash = CryptoService.searchHash(normalizedEmail);

    // Verifica se já existe um usuário cadastrado com esse e-mail ou google_id
    final existing = await db.query(
      'users',
      where: 'email_hash = ? OR google_id = ?',
      whereArgs: [emailHash, result.googleId],
      limit: 1,
    );

    final now = DateTime.now();

    if (existing.isNotEmpty) {
      // Usuário já existe: atualiza o token do YouTube/Google e loga diretamente
      final row = existing.first;
      final userId = row['id'] as String;

      await db.update(
        'users',
        {
          'google_id': result.googleId,
          'youtube_token_encrypted': CryptoService.encrypt(result.accessToken),
          if (result.avatarUrl != null)
            'avatar_url_encrypted': CryptoService.encrypt(result.avatarUrl!),
        },
        where: 'id = ?',
        whereArgs: [userId],
      );

      await _saveActiveSession(db, userId);

      // Recarrega os dados atualizados
      final updated = await db.query('users', where: 'id = ?', whereArgs: [userId], limit: 1);
      return _mapRowToUserModel(updated.first, db);
    } else {
      // Novo usuário criando conta diretamente pelo Google
      final userId = 'usr_g_${now.millisecondsSinceEpoch}';

      await db.insert('users', {
        'id': userId,
        'name_encrypted': CryptoService.encrypt(result.name),
        'email_encrypted': CryptoService.encrypt(normalizedEmail),
        'email_hash': emailHash,
        'password_hash': null,
        'salt': null,
        'google_id': result.googleId,
        'avatar_url_encrypted': result.avatarUrl != null ? CryptoService.encrypt(result.avatarUrl!) : null,
        'auth_provider': 'google',
        'youtube_token_encrypted': CryptoService.encrypt(result.accessToken),
        'created_at': now.toIso8601String(),
      });

      await _saveActiveSession(db, userId);

      return UserModel(
        id: userId,
        name: result.name,
        email: normalizedEmail,
        googleId: result.googleId,
        avatarUrl: result.avatarUrl,
        authProvider: 'google',
        youtubeToken: result.accessToken,
        createdAt: now,
      );
    }
  }

  @override
  Future<UserModel> linkGoogleAccount({
    required String userId,
    required GoogleAuthResult result,
  }) async {
    final db = await DatabaseService.database;

    await db.update(
      'users',
      {
        'google_id': result.googleId,
        'youtube_token_encrypted': CryptoService.encrypt(result.accessToken),
        if (result.avatarUrl != null)
          'avatar_url_encrypted': CryptoService.encrypt(result.avatarUrl!),
      },
      where: 'id = ?',
      whereArgs: [userId],
    );

    final updated = await db.query('users', where: 'id = ?', whereArgs: [userId], limit: 1);
    return _mapRowToUserModel(updated.first, db);
  }

  @override
  Future<void> unlinkGoogleAccount({required String userId}) async {
    final db = await DatabaseService.database;
    await db.update(
      'users',
      {
        'google_id': null,
        'youtube_token_encrypted': null,
      },
      where: 'id = ?',
      whereArgs: [userId],
    );
  }

  @override
  Future<UserModel?> getCurrentUser() async {
    final db = await DatabaseService.database;

    final session = await db.query(
      'sessions',
      where: 'id = ?',
      whereArgs: ['active_session'],
      limit: 1,
    );

    if (session.isEmpty) return null;

    final userId = session.first['user_id'] as String;

    final userRows = await db.query(
      'users',
      where: 'id = ?',
      whereArgs: [userId],
      limit: 1,
    );

    if (userRows.isEmpty) return null;
    return _mapRowToUserModel(userRows.first, db, saveSession: false);
  }

  @override
  Future<void> logout() async {
    final db = await DatabaseService.database;
    await db.delete('sessions', where: 'id = ?', whereArgs: ['active_session']);
  }

  Future<UserModel> _mapRowToUserModel(
    Map<String, dynamic> row,
    Database db, {
    bool saveSession = true,
  }) async {
    final name = CryptoService.decrypt(row['name_encrypted'] as String);
    final email = CryptoService.decrypt(row['email_encrypted'] as String);
    final youtubeEncrypted = row['youtube_token_encrypted'] as String?;
    final youtubeToken = youtubeEncrypted != null
        ? CryptoService.decrypt(youtubeEncrypted)
        : null;

    final avatarEncrypted = row['avatar_url_encrypted'] as String?;
    final avatarUrl = avatarEncrypted != null
        ? CryptoService.decrypt(avatarEncrypted)
        : null;

    final userId = row['id'] as String;

    if (saveSession) {
      await _saveActiveSession(db, userId);
    }

    return UserModel(
      id: userId,
      name: name,
      email: email,
      googleId: row['google_id'] as String?,
      avatarUrl: avatarUrl,
      authProvider: row['auth_provider'] as String? ?? 'email',
      youtubeToken: youtubeToken,
      createdAt: DateTime.parse(row['created_at'] as String),
    );
  }

  Future<void> _saveActiveSession(Database db, String userId) async {
    await db.insert(
      'sessions',
      {
        'id': 'active_session',
        'user_id': userId,
        'logged_in_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
