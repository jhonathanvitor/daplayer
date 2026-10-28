import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;

class CryptoService {
  // Chave AES-256 de 32 bytes (256 bits) e IV de 16 bytes (128 bits)
  static final enc.Key _aesKey = enc.Key.fromUtf8('DaPlayer@2026#SecureMusicMaster!');
  static final enc.IV _aesIv = enc.IV.fromUtf8('DaPlayerIV#2026!');

  /// Criptografa um texto em claro com AES-256
  static String encrypt(String plainText) {
    if (plainText.isEmpty) return '';
    final encrypter = enc.Encrypter(enc.AES(_aesKey, mode: enc.AESMode.cbc));
    final encrypted = encrypter.encrypt(plainText, iv: _aesIv);
    return encrypted.base64;
  }

  /// Descriptografa um texto cifrado em Base64 de volta para texto em claro
  static String decrypt(String base64Cipher) {
    if (base64Cipher.isEmpty) return '';
    try {
      final encrypter = enc.Encrypter(enc.AES(_aesKey, mode: enc.AESMode.cbc));
      return encrypter.decrypt64(base64Cipher, iv: _aesIv);
    } catch (e) {
      return '';
    }
  }

  /// Gera um salt criptográfico aleatório para a senha
  static String generateSalt([int length = 32]) {
    final random = Random.secure();
    final values = List<int>.generate(length, (i) => random.nextInt(256));
    return base64Url.encode(values);
  }

  /// Gera um hash SHA-256 salgado para a senha (armazenamento seguro unidirecional)
  static String hashPassword(String password, String salt) {
    final bytes = utf8.encode(password + salt);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Hash determinístico de busca rápida (para buscar email sem descriptografar tabela inteira)
  static String searchHash(String input) {
    final normalized = input.trim().toLowerCase();
    return sha256.convert(utf8.encode('search_salt_$normalized')).toString();
  }

  /// Verifica se uma senha confere com o hash salgado armazenado
  static bool verifyPassword({
    required String password,
    required String salt,
    required String storedHash,
  }) {
    final computed = hashPassword(password, salt);
    return computed == storedHash;
  }
}
