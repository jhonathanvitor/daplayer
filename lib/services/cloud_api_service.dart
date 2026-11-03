import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/playlist.dart';

/// Modelo de status de assinatura do usuário vindo da API
class SubscriptionStatus {
  final String plan; // 'free', 'pro', 'premium'
  final bool isActive;
  final DateTime? expiresAt;
  final int maxPlaylists; // -1 = ilimitado

  const SubscriptionStatus({
    this.plan = 'free',
    this.isActive = false,
    this.expiresAt,
    this.maxPlaylists = 5,
  });

  bool get isPremium => isActive && plan != 'free';

  factory SubscriptionStatus.fromMap(Map<String, dynamic> map) {
    return SubscriptionStatus(
      plan: (map['plan'] ?? 'free') as String,
      isActive: (map['is_active'] ?? false) as bool,
      expiresAt: map['expires_at'] != null
          ? DateTime.tryParse(map['expires_at'] as String)
          : null,
      maxPlaylists: (map['max_playlists'] ?? 5) as int,
    );
  }
}

/// Serviço pronto para conectar o DaPlayer à sua futura API REST
/// (Sincronização de Playlists na Nuvem + Controle de Assinatura)
class CloudApiService {
  static const _tokenKey = 'daplayer_cloud_jwt_token';
  static const _apiUrlKey = 'daplayer_cloud_api_url';

  /// Pode ser passado via `--dart-define=API_BASE_URL=https://sua-api.com/api/v1`
  static const String _envBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: '',
  );

  String? _authToken;
  String _baseUrl = _envBaseUrl;

  bool get isConfigured => _baseUrl.trim().isNotEmpty;
  bool get isAuthenticated => _authToken != null && _authToken!.isNotEmpty;
  String get baseUrl => _baseUrl;

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _authToken = prefs.getString(_tokenKey);
    final savedUrl = prefs.getString(_apiUrlKey);
    if (savedUrl != null && savedUrl.trim().isNotEmpty) {
      _baseUrl = savedUrl.trim();
    }
  }

  Future<void> setAuthToken(String? token) async {
    _authToken = token;
    final prefs = await SharedPreferences.getInstance();
    if (token == null || token.isEmpty) {
      await prefs.remove(_tokenKey);
    } else {
      await prefs.setString(_tokenKey, token);
    }
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (_authToken != null && _authToken!.isNotEmpty)
          'Authorization': 'Bearer $_authToken',
      };

  /// 1. Sincroniza todas as playlists locais com o banco de dados da API
  /// Endpoint esperado: PUT /playlists/sync
  Future<bool> syncPlaylistsToCloud(List<Playlist> playlists) async {
    if (!isConfigured || !isAuthenticated) return false;
    try {
      final uri = Uri.parse('$_baseUrl/playlists/sync');
      final response = await http.put(
        uri,
        headers: _headers,
        body: json.encode({
          'playlists': playlists.map((p) => p.toMap()).toList(),
          'synced_at': DateTime.now().toIso8601String(),
        }),
      );
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      debugPrint('Erro ao sincronizar playlists na nuvem: $e');
      return false;
    }
  }

  /// 2. Busca as playlists salvas pelo usuário na nuvem
  /// Endpoint esperado: GET /playlists
  Future<List<Playlist>?> fetchPlaylistsFromCloud() async {
    if (!isConfigured || !isAuthenticated) return null;
    try {
      final uri = Uri.parse('$_baseUrl/playlists');
      final response = await http.get(uri, headers: _headers);
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final list = data['playlists'] as List<dynamic>? ?? [];
        return list
            .map((item) => Playlist.fromMap(item as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      debugPrint('Erro ao buscar playlists da nuvem: $e');
    }
    return null;
  }

  /// 3. Consulta o status da assinatura do usuário logado
  /// Endpoint esperado: GET /subscriptions/status
  Future<SubscriptionStatus> getSubscriptionStatus() async {
    if (!isConfigured || !isAuthenticated) {
      return const SubscriptionStatus();
    }
    try {
      final uri = Uri.parse('$_baseUrl/subscriptions/status');
      final response = await http.get(uri, headers: _headers);
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        return SubscriptionStatus.fromMap(data);
      }
    } catch (e) {
      debugPrint('Erro ao verificar assinatura: $e');
    }
    return const SubscriptionStatus();
  }

  /// 4. Gera o link de pagamento / checkout para assinar um plano
  /// Endpoint esperado: POST /subscriptions/checkout
  Future<String?> createCheckoutUrl(String planId) async {
    if (!isConfigured || !isAuthenticated) return null;
    try {
      final uri = Uri.parse('$_baseUrl/subscriptions/checkout');
      final response = await http.post(
        uri,
        headers: _headers,
        body: json.encode({'plan_id': planId}),
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        return data['checkout_url'] as String?;
      }
    } catch (e) {
      debugPrint('Erro ao gerar checkout de assinatura: $e');
    }
    return null;
  }
}
