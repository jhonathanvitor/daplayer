import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppThemePalette {
  final String id;
  final String name;
  final String subtitle;
  final IconData icon;
  final Color scaffoldBg;
  final Color sidebarBg;
  final Color headerBg;
  final Color cardBg;
  final Color tileBg;
  final Color activeTileBg;
  final Color primary;
  final Color primaryLight;
  final Color accent;
  final Color gradientEnd;

  const AppThemePalette({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.icon,
    required this.scaffoldBg,
    required this.sidebarBg,
    required this.headerBg,
    required this.cardBg,
    required this.tileBg,
    required this.activeTileBg,
    required this.primary,
    required this.primaryLight,
    required this.accent,
    required this.gradientEnd,
  });

  ThemeData toThemeData() {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: scaffoldBg,
      colorScheme: ColorScheme.dark(
        primary: primaryLight,
        secondary: gradientEnd,
        tertiary: accent,
        surface: sidebarBg,
      ),
      fontFamily: 'Roboto',
      useMaterial3: true,
    );
  }
}

class ThemeProvider extends ChangeNotifier {
  static const _storageKey = 'daplayer_selected_theme';

  static const List<AppThemePalette> themes = [
    AppThemePalette(
      id: 'neon_purple',
      name: 'Neon Roxo (Padrão)',
      subtitle: 'Roxo vibrante com detalhes em ciano e magenta',
      icon: Icons.auto_awesome,
      scaffoldBg: Color(0xFF0F0F17),
      sidebarBg: Color(0xFF161622),
      headerBg: Color(0xFF12121B),
      cardBg: Color(0xFF1E1E2C),
      tileBg: Color(0xFF161622),
      activeTileBg: Color(0xFF261D3A),
      primary: Color(0xFF7B2CBF),
      primaryLight: Color(0xFF9D4EDD),
      accent: Color(0xFF00F5D4),
      gradientEnd: Color(0xFFF72585),
    ),
    AppThemePalette(
      id: 'emerald_green',
      name: 'Esmeralda Musical',
      subtitle: 'Verde escuro elegante inspirado em estúdios',
      icon: Icons.eco,
      scaffoldBg: Color(0xFF0A110D),
      sidebarBg: Color(0xFF111C16),
      headerBg: Color(0xFF0D1611),
      cardBg: Color(0xFF17261E),
      tileBg: Color(0xFF111C16),
      activeTileBg: Color(0xFF193526),
      primary: Color(0xFF159947),
      primaryLight: Color(0xFF1ED760),
      accent: Color(0xFF64DFDF),
      gradientEnd: Color(0xFF00B4D8),
    ),
    AppThemePalette(
      id: 'cyber_ocean',
      name: 'Oceano Cyber',
      subtitle: 'Tons profundos de azul oceânico e turquesa',
      icon: Icons.waves,
      scaffoldBg: Color(0xFF080F1A),
      sidebarBg: Color(0xFF0E1829),
      headerBg: Color(0xFF0B1321),
      cardBg: Color(0xFF15233B),
      tileBg: Color(0xFF0E1829),
      activeTileBg: Color(0xFF182F4F),
      primary: Color(0xFF0077B6),
      primaryLight: Color(0xFF00B4D8),
      accent: Color(0xFF90E0EF),
      gradientEnd: Color(0xFF4361EE),
    ),
    AppThemePalette(
      id: 'ruby_sunset',
      name: 'Rubi Sunset',
      subtitle: 'Vermelho intenso com brilho dourado de pôr do sol',
      icon: Icons.local_fire_department,
      scaffoldBg: Color(0xFF140B0E),
      sidebarBg: Color(0xFF1F1115),
      headerBg: Color(0xFF180D11),
      cardBg: Color(0xFF2B181E),
      tileBg: Color(0xFF1F1115),
      activeTileBg: Color(0xFF3B1C26),
      primary: Color(0xFFD62839),
      primaryLight: Color(0xFFFF4D6D),
      accent: Color(0xFFFFB703),
      gradientEnd: Color(0xFFFB8500),
    ),
    AppThemePalette(
      id: 'imperial_gold',
      name: 'Ouro Imperial',
      subtitle: 'Acabamento escuro premium com dourado clássico',
      icon: Icons.workspace_premium,
      scaffoldBg: Color(0xFF11100C),
      sidebarBg: Color(0xFF1A1812),
      headerBg: Color(0xFF15130E),
      cardBg: Color(0xFF242118),
      tileBg: Color(0xFF1A1812),
      activeTileBg: Color(0xFF332D1D),
      primary: Color(0xFFB8860B),
      primaryLight: Color(0xFFE6C253),
      accent: Color(0xFFFFD166),
      gradientEnd: Color(0xFFD4AF37),
    ),
    AppThemePalette(
      id: 'amoled_midnight',
      name: 'AMOLED Preto Puro',
      subtitle: 'Contraste máximo e economia de bateria em telas OLED',
      icon: Icons.dark_mode,
      scaffoldBg: Color(0xFF000000),
      sidebarBg: Color(0xFF09090E),
      headerBg: Color(0xFF050508),
      cardBg: Color(0xFF12121A),
      tileBg: Color(0xFF09090E),
      activeTileBg: Color(0xFF1E1430),
      primary: Color(0xFF6D28D9),
      primaryLight: Color(0xFFA855F7),
      accent: Color(0xFF38BDF8),
      gradientEnd: Color(0xFFEC4899),
    ),
  ];

  AppThemePalette _current = themes.first;
  AppThemePalette get current => _current;

  ThemeProvider() {
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedId = prefs.getString(_storageKey);
      if (savedId != null) {
        final match = themes.where((t) => t.id == savedId);
        if (match.isNotEmpty) {
          _current = match.first;
          notifyListeners();
        }
      }
    } catch (_) {}
  }

  Future<void> setTheme(String themeId) async {
    final match = themes.where((t) => t.id == themeId);
    if (match.isEmpty) return;
    _current = match.first;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey, themeId);
    } catch (_) {}
  }
}
