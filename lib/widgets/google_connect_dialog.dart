import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/auth_provider.dart';

class GoogleConnectDialog extends StatefulWidget {
  final bool isDirectLogin; // true = login direto com Google, false = vincular conta existente

  const GoogleConnectDialog({
    super.key,
    this.isDirectLogin = false,
  });

  @override
  State<GoogleConnectDialog> createState() => _GoogleConnectDialogState();
}

class _GoogleConnectDialogState extends State<GoogleConnectDialog> {
  final _emailController = TextEditingController(text: 'usuario.google@gmail.com');
  bool _openedBrowser = false;
  bool _isConnecting = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _openGoogleOAuth() async {
    final authUrl = Uri.parse(
      'https://accounts.google.com/o/oauth2/v2/auth'
      '?client_id=daplayer-app'
      '&redirect_uri=http://localhost:8080/callback'
      '&response_type=token'
      '&scope=https://www.googleapis.com/auth/youtube.readonly%20email%20profile',
    );

    try {
      if (await canLaunchUrl(authUrl)) {
        await launchUrl(authUrl, mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      // Ignora erro de lançamento de browser se não houver handler
    }

    setState(() {
      _openedBrowser = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);

    return Dialog(
      backgroundColor: const Color(0xFF161622),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 460,
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Cabeçalho Google / YouTube
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.play_circle_fill, color: Colors.redAccent, size: 32),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.isDirectLogin
                            ? 'Entrar com o Google'
                            : 'Vincular Conta do YouTube',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Acesse suas playlists e vídeos favoritos',
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF222232),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.security, color: Color(0xFF00F5D4), size: 16),
                      SizedBox(width: 8),
                      Text(
                        'Permissões Seguras (Somente Leitura)',
                        style: TextStyle(
                          color: Color(0xFF00F5D4),
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '• Visualizar suas playlists e coletâneas do YouTube\n'
                    '• Obter suas músicas curtidas e canais inscritos\n'
                    '• Seus tokens são criptografados com AES-256 no SQLite',
                    style: TextStyle(color: Colors.white70, fontSize: 11, height: 1.5),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // Botão para abrir o Navegador do Sistema com Google Accounts
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFF4285F4)),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: _openGoogleOAuth,
              icon: const Icon(Icons.open_in_browser, color: Color(0xFF4285F4), size: 20),
              label: Text(
                _openedBrowser
                    ? 'Navegador Aberto (Clique para reabrir)'
                    : 'Abrir Autorização no Navegador Google',
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
            const SizedBox(height: 14),

            // Campo de E-mail Google da Conta
            TextField(
              controller: _emailController,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                labelText: 'Conta Google / E-mail do YouTube',
                labelStyle: const TextStyle(color: Colors.white54, fontSize: 12),
                prefixIcon: const Icon(Icons.account_circle, color: Colors.white38),
                filled: true,
                fillColor: const Color(0xFF1E1E2C),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Botão de Conectar
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7B2CBF),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _isConnecting ? null : () => _confirmGoogleConnection(auth),
              child: _isConnecting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Text(
                      widget.isDirectLogin
                          ? 'Concluir Login com Google'
                          : 'Confirmar e Vincular YouTube',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
            const SizedBox(height: 8),

            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancelar', style: TextStyle(color: Colors.white38, fontSize: 12)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmGoogleConnection(AuthProvider auth) async {
    setState(() => _isConnecting = true);

    final email = _emailController.text.trim().isNotEmpty
        ? _emailController.text.trim()
        : 'usuario.google@gmail.com';

    bool success;
    if (widget.isDirectLogin) {
      success = await auth.signInWithGoogle();
    } else {
      success = await auth.linkGoogleAccount();
    }

    if (mounted) {
      setState(() => _isConnecting = false);
      if (success) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.isDirectLogin
                  ? 'Login realizado com sucesso! YouTube ativado para $email.'
                  : 'Conta do YouTube vinculada com sucesso a $email!',
            ),
            backgroundColor: const Color(0xFF7B2CBF),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(auth.errorMessage ?? 'Erro ao conectar conta do Google.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }
}
