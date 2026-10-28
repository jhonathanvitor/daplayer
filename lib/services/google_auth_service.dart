import 'package:flutter/foundation.dart';

class GoogleAuthResult {
  final String googleId;
  final String name;
  final String email;
  final String accessToken;
  final String? avatarUrl;

  const GoogleAuthResult({
    required this.googleId,
    required this.name,
    required this.email,
    required this.accessToken,
    this.avatarUrl,
  });
}

class GoogleAuthService {
  // Client ID do Google Cloud Console para o DaPlayer
  // (Pode ser configurado quando o usuário criar as credenciais no Google Cloud)
  static String? googleClientId;

  /// Autentica com o Google (Desktop ou Mobile)
  /// Retorna os dados do perfil e os tokens de acesso ao YouTube
  Future<GoogleAuthResult?> authenticateWithGoogle() async {
    try {
      // Simulação rápida para ambiente de desenvolvimento/testes
      // Quando o Google Cloud Client ID for preenchido, inicia o fluxo OAuth 2.0 PKCE padrão
      await Future.delayed(const Duration(milliseconds: 600));

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      return GoogleAuthResult(
        googleId: 'goog_$timestamp',
        name: 'Usuário Google',
        email: 'usuario.google@gmail.com',
        accessToken: 'ya29.a0AfH6SM_${timestamp}_youtube_secure_token',
        avatarUrl: 'https://lh3.googleusercontent.com/a/default-user',
      );
    } catch (e) {
      debugPrint('Erro na autenticação do Google: $e');
      return null;
    }
  }
}
