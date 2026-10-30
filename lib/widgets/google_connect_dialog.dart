import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';

class GoogleConnectDialog extends StatefulWidget {
  final bool isDirectLogin;

  const GoogleConnectDialog({
    super.key,
    this.isDirectLogin = false,
  });

  @override
  State<GoogleConnectDialog> createState() => _GoogleConnectDialogState();
}

class _GoogleConnectDialogState extends State<GoogleConnectDialog> {
  bool _isConnecting = false;
  String? _statusText;

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);

    return Dialog(
      backgroundColor: const Color(0xFF161622),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 460),
        width: MediaQuery.of(context).size.width,
        padding: const EdgeInsets.all(22),
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
                        'Acesse suas playlists e coletâneas do YouTube',
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Card Informativo
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF222232),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white10),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.verified_user, color: Color(0xFF00F5D4), size: 16),
                      SizedBox(width: 8),
                      Text(
                        'OAuth 2.0 Oficial do Google Ativo',
                        style: TextStyle(
                          color: Color(0xFF00F5D4),
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Ao clicar no botão abaixo, seu navegador abrirá a tela oficial de autorização do Google para permitir que o DaPlayer leia suas playlists.',
                    style: TextStyle(color: Colors.white70, fontSize: 11, height: 1.5),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Status ou Erro
            if (_statusText != null)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF7B2CBF).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF7B2CBF).withValues(alpha: 0.5)),
                ),
                child: Row(
                  children: [
                    if (_isConnecting)
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    else
                      const Icon(Icons.info_outline, color: Colors.white70, size: 16),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _statusText!,
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),

            // Botão Principal para Disparar o OAuth no Navegador
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7B2CBF),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _isConnecting ? null : () => _startOAuth(auth),
              icon: _isConnecting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.open_in_browser, color: Colors.white, size: 20),
              label: Text(
                _isConnecting
                  ? 'Aguardando login no navegador...'
                  : widget.isDirectLogin
                      ? 'Abrir Navegador e Fazer Login'
                      : 'Abrir Navegador e Autorizar YouTube',
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

  Future<void> _startOAuth(AuthProvider auth) async {
    setState(() {
      _isConnecting = true;
      _statusText = 'Abrindo navegador... Faça login com sua conta do Google e autorize o DaPlayer.';
    });

    try {
      bool success;
      if (widget.isDirectLogin) {
        success = await auth.signInWithGoogle();
      } else {
        success = await auth.linkGoogleAccount();
      }

      if (mounted) {
        if (success) {
          Navigator.of(context).pop(true);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                widget.isDirectLogin
                    ? 'Login com Google concluído! Bem-vindo, ${auth.currentUser?.name}!'
                    : 'Conta do YouTube conectada com sucesso!',
              ),
              backgroundColor: const Color(0xFF7B2CBF),
            ),
          );
        } else {
          setState(() {
            _isConnecting = false;
            _statusText = auth.errorMessage ?? 'Não foi possível concluir a autenticação.';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isConnecting = false;
          _statusText = 'Erro ao autenticar: $e';
        });
      }
    }
  }
}
