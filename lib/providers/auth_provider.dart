import 'package:flutter/foundation.dart';
import '../models/user_model.dart';
import '../repositories/auth_repository.dart';
import '../services/google_auth_service.dart';

class AuthProvider extends ChangeNotifier {
  final AuthRepository _repository;
  final GoogleAuthService _googleAuthService = GoogleAuthService();

  UserModel? _currentUser;
  bool _isLoading = false;
  String? _errorMessage;

  UserModel? get currentUser => _currentUser;
  bool get isAuthenticated => _currentUser != null;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  AuthProvider({required AuthRepository repository}) : _repository = repository {
    checkCurrentUser();
  }

  Future<void> checkCurrentUser() async {
    _setLoading(true);
    try {
      _currentUser = await _repository.getCurrentUser();
    } catch (e) {
      debugPrint('Erro ao verificar usuário logado: $e');
    } finally {
      _setLoading(false);
    }
  }

  Future<bool> login(String email, String password) async {
    _setLoading(true);
    _errorMessage = null;
    try {
      _currentUser = await _repository.login(email: email, password: password);
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      notifyListeners();
      return false;
    } finally {
      _setLoading(false);
    }
  }

  Future<bool> register(String name, String email, String password) async {
    _setLoading(true);
    _errorMessage = null;
    try {
      _currentUser = await _repository.register(
        name: name,
        email: email,
        password: password,
      );
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      notifyListeners();
      return false;
    } finally {
      _setLoading(false);
    }
  }

  /// Fluxo B: Login ou Cadastro direto com a conta Google / YouTube
  Future<bool> signInWithGoogle() async {
    _setLoading(true);
    _errorMessage = null;
    try {
      final googleResult = await _googleAuthService.authenticateWithGoogle();
      if (googleResult == null) {
        _errorMessage = 'Autenticação com Google cancelada ou indisponível.';
        notifyListeners();
        return false;
      }

      _currentUser = await _repository.signInWithGoogle(googleResult);
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      notifyListeners();
      return false;
    } finally {
      _setLoading(false);
    }
  }

  /// Fluxo A: Usuário cadastrado por e-mail/senha vincula sua conta do Google/YouTube
  Future<bool> linkGoogleAccount() async {
    if (_currentUser == null) return false;
    _setLoading(true);
    _errorMessage = null;
    try {
      final googleResult = await _googleAuthService.authenticateWithGoogle();
      if (googleResult == null) {
        _errorMessage = 'Não foi possível vincular a conta do Google.';
        notifyListeners();
        return false;
      }

      _currentUser = await _repository.linkGoogleAccount(
        userId: _currentUser!.id,
        result: googleResult,
      );
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      notifyListeners();
      return false;
    } finally {
      _setLoading(false);
    }
  }

  /// Desvincular conta do Google/YouTube
  Future<void> unlinkGoogleAccount() async {
    if (_currentUser == null) return;
    _setLoading(true);
    try {
      await _repository.unlinkGoogleAccount(userId: _currentUser!.id);
      _currentUser = _currentUser!.copyWith(
        youtubeToken: '',
        googleId: '',
      );
      notifyListeners();
    } catch (e) {
      debugPrint('Erro ao desvincular Google: $e');
    } finally {
      _setLoading(false);
    }
  }

  Future<void> logout() async {
    _setLoading(true);
    try {
      await _repository.logout();
      _currentUser = null;
    } catch (e) {
      debugPrint('Erro ao deslogar: $e');
    } finally {
      _setLoading(false);
    }
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }
}
