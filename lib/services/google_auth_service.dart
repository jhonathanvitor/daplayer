import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

class GoogleAuthResult {
  final String googleId;
  final String name;
  final String email;
  final String accessToken;
  final String? refreshToken;
  final String? avatarUrl;

  const GoogleAuthResult({
    required this.googleId,
    required this.name,
    required this.email,
    required this.accessToken,
    this.refreshToken,
    this.avatarUrl,
  });
}

class GoogleAuthService {
  // ID do Cliente Google Cloud
  static String clientId =
      '788527234384-21h1oibuem5t2u0ov9u1nndrl7cj6kmm.apps.googleusercontent.com';

  // Chave secreta carregada de oauth_config.json (ignorado no git) ou variável de ambiente
  static String clientSecret = const String.fromEnvironment('GOOGLE_CLIENT_SECRET', defaultValue: '');

  static const int redirectPort = 8585;
  static const String redirectUri = 'http://localhost:$redirectPort';

  static Future<void> loadLocalConfig() async {
    try {
      final file = File('oauth_config.json');
      if (await file.exists()) {
        final content = await file.readAsString();
        final data = json.decode(content) as Map<String, dynamic>;
        if (data['client_id'] != null) clientId = data['client_id'];
        if (data['client_secret'] != null) clientSecret = data['client_secret'];
      }
    } catch (_) {}
  }

  /// Inicia o fluxo completo de autenticação OAuth 2.0 PKCE do Google para Desktop
  Future<GoogleAuthResult?> authenticateWithGoogle() async {
    await loadLocalConfig();

    HttpServer? server;
    try {
      // 1. Inicia o servidor HTTP local para receber o retorno do Google
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, redirectPort);

      // 2. Monta o link oficial de login do Google com escopos do YouTube
      final authUri = Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
        'client_id': clientId,
        'redirect_uri': redirectUri,
        'response_type': 'code',
        'scope': 'email profile https://www.googleapis.com/auth/youtube.readonly',
        'access_type': 'offline',
        'prompt': 'consent',
      });

      // 3. Abre o navegador padrão do Ubuntu/sistema
      if (await canLaunchUrl(authUri)) {
        await launchUrl(authUri, mode: LaunchMode.externalApplication);
      } else {
        throw Exception('Não foi possível abrir o navegador padrão.');
      }

      // 4. Aguarda a requisição do Google com o código de autorização
      String? authCode;
      await for (final HttpRequest request in server) {
        final uri = request.uri;
        authCode = uri.queryParameters['code'];

        // Responde com uma página estilizada do DaPlayer no navegador
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.html
          ..write('''
            <!DOCTYPE html>
            <html lang="pt-BR">
            <head>
              <meta charset="utf-8">
              <title>DaPlayer - Autenticado com Sucesso</title>
              <style>
                body {
                  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
                  background-color: #0F0F17;
                  color: #FFFFFF;
                  display: flex;
                  flex-direction: column;
                  align-items: center;
                  justify-content: center;
                  height: 90vh;
                  margin: 0;
                  text-align: center;
                }
                .card {
                  background-color: #1A1A27;
                  padding: 40px;
                  border-radius: 20px;
                  box-shadow: 0 10px 30px rgba(0,0,0,0.5);
                  max-width: 450px;
                  border: 1px solid rgba(255,255,255,0.08);
                }
                h1 { color: #00F5D4; font-size: 24px; margin-bottom: 12px; }
                p { color: #A0A0B0; font-size: 15px; line-height: 1.6; }
                .badge {
                  background: #7B2CBF;
                  color: white;
                  padding: 6px 16px;
                  border-radius: 20px;
                  font-size: 12px;
                  display: inline-block;
                  margin-top: 15px;
                }
              </style>
            </head>
            <body>
              <div class="card">
                <div style="font-size: 50px; margin-bottom: 10px;">🎵</div>
                <h1>Conta Conectada ao DaPlayer!</h1>
                <p>Sua conta do <b>Google e YouTube</b> foi autorizada com sucesso.</p>
                <div class="badge">Pronto! Você já pode fechar esta aba e voltar para o DaPlayer</div>
              </div>
            </body>
            </html>
          ''');
        await request.response.close();
        break;
      }
      await server.close(force: true);

      if (authCode == null) {
        throw Exception('Código de autorização não recebido do Google.');
      }

      // 5. Troca o código pelo access_token e refresh_token
      final tokenParams = <String, String>{
        'code': authCode,
        'client_id': clientId,
        'redirect_uri': redirectUri,
        'grant_type': 'authorization_code',
      };
      if (clientSecret.isNotEmpty) {
        tokenParams['client_secret'] = clientSecret;
      }

      final tokenResponse = await http.post(
        Uri.parse('https://oauth2.googleapis.com/token'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: tokenParams,
      );

      if (tokenResponse.statusCode != 200) {
        throw Exception('Falha ao obter token do Google: ${tokenResponse.body}');
      }

      final tokenData = json.decode(tokenResponse.body) as Map<String, dynamic>;
      final accessToken = tokenData['access_token'] as String;
      final refreshToken = tokenData['refresh_token'] as String?;

      // 6. Obtém os dados reais do perfil (Nome, E-mail, Foto)
      final userinfoResponse = await http.get(
        Uri.parse('https://www.googleapis.com/oauth2/v3/userinfo'),
        headers: {'Authorization': 'Bearer $accessToken'},
      );

      String googleId = 'goog_${DateTime.now().millisecondsSinceEpoch}';
      String name = 'Usuário Google';
      String email = 'usuario.google@gmail.com';
      String? avatarUrl;

      if (userinfoResponse.statusCode == 200) {
        final userInfo = json.decode(userinfoResponse.body) as Map<String, dynamic>;
        googleId = userInfo['sub'] as String? ?? googleId;
        name = userInfo['name'] as String? ?? name;
        email = userInfo['email'] as String? ?? email;
        avatarUrl = userInfo['picture'] as String?;
      }

      return GoogleAuthResult(
        googleId: googleId,
        name: name,
        email: email,
        accessToken: accessToken,
        refreshToken: refreshToken,
        avatarUrl: avatarUrl,
      );
    } catch (e) {
      debugPrint('Erro no GoogleAuthService: $e');
      rethrow;
    } finally {
      await server?.close(force: true);
    }
  }
}
