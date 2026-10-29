import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import 'google_connect_dialog.dart';

class AuthDialog extends StatefulWidget {
  const AuthDialog({super.key});

  @override
  State<AuthDialog> createState() => _AuthDialogState();
}

class _AuthDialogState extends State<AuthDialog> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Controllers Login
  final _loginEmailController = TextEditingController();
  final _loginPasswordController = TextEditingController();

  // Controllers Register
  final _registerNameController = TextEditingController();
  final _registerEmailController = TextEditingController();
  final _registerPasswordController = TextEditingController();
  final _registerConfirmPasswordController = TextEditingController();

  bool _obscurePassword = true;
  bool _connectYouTubeOnRegister = true; // Marcado por padrão para abrir a vinculação!

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _loginEmailController.dispose();
    _loginPasswordController.dispose();
    _registerNameController.dispose();
    _registerEmailController.dispose();
    _registerPasswordController.dispose();
    _registerConfirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);

    return Dialog(
      backgroundColor: const Color(0xFF161622),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 450,
        padding: const EdgeInsets.all(26),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Cabeçalho com Ícone
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF7B2CBF), Color(0xFFF72585)],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.lock_outline, color: Colors.white, size: 26),
                  ),
                  const SizedBox(width: 14),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'DaPlayer Auth',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Acesse sua conta ou crie uma nova',
                        style: TextStyle(
                          color: Color(0xFF00F5D4),
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // Botão de Login Direto com Google (Fluxo B)
              _buildGoogleButton(context),
              const SizedBox(height: 16),

              // Divisor com "OU"
              Row(
                children: [
                  const Expanded(child: Divider(color: Colors.white12)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      'OU COM E-MAIL',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.4),
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),
                  const Expanded(child: Divider(color: Colors.white12)),
                ],
              ),
              const SizedBox(height: 16),

              // Seletor de Abas (Entrar / Cadastrar)
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF222232),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TabBar(
                  controller: _tabController,
                  indicatorSize: TabBarIndicatorSize.tab,
                  dividerColor: Colors.transparent,
                  indicator: BoxDecoration(
                    color: const Color(0xFF7B2CBF),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white54,
                  tabs: const [
                    Tab(text: 'Entrar'),
                    Tab(text: 'Criar Conta'),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Mensagem de Erro
              if (auth.errorMessage != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.redAccent.withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: Colors.redAccent, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          auth.errorMessage!,
                          style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),

              // Conteúdo das Abas
              SizedBox(
                height: 310,
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildLoginForm(auth),
                    _buildRegisterForm(auth),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGoogleButton(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () async {
        Navigator.of(context).pop();
        await showDialog(
          context: context,
          builder: (ctx) => const GoogleConnectDialog(isDirectLogin: true),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFFEA4335),
              ),
              child: const Icon(Icons.play_arrow, color: Colors.white, size: 16),
            ),
            const SizedBox(width: 12),
            const Text(
              'Continuar com o Google / YouTube',
              style: TextStyle(
                color: Color(0xFF1F1F1F),
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoginForm(AuthProvider auth) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildTextField(
          controller: _loginEmailController,
          label: 'E-mail ou Usuário',
          icon: Icons.email_outlined,
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 12),
        _buildTextField(
          controller: _loginPasswordController,
          label: 'Senha',
          icon: Icons.key_outlined,
          obscureText: _obscurePassword,
          suffixIcon: IconButton(
            icon: Icon(
              _obscurePassword ? Icons.visibility_off : Icons.visibility,
              color: Colors.white38,
            ),
            onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
          ),
        ),
        const SizedBox(height: 16),

        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF7B2CBF),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: auth.isLoading ? null : () => _submitLogin(auth),
          child: auth.isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text(
                  'Entrar',
                  style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                ),
        ),
        const Spacer(),
        const Center(
          child: Text(
            '🔒 Seus dados são salvos criptografados localmente.',
            style: TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ),
      ],
    );
  }

  Widget _buildRegisterForm(AuthProvider auth) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildTextField(
            controller: _registerNameController,
            label: 'Seu Nome Completo',
            icon: Icons.person_outline,
          ),
          const SizedBox(height: 8),
          _buildTextField(
            controller: _registerEmailController,
            label: 'E-mail',
            icon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 8),
          _buildTextField(
            controller: _registerPasswordController,
            label: 'Senha (mínimo 6 dígitos)',
            icon: Icons.lock_outline,
            obscureText: _obscurePassword,
          ),
          const SizedBox(height: 8),
          _buildTextField(
            controller: _registerConfirmPasswordController,
            label: 'Confirmar Senha',
            icon: Icons.lock_clock_outlined,
            obscureText: _obscurePassword,
          ),
          const SizedBox(height: 8),

          // Checkbox para vincular conta do YouTube logo após criar a conta
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            activeColor: const Color(0xFF7B2CBF),
            title: const Text(
              'Abrir para vincular conta do YouTube logo após cadastrar',
              style: TextStyle(color: Color(0xFF00F5D4), fontSize: 11, fontWeight: FontWeight.w600),
            ),
            value: _connectYouTubeOnRegister,
            onChanged: (val) => setState(() => _connectYouTubeOnRegister = val ?? true),
          ),
          const SizedBox(height: 8),

          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF7B2CBF),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: auth.isLoading ? null : () => _submitRegister(auth),
            child: auth.isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text(
                    'Cadastrar e Prosseguir',
                    style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscureText = false,
    TextInputType keyboardType = TextInputType.text,
    Widget? suffixIcon,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      style: const TextStyle(color: Colors.white, fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white54, fontSize: 12),
        prefixIcon: Icon(icon, color: const Color(0xFF9D4EDD), size: 18),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: const Color(0xFF222232),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Future<void> _submitLogin(AuthProvider auth) async {
    final email = _loginEmailController.text.trim();
    final password = _loginPasswordController.text;

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Preencha e-mail e senha')),
      );
      return;
    }

    final success = await auth.login(email, password);
    if (success && mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Bem-vindo de volta, ${auth.currentUser?.name}!'),
          backgroundColor: const Color(0xFF7B2CBF),
        ),
      );
    }
  }

  Future<void> _submitRegister(AuthProvider auth) async {
    final name = _registerNameController.text.trim();
    final email = _registerEmailController.text.trim();
    final password = _registerPasswordController.text;
    final confirmPassword = _registerConfirmPasswordController.text;

    if (name.isEmpty || email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor, preencha todos os campos')),
      );
      return;
    }

    if (password.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('A senha deve ter pelo menos 6 caracteres')),
      );
      return;
    }

    if (password != confirmPassword) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('As senhas não coincidem')),
      );
      return;
    }

    final success = await auth.register(name, email, password);
    if (success && mounted) {
      Navigator.of(context).pop(); // Fecha o modal de cadastro

      if (_connectYouTubeOnRegister) {
        // Abre imediatamente o modal para vincular a conta do Google/YouTube!
        await showDialog(
          context: context,
          builder: (ctx) => const GoogleConnectDialog(isDirectLogin: false),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Conta criada com sucesso e salva criptografada! Olá, $name!'),
            backgroundColor: const Color(0xFF7B2CBF),
          ),
        );
      }
    }
  }
}
