import 'dart:ffi';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqlite3/open.dart';
import 'package:daplayer/services/crypto_service.dart';
import 'package:daplayer/services/database_service.dart';
import 'package:daplayer/services/google_auth_service.dart';
import 'package:daplayer/repositories/auth_repository.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class FakePathProviderPlatform extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  @override
  Future<String?> getApplicationSupportPath() async {
    return Directory.systemTemp.createTempSync('daplayer_test_').path;
  }
}

void main() {
  setUpAll(() {
    if (Platform.isLinux) {
      open.overrideFor(OperatingSystem.linux, () {
        final candidates = [
          '/usr/lib/x86_64-linux-gnu/libsqlite3.so.0',
          '/usr/lib/aarch64-linux-gnu/libsqlite3.so.0',
          '${Platform.environment['HOME']}/.local/lib/libsqlite3.so',
          'libsqlite3.so.0',
          'libsqlite3.so',
        ];
        for (final candidate in candidates) {
          try {
            return DynamicLibrary.open(candidate);
          } catch (_) {}
        }
        return DynamicLibrary.open('libsqlite3.so');
      });
    }
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    PathProviderPlatform.instance = FakePathProviderPlatform();
  });

  tearDownAll(() async {
    await DatabaseService.close();
  });

  group('CryptoService Tests', () {
    test('Encrypt and Decrypt should match original text', () {
      const original = 'jhonathan@email.com';
      final encrypted = CryptoService.encrypt(original);

      expect(encrypted, isNot(equals(original)));
      final decrypted = CryptoService.decrypt(encrypted);
      expect(decrypted, equals(original));
    });

    test('Password Hashing with Salt should verify correctly', () {
      const password = 'MinhaSenhaSegura123';
      final salt = CryptoService.generateSalt();
      final hash = CryptoService.hashPassword(password, salt);

      final isValid = CryptoService.verifyPassword(
        password: password,
        salt: salt,
        storedHash: hash,
      );
      expect(isValid, isTrue);

      final isWrongValid = CryptoService.verifyPassword(
        password: 'SenhaErrada',
        salt: salt,
        storedHash: hash,
      );
      expect(isWrongValid, isFalse);
    });
  });

  group('LocalSqliteAuthRepository Tests', () {
    final repo = LocalSqliteAuthRepository();

    test('Fluxo A: Cadastro por E-mail + Vinculação Posterior do YouTube', () async {
      const name = 'Jhonathan Developer';
      const email = 'jhonathan@example.com';
      const password = 'SenhaSecreta2026';

      // 1. Cadastra normal
      final user = await repo.register(
        name: name,
        email: email,
        password: password,
      );

      expect(user.isYouTubeConnected, isFalse);
      expect(user.authProvider, equals('email'));

      // 2. Vincula com o Google/YouTube posteriormente
      const googleResult = GoogleAuthResult(
        googleId: 'goog_12345',
        name: 'Jhonathan YouTube',
        email: 'jhonathan@example.com',
        accessToken: 'ya29.token_super_secreto',
      );

      final linkedUser = await repo.linkGoogleAccount(
        userId: user.id,
        result: googleResult,
      );

      expect(linkedUser.isYouTubeConnected, isTrue);
      expect(linkedUser.youtubeToken, equals('ya29.token_super_secreto'));

      // Inspeciona o SQLite para garantir que o token do YouTube foi salvo criptografado!
      final db = await DatabaseService.database;
      final rawRows = await db.query('users', where: 'id = ?', whereArgs: [user.id]);
      expect(rawRows.first['youtube_token_encrypted'], isNot(contains('ya29.token_super_secreto')));
    });

    test('Fluxo B: Cadastro/Login Direto com o Google/YouTube', () async {
      const googleResult = GoogleAuthResult(
        googleId: 'goog_99999',
        name: 'Maria Google',
        email: 'maria.google@gmail.com',
        accessToken: 'ya29.maria_token_youtube',
        avatarUrl: 'https://lh3.googleusercontent.com/avatar.jpg',
      );

      // Entra direto com o Google
      final user = await repo.signInWithGoogle(googleResult);

      expect(user.name, equals('Maria Google'));
      expect(user.email, equals('maria.google@gmail.com'));
      expect(user.authProvider, equals('google'));
      expect(user.isYouTubeConnected, isTrue);
      expect(user.youtubeToken, equals('ya29.maria_token_youtube'));

      // Garante que o SQLite gravou sem necessidade de senha tradicional
      final db = await DatabaseService.database;
      final rawRows = await db.query('users', where: 'id = ?', whereArgs: [user.id]);
      expect(rawRows.first['password_hash'], isNull);
      expect(rawRows.first['auth_provider'], equals('google'));
    });
  });
}
