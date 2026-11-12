import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/track.dart';
import '../models/playlist.dart';
import '../services/audio_player_service.dart';
import '../services/download_service.dart';
import '../services/playlist_service.dart';
import '../services/youtube_service.dart';
import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';
import '../widgets/bottom_player_bar.dart';
import '../widgets/add_to_playlist_dialog.dart';
import '../widgets/auth_dialog.dart';
import '../widgets/import_by_url_dialog.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  static const _recentSearchesKey = 'daplayer_recent_searches';
  static const _deepLinkChannel = MethodChannel('com.daplayer.daplayer/deeplink');
  final TextEditingController _searchController = TextEditingController();
  final YouTubeService _ytService = YouTubeService();

  int _selectedTabIndex = 0;
  List<Track> _searchResults = [];
  List<Track> _trendingTracks = [];
  List<String> _recentSearches = [];
  bool _isSearching = false;
  bool _isLoadingTrending = true;
  String? _lastHandledShareCode;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadRecentSearches();
    _loadTrending();
    _initDeepLinks();
  }

  Future<void> _initDeepLinks() async {
    _deepLinkChannel.setMethodCallHandler((call) async {
      if (call.method == 'onSharedText') {
        final text = call.arguments as String?;
        if (text != null && text.trim().isNotEmpty) {
          await _handleIncomingSharedText(text.trim());
        }
      }
    });

    try {
      final initialText = await _deepLinkChannel.invokeMethod<String>('getInitialSharedText');
      if (initialText != null && initialText.trim().isNotEmpty) {
        await _handleIncomingSharedText(initialText.trim());
      }
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkClipboardForSharedPlaylist();
    }
  }

  Future<void> _checkClipboardForSharedPlaylist() async {
    try {
      final data = await Clipboard.getData('text/plain');
      final text = data?.text?.trim();
      if (text == null || text.isEmpty) return;
      if (!PlaylistService.isShareCode(text)) return;

      final match = RegExp(r'(?:daplayer://playlist/|[?&]daplayer=)([A-Za-z0-9_\-=]+)')
          .firstMatch(text);
      if (match == null) return;
      final token = match.group(1)!;
      if (_lastHandledShareCode == token) return;
      _lastHandledShareCode = token;

      final decoded = PlaylistService.decodeShareCode(text);
      if (decoded == null || decoded.tracks.isEmpty || !mounted) return;

      final playlistService = Provider.of<PlaylistService>(context, listen: false);
      // Se já tiver uma coletânea com exatamente o mesmo nome e quantidade, ignora
      if (playlistService.playlists.any(
        (p) => p.name == decoded.name && p.tracks.length == decoded.tracks.length,
      )) {
        return;
      }

      final palette = Provider.of<ThemeProvider>(context, listen: false).current;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: palette.cardBg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.library_music, color: palette.accent),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Coletânea Compartilhada Detectada',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: Text(
            'Deseja importar a coletânea "${decoded.name}" (${decoded.tracks.length} músicas) que está na sua área de transferência?',
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Agora não', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: palette.primary),
              onPressed: () async {
                Navigator.of(ctx).pop();
                await playlistService.addPlaylist(decoded);
                if (mounted) {
                  setState(() => _selectedTabIndex = 2);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Coletânea "${decoded.name}" importada com ${decoded.tracks.length} músicas!',
                      ),
                      backgroundColor: palette.primary,
                    ),
                  );
                }
              },
              icon: const Icon(Icons.download_done, color: Colors.white, size: 18),
              label: const Text('Importar Coletânea', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
    } catch (_) {}
  }

  Future<void> _handleIncomingSharedText(String text) async {
    if (!mounted) return;
    final decoded = PlaylistService.decodeShareCode(text);
    if (decoded != null && decoded.tracks.isNotEmpty) {
      final playlistService = Provider.of<PlaylistService>(context, listen: false);
      final playerService = Provider.of<AudioPlayerService>(context, listen: false);
      await playlistService.addPlaylist(decoded);
      if (mounted) {
        setState(() => _selectedTabIndex = 2);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Coletânea "${decoded.name}" (${decoded.tracks.length} músicas) importada e iniciando reprodução!',
            ),
          ),
        );
      }
      await playerService.playPlaylist(decoded);
      return;
    }

    if (YouTubeService.isYouTubeUrl(text)) {
      _showImportByUrlDialog(context, initialUrl: text);
    }
  }

  Future<void> _loadRecentSearches() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList(_recentSearchesKey);
      if (saved != null && mounted) {
        setState(() {
          _recentSearches = saved;
        });
      }
    } catch (e) {
      debugPrint('Erro ao carregar histórico de buscas: $e');
    }
  }

  Future<void> _saveRecentSearch(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty ||
        YouTubeService.isYouTubeUrl(trimmed) ||
        PlaylistService.isShareCode(trimmed)) {
      return;
    }

    final updated = List<String>.from(_recentSearches)
      ..removeWhere((item) => item.toLowerCase() == trimmed.toLowerCase())
      ..insert(0, trimmed);

    if (updated.length > 15) {
      updated.removeRange(15, updated.length);
    }

    setState(() {
      _recentSearches = updated;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_recentSearchesKey, updated);
    } catch (e) {
      debugPrint('Erro ao salvar histórico de buscas: $e');
    }
  }

  Future<void> _removeRecentSearch(String query) async {
    final updated = List<String>.from(_recentSearches)..remove(query);
    setState(() {
      _recentSearches = updated;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_recentSearchesKey, updated);
    } catch (_) {}
  }

  Future<void> _clearRecentSearches() async {
    setState(() {
      _recentSearches = [];
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_recentSearchesKey);
    } catch (_) {}
  }

  Future<void> _loadTrending() async {
    setState(() => _isLoadingTrending = true);
    final results = await _ytService.getTrendingMusic();
    if (mounted) {
      setState(() {
        _trendingTracks = results;
        _isLoadingTrending = false;
      });
    }
  }

  Future<void> _performSearch(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;

    // Detecta código de coletânea compartilhada do DaPlayer
    if (PlaylistService.isShareCode(trimmed)) {
      _showImportByUrlDialog(context, initialUrl: trimmed);
      return;
    }

    // Detecta se o usuário colou diretamente um link do YouTube (Vídeo ou Playlist)
    if (YouTubeService.isYouTubeUrl(trimmed)) {
      final playlistId = YouTubeService.extractPlaylistId(trimmed);
      if (playlistId != null) {
        _showImportByUrlDialog(context, initialUrl: trimmed);
        return;
      }

      final videoId = YouTubeService.extractVideoId(trimmed);
      if (videoId != null) {
        setState(() {
          _isSearching = true;
          _selectedTabIndex = 1;
        });

        final track = await _ytService.getTrackFromUrl(trimmed);
        if (mounted) {
          setState(() {
            _searchResults = track != null ? [track] : [];
            _isSearching = false;
          });
        }
        return;
      }
    }

    _searchController.text = trimmed;
    await _saveRecentSearch(trimmed);

    setState(() {
      _isSearching = true;
      _selectedTabIndex = 1; // Alterna para a aba de resultados
    });

    final results = await _ytService.search(trimmed);
    if (mounted) {
      setState(() {
        _searchResults = results;
        _isSearching = false;
      });
    }
  }

  void _showImportByUrlDialog(BuildContext context, {String? initialPlaylistId, String? initialUrl}) {
    showDialog(
      context: context,
      builder: (ctx) => ImportByUrlDialog(
        initialPlaylistId: initialPlaylistId,
        initialUrl: initialUrl,
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    _ytService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final playerService = Provider.of<AudioPlayerService>(context, listen: false);
    // Observa apenas mudanças na faixa atual, play/pause ou estado de pré-carregamento/buffer
    context.select<AudioPlayerService, (String?, bool, bool)>(
      (s) => (s.currentTrack?.id, s.isPlaying, s.isBuffering),
    );
    final auth = Provider.of<AuthProvider>(context);
    final palette = Provider.of<ThemeProvider>(context).current;
    final isMobile = MediaQuery.of(context).size.width < 720;

    final mainContent = Column(
      children: [
        _buildTopHeader(auth, palette, isMobile: isMobile),
        Expanded(
          child: IndexedStack(
            index: _selectedTabIndex,
            children: [
              _buildTrendingView(playerService, palette, isMobile: isMobile),
              _buildSearchResultsView(playerService, palette, isMobile: isMobile),
              _buildMyPlaylistsView(playerService, palette, isMobile: isMobile),
            ],
          ),
        ),
        const BottomPlayerBar(),
      ],
    );

    return Scaffold(
      backgroundColor: palette.scaffoldBg,
      drawer: isMobile
          ? Drawer(
              backgroundColor: palette.sidebarBg,
              child: SafeArea(
                child: _buildSidebar(auth, palette, isDrawer: true),
              ),
            )
          : null,
      bottomNavigationBar: isMobile ? _buildMobileNavBar(palette) : null,
      body: isMobile
          ? SafeArea(child: mainContent)
          : Row(
              children: [
                _buildSidebar(auth, palette),
                Expanded(child: mainContent),
              ],
            ),
    );
  }

  Widget _buildMobileNavBar(AppThemePalette palette) {
    return BottomNavigationBar(
      backgroundColor: palette.sidebarBg,
      selectedItemColor: palette.primaryLight,
      unselectedItemColor: Colors.white54,
      currentIndex: _selectedTabIndex,
      onTap: (index) => setState(() => _selectedTabIndex = index),
      items: const [
        BottomNavigationBarItem(
          icon: Icon(Icons.explore_outlined),
          activeIcon: Icon(Icons.explore),
          label: 'Descobrir',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.search_outlined),
          activeIcon: Icon(Icons.search),
          label: 'Busca',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.library_music_outlined),
          activeIcon: Icon(Icons.library_music),
          label: 'Coletâneas',
        ),
      ],
    );
  }

  Widget _buildSidebar(AuthProvider auth, AppThemePalette palette, {bool isDrawer = false}) {
    return Container(
      width: isDrawer ? null : 250,
      color: palette.sidebarBg,
      child: Column(
        children: [
          const SizedBox(height: 32),
          // Logotipo do DaPlayer
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [palette.primary, palette.gradientEnd],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.music_note, color: Colors.white, size: 26),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'DaPlayer',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                  Text(
                    'Coletâneas MP3',
                    style: TextStyle(
                      color: palette.primaryLight,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 36),

          // Itens de Navegação
          _sidebarItem(
            index: 0,
            icon: Icons.explore_outlined,
            activeIcon: Icons.explore,
            title: 'Descobrir',
            palette: palette,
            isDrawer: isDrawer,
          ),
          _sidebarItem(
            index: 1,
            icon: Icons.search_outlined,
            activeIcon: Icons.search,
            title: 'Busca',
            palette: palette,
            isDrawer: isDrawer,
          ),
          _sidebarItem(
            index: 2,
            icon: Icons.library_music_outlined,
            activeIcon: Icons.library_music,
            title: 'Minhas Coletâneas',
            palette: palette,
            isDrawer: isDrawer,
          ),

          // Botão de Seletor de Temas na barra lateral / menu mobile
          ListTile(
            leading: Icon(Icons.palette_outlined, color: palette.accent),
            title: const Text(
              'Temas do App',
              style: TextStyle(color: Colors.white70),
            ),
            subtitle: Text(
              palette.name,
              style: TextStyle(color: palette.primaryLight, fontSize: 11),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            onTap: () {
              if (isDrawer) {
                Navigator.of(context).maybePop();
              }
              _showThemePickerDialog(context);
            },
          ),

          const Spacer(),

          // Card do Usuário (SQLite Criptografado)
          _buildUserProfileCard(auth, palette),

          const SizedBox(height: 8),

          // Indicador de Status de Segundo Plano
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: palette.cardBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white10),
            ),
            child: Row(
              children: [
                Icon(Icons.system_update_alt, color: palette.primaryLight, size: 16),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Minimiza para a bandeja do sistema',
                    style: TextStyle(color: Colors.white54, fontSize: 10),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildUserProfileCard(AuthProvider auth, AppThemePalette palette) {
    if (!auth.isAuthenticated) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: palette.cardBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: palette.primary.withValues(alpha: 0.3)),
        ),
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: palette.primary,
            minimumSize: const Size.fromHeight(38),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onPressed: () => _openAuthDialog(),
          icon: const Icon(Icons.person, color: Colors.white, size: 16),
          label: const Text('Entrar / Cadastrar', style: TextStyle(color: Colors.white, fontSize: 12)),
        ),
      );
    }

    final user = auth.currentUser!;
    final initials = user.name.trim().isNotEmpty
        ? user.name.trim()[0].toUpperCase()
        : 'U';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: palette.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: palette.primary,
                child: Text(
                  initials,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    Text(
                      user.email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.logout, color: Colors.white38, size: 18),
                tooltip: 'Sair da Conta',
                onPressed: () => auth.logout(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sidebarItem({
    required int index,
    required IconData icon,
    required IconData activeIcon,
    required String title,
    required AppThemePalette palette,
    bool isDrawer = false,
  }) {
    final isSelected = _selectedTabIndex == index;
    return ListTile(
      leading: Icon(
        isSelected ? activeIcon : icon,
        color: isSelected ? palette.primaryLight : Colors.white60,
      ),
      title: Text(
        title,
        style: TextStyle(
          color: isSelected ? Colors.white : Colors.white60,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      selected: isSelected,
      selectedTileColor: palette.activeTileBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      onTap: () {
        setState(() => _selectedTabIndex = index);
        if (isDrawer) {
          Navigator.of(context).maybePop();
        }
      },
    );
  }

  Widget _buildTopHeader(AuthProvider auth, AppThemePalette palette, {bool isMobile = false}) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 12 : 24,
        vertical: isMobile ? 10 : 16,
      ),
      color: palette.headerBg,
      child: Row(
        children: [
          if (isMobile) ...[
            Builder(
              builder: (ctx) => IconButton(
                icon: const Icon(Icons.menu, color: Colors.white70),
                onPressed: () => Scaffold.of(ctx).openDrawer(),
                tooltip: 'Menu',
              ),
            ),
            const SizedBox(width: 4),
          ],
          // Campo de Busca
          Expanded(
            child: Container(
              height: 46,
              decoration: BoxDecoration(
                color: palette.cardBg,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white10),
              ),
              child: TextField(
                controller: _searchController,
                style: const TextStyle(color: Colors.white),
                onTap: () {
                  if (_searchController.text.isEmpty && _recentSearches.isNotEmpty) {
                    setState(() => _selectedTabIndex = 1);
                  }
                },
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: isMobile
                      ? 'Buscar no YouTube...'
                      : 'Buscar músicas, coletâneas, artistas no YouTube...',
                  hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                  prefixIcon: IconButton(
                    icon: const Icon(Icons.search, color: Colors.white54, size: 20),
                    onPressed: () => _performSearch(_searchController.text),
                  ),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, color: Colors.white54, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            setState(() {
                              _searchResults = [];
                              _selectedTabIndex = 1;
                            });
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onSubmitted: _performSearch,
              ),
            ),
          ),
          if (isMobile) ...[
            const SizedBox(width: 2),
            IconButton(
              icon: Icon(Icons.palette_outlined, color: palette.primaryLight, size: 22),
              tooltip: 'Temas',
              onPressed: () => _showThemePickerDialog(context),
            ),
            IconButton(
              icon: Icon(Icons.link, color: palette.accent, size: 22),
              tooltip: 'Colar Link',
              onPressed: () => _showImportByUrlDialog(context),
            ),
            IconButton(
              icon: Icon(
                auth.isAuthenticated ? Icons.account_circle : Icons.person_outline,
                color: auth.isAuthenticated ? palette.accent : Colors.white70,
                size: 24,
              ),
              tooltip: auth.isAuthenticated ? auth.currentUser!.name : 'Entrar',
              onPressed: () => _openAuthDialog(),
            ),
          ] else ...[
            const SizedBox(width: 12),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: palette.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              ),
              onPressed: () => _performSearch(_searchController.text),
              icon: const Icon(Icons.search, color: Colors.white, size: 18),
              label: const Text('Buscar', style: TextStyle(color: Colors.white)),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: Icon(Icons.palette_outlined, color: palette.primaryLight),
              tooltip: 'Trocar Tema do App',
              onPressed: () => _showThemePickerDialog(context),
            ),
            const SizedBox(width: 4),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: palette.accent,
                side: BorderSide(color: palette.accent),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
              onPressed: () => _showImportByUrlDialog(context),
              icon: const Icon(Icons.link, size: 18),
              label: const Text('Colar Link', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 14),

            // Botão de Conta / Perfil Criptografado
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                side: BorderSide(
                  color: auth.isAuthenticated
                      ? palette.accent.withValues(alpha: 0.6)
                      : Colors.white24,
                ),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              onPressed: () => _openAuthDialog(),
              icon: Icon(
                auth.isAuthenticated ? Icons.verified_user : Icons.lock_outline,
                color: auth.isAuthenticated ? palette.accent : Colors.white70,
                size: 18,
              ),
              label: Text(
                auth.isAuthenticated ? auth.currentUser!.name : 'Entrar',
                style: TextStyle(
                  color: auth.isAuthenticated ? Colors.white : Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _openAuthDialog() {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    if (auth.isAuthenticated && auth.currentUser != null) {
      _showUserAccountDialog(context);
      return;
    }
    showDialog(
      context: context,
      builder: (ctx) => const AuthDialog(),
    );
  }

  void _showUserAccountDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) {
        final auth = Provider.of<AuthProvider>(ctx);
        final palette = Provider.of<ThemeProvider>(ctx).current;
        final user = auth.currentUser;
        if (user == null) {
          Navigator.of(ctx).pop();
          return const SizedBox.shrink();
        }
        final initials = user.name.trim().isNotEmpty
            ? user.name.trim()[0].toUpperCase()
            : 'U';

        return AlertDialog(
          backgroundColor: palette.cardBg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: palette.primary,
                child: Text(
                  initials,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      user.email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: palette.tileBg,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: palette.accent.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.verified_user, color: palette.accent, size: 18),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Sessão ativa • Conta sincronizada',
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  leading: Icon(Icons.library_music, color: palette.primaryLight),
                  title: const Text(
                    'Minhas Coletâneas',
                    style: TextStyle(color: Colors.white, fontSize: 14),
                  ),
                  subtitle: const Text(
                    'Acessar suas playlists salvas',
                    style: TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    setState(() => _selectedTabIndex = 2);
                  },
                ),
                const Divider(color: Colors.white12),
                const SizedBox(height: 4),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent.withValues(alpha: 0.2),
                    foregroundColor: Colors.redAccent,
                    side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.5)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () async {
                    Navigator.of(ctx).pop();
                    await auth.logout();
                  },
                  icon: const Icon(Icons.logout, size: 18),
                  label: const Text(
                    'Sair da Conta',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('Fechar', style: TextStyle(color: palette.accent)),
            ),
          ],
        );
      },
    );
  }

  void _showThemePickerDialog(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final currentId = themeProvider.current.id;

    showDialog(
      context: context,
      builder: (ctx) {
        final activePalette = Provider.of<ThemeProvider>(ctx).current;
        return AlertDialog(
          backgroundColor: activePalette.cardBg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Row(
            children: [
              Icon(Icons.palette, color: activePalette.primaryLight),
              const SizedBox(width: 10),
              const Text(
                'Escolher Tema do App',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: ThemeProvider.themes.map((t) {
                  final isSelected = t.id == activePalette.id || (t.id == currentId && t.id == activePalette.id);
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: t.tileBg,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isSelected ? t.primaryLight : Colors.white12,
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: ListTile(
                      leading: Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [t.primary, t.gradientEnd],
                          ),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(t.icon, color: Colors.white, size: 22),
                      ),
                      title: Text(
                        t.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      subtitle: Text(
                        t.subtitle,
                        style: const TextStyle(color: Colors.white60, fontSize: 11),
                      ),
                      trailing: isSelected
                          ? Icon(Icons.check_circle, color: t.accent, size: 24)
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircleAvatar(radius: 6, backgroundColor: t.primaryLight),
                                const SizedBox(width: 4),
                                CircleAvatar(radius: 6, backgroundColor: t.accent),
                              ],
                            ),
                      onTap: () => themeProvider.setTheme(t.id),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('Fechar', style: TextStyle(color: activePalette.accent)),
            ),
          ],
        );
      },
    );
  }

  // Visualização de Coletâneas / Tendências
  Widget _buildTrendingView(
    AudioPlayerService playerService,
    AppThemePalette palette, {
    bool isMobile = false,
  }) {
    if (_isLoadingTrending) {
      return Center(
        child: CircularProgressIndicator(color: palette.primaryLight),
      );
    }

    return ListView(
      padding: EdgeInsets.all(isMobile ? 14 : 24),
      children: [
        Text(
          '🔥 Coletâneas & Músicas em Destaque',
          style: TextStyle(
            color: Colors.white,
            fontSize: isMobile ? 18 : 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Toque em qualquer faixa para ouvir o áudio diretamente do YouTube em alta qualidade',
          style: TextStyle(color: Colors.white54, fontSize: 12),
        ),
        const SizedBox(height: 16),
        ..._trendingTracks.map((t) => _buildTrackTile(t, playerService, _trendingTracks, palette)),
      ],
    );
  }

  // Visualização de Resultados da Busca
  Widget _buildSearchResultsView(
    AudioPlayerService playerService,
    AppThemePalette palette, {
    bool isMobile = false,
  }) {
    if (_isSearching) {
      return Center(
        child: CircularProgressIndicator(color: palette.primaryLight),
      );
    }

    if (_searchResults.isEmpty) {
      if (_recentSearches.isEmpty) {
        return const Center(
          child: Padding(
            padding: EdgeInsets.all(24.0),
            child: Text(
              'Digite um termo de pesquisa para encontrar músicas e coletâneas.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white38, fontSize: 14),
            ),
          ),
        );
      }

      return ListView(
        padding: EdgeInsets.all(isMobile ? 14 : 24),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '🕒 Últimas Consultas',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: isMobile ? 16 : 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              TextButton.icon(
                onPressed: _clearRecentSearches,
                icon: const Icon(Icons.delete_sweep, color: Colors.white54, size: 18),
                label: const Text(
                  'Limpar tudo',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ..._recentSearches.map(
            (term) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: palette.tileBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
              ),
              child: ListTile(
                dense: true,
                leading: Icon(Icons.history, color: palette.primaryLight, size: 20),
                title: Text(
                  term,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.north_west, color: Colors.white38, size: 18),
                      tooltip: 'Preencher na busca',
                      onPressed: () {
                        setState(() {
                          _searchController.text = term;
                          _searchController.selection = TextSelection.fromPosition(
                            TextPosition(offset: term.length),
                          );
                        });
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white38, size: 18),
                      tooltip: 'Remover do histórico',
                      onPressed: () => _removeRecentSearch(term),
                    ),
                  ],
                ),
                onTap: () => _performSearch(term),
              ),
            ),
          ),
        ],
      );
    }

    return ListView(
      padding: EdgeInsets.all(isMobile ? 14 : 24),
      children: [
        if (_recentSearches.isNotEmpty) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '🕒 Últimas consultas',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              InkWell(
                onTap: _clearRecentSearches,
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                  child: Text(
                    'Limpar',
                    style: TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _recentSearches.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final term = _recentSearches[index];
                final isActive =
                    term.toLowerCase() == _searchController.text.trim().toLowerCase();
                return InputChip(
                  avatar: Icon(
                    Icons.history,
                    size: 15,
                    color: isActive ? Colors.white : palette.primaryLight,
                  ),
                  label: Text(
                    term,
                    style: TextStyle(
                      color: isActive ? Colors.white : Colors.white70,
                      fontSize: 12,
                    ),
                  ),
                  backgroundColor: isActive ? palette.primary : palette.cardBg,
                  side: BorderSide(
                    color: isActive ? palette.primaryLight : Colors.white12,
                  ),
                  deleteIcon: const Icon(Icons.close, size: 14, color: Colors.white54),
                  onDeleted: () => _removeRecentSearch(term),
                  onPressed: () => _performSearch(term),
                  visualDensity: VisualDensity.compact,
                );
              },
            ),
          ),
          const SizedBox(height: 16),
        ],
        Text(
          'Resultados da busca por "${_searchController.text}"',
          style: TextStyle(
            color: Colors.white,
            fontSize: isMobile ? 16 : 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 14),
        ..._searchResults.map((t) => _buildTrackTile(t, playerService, _searchResults, palette)),
      ],
    );
  }

  // Visualização de Minhas Coletâneas
  Widget _buildMyPlaylistsView(
    AudioPlayerService playerService,
    AppThemePalette palette, {
    bool isMobile = false,
  }) {
    final playlistService = Provider.of<PlaylistService>(context);
    final playlists = playlistService.playlists;

    return ListView(
      padding: EdgeInsets.all(isMobile ? 14 : 24),
      children: [
        if (isMobile) ...[
          const Text(
            '📁 Minhas Coletâneas',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: palette.accent,
                    side: BorderSide(color: palette.accent),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  onPressed: () => _showImportByUrlDialog(context),
                  icon: const Icon(Icons.link, size: 16),
                  label: const Text('Importar Link', style: TextStyle(fontSize: 12)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: palette.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  onPressed: () => _showCreatePlaylistDialog(playlistService, palette),
                  icon: const Icon(Icons.add, color: Colors.white, size: 16),
                  label: const Text('Nova Coletânea', style: TextStyle(color: Colors.white, fontSize: 12)),
                ),
              ),
            ],
          ),
        ] else ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '📁 Minhas Coletâneas',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Row(
                children: [
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: palette.accent,
                      side: BorderSide(color: palette.accent),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () => _showImportByUrlDialog(context),
                    icon: const Icon(Icons.link, size: 18),
                    label: const Text('Importar por Link'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: palette.primary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () => _showCreatePlaylistDialog(playlistService, palette),
                    icon: const Icon(Icons.add, color: Colors.white),
                    label: const Text('Nova Coletânea', style: TextStyle(color: Colors.white)),
                  ),
                ],
              ),
            ],
          ),
        ],
        const SizedBox(height: 16),
        if (playlists.isEmpty)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(40.0),
              child: Text(
                'Nenhuma coletânea criada ainda. Crie uma para organizar suas músicas!',
                style: TextStyle(color: Colors.white38),
              ),
            ),
          )
        else
          ...playlists.map(
            (pl) => _buildPlaylistCard(
              pl,
              playerService,
              playlistService,
              palette,
              isMobile: isMobile,
            ),
          ),
      ],
    );
  }

  Future<void> _handleDownloadPlaylist(
    Playlist playlist,
    DownloadService downloadService,
    AppThemePalette palette,
  ) async {
    final isAllDownloaded = downloadService.isPlaylistFullyDownloaded(playlist);
    if (isAllDownloaded) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Todas as ${playlist.tracks.length} músicas de "${playlist.name}" já estão baixadas offline!',
          ),
          backgroundColor: palette.primary,
        ),
      );
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Baixando coletânea "${playlist.name}" (${playlist.tracks.length} músicas) para ouvir offline...',
        ),
        backgroundColor: palette.primary,
      ),
    );
    final count = await downloadService.downloadPlaylist(playlist);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Coletânea "${playlist.name}" pronta offline ($count/${playlist.tracks.length} músicas baixadas)!',
        ),
        backgroundColor: palette.primary,
      ),
    );
  }

  Widget _buildPlaylistCard(
    Playlist playlist,
    AudioPlayerService playerService,
    PlaylistService playlistService,
    AppThemePalette palette, {
    bool isMobile = false,
  }) {
    final downloadService = Provider.of<DownloadService>(context);
    final downloadedCount = downloadService.getPlaylistDownloadedCount(playlist);
    final isAllDownloaded = downloadService.isPlaylistFullyDownloaded(playlist);
    final isDownloadingPl = downloadService.isDownloadingPlaylist(playlist.id);

    return Card(
      color: palette.cardBg,
      margin: const EdgeInsets.only(bottom: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ExpansionTile(
        tilePadding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 16, vertical: 4),
        leading: Container(
          width: isMobile ? 42 : 48,
          height: isMobile ? 42 : 48,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [palette.primary, palette.gradientEnd],
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(Icons.queue_music, color: Colors.white, size: isMobile ? 22 : 24),
        ),
        title: Text(
          playlist.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: isMobile ? 14 : 15,
          ),
        ),
        subtitle: Text(
          downloadedCount > 0
              ? '${playlist.tracks.length} músicas • $downloadedCount offline'
              : '${playlist.tracks.length} músicas',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: downloadedCount > 0 ? palette.accent : Colors.white54,
            fontSize: 12,
          ),
        ),
        trailing: isMobile
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isDownloadingPl)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: palette.accent,
                        ),
                      ),
                    )
                  else if (isAllDownloaded)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Icon(Icons.offline_pin, color: palette.accent, size: 18),
                    ),
                  if (playlist.tracks.isNotEmpty)
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                      icon: Icon(Icons.play_circle_fill, color: palette.primaryLight, size: 30),
                      tooltip: 'Reproduzir Coletânea',
                      onPressed: () => playerService.playPlaylist(playlist),
                    ),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, color: Colors.white70, size: 22),
                    color: palette.sidebarBg,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    onSelected: (action) {
                      switch (action) {
                        case 'download':
                          _handleDownloadPlaylist(playlist, downloadService, palette);
                          break;
                        case 'share':
                          _showSharePlaylistDialog(playlist, palette);
                          break;
                        case 'rename':
                          _showRenamePlaylistDialog(playlist, playlistService, palette);
                          break;
                        case 'add_link':
                          _showImportByUrlDialog(context, initialPlaylistId: playlist.id);
                          break;
                        case 'delete':
                          playlistService.deletePlaylist(playlist.id);
                          break;
                      }
                    },
                    itemBuilder: (ctx) => [
                      if (playlist.tracks.isNotEmpty)
                        PopupMenuItem(
                          value: 'download',
                          enabled: !isDownloadingPl,
                          child: Row(
                            children: [
                              Icon(
                                isAllDownloaded
                                    ? Icons.offline_pin
                                    : Icons.download_for_offline_outlined,
                                color: palette.accent,
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              Text(
                                isAllDownloaded
                                    ? 'Baixada Offline (100%)'
                                    : 'Baixar Coletânea Offline',
                                style: const TextStyle(color: Colors.white, fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                      const PopupMenuItem(
                        value: 'share',
                        child: Row(
                          children: [
                            Icon(Icons.share_outlined, color: Colors.white70, size: 20),
                            SizedBox(width: 10),
                            Text('Compartilhar Coletânea', style: TextStyle(color: Colors.white, fontSize: 13)),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'rename',
                        child: Row(
                          children: [
                            Icon(Icons.edit_outlined, color: Colors.white70, size: 20),
                            SizedBox(width: 10),
                            Text('Editar Nome', style: TextStyle(color: Colors.white, fontSize: 13)),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'add_link',
                        child: Row(
                          children: [
                            Icon(Icons.add_link, color: palette.accent, size: 20),
                            const SizedBox(width: 10),
                            const Text('Adicionar por Link', style: TextStyle(color: Colors.white, fontSize: 13)),
                          ],
                        ),
                      ),
                      const PopupMenuDivider(),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                            SizedBox(width: 10),
                            Text('Excluir Coletânea', style: TextStyle(color: Colors.redAccent, fontSize: 13)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (playlist.tracks.isNotEmpty)
                    IconButton(
                      icon: isDownloadingPl
                          ? SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: palette.accent,
                              ),
                            )
                          : Icon(
                              isAllDownloaded
                                  ? Icons.offline_pin
                                  : Icons.download_for_offline_outlined,
                              color: isAllDownloaded ? palette.accent : Colors.white70,
                              size: 21,
                            ),
                      tooltip: isDownloadingPl
                          ? 'Baixando coletânea ($downloadedCount/${playlist.tracks.length})...'
                          : isAllDownloaded
                              ? 'Coletânea 100% baixada offline'
                              : 'Baixar todas as músicas da coletânea offline',
                      onPressed: isDownloadingPl
                          ? null
                          : () => _handleDownloadPlaylist(playlist, downloadService, palette),
                    ),
                  IconButton(
                    icon: const Icon(Icons.share_outlined, color: Colors.white70, size: 20),
                    tooltip: 'Compartilhar Coletânea',
                    onPressed: () => _showSharePlaylistDialog(playlist, palette),
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, color: Colors.white70, size: 20),
                    tooltip: 'Editar Nome da Coletânea',
                    onPressed: () => _showRenamePlaylistDialog(playlist, playlistService, palette),
                  ),
                  IconButton(
                    icon: Icon(Icons.add_link, color: palette.accent, size: 22),
                    tooltip: 'Adicionar música por link',
                    onPressed: () => _showImportByUrlDialog(context, initialPlaylistId: playlist.id),
                  ),
                  if (playlist.tracks.isNotEmpty)
                    IconButton(
                      icon: Icon(Icons.play_circle_fill, color: palette.primaryLight, size: 32),
                      tooltip: 'Reproduzir Coletânea',
                      onPressed: () => playerService.playPlaylist(playlist),
                    ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 22),
                    tooltip: 'Excluir Coletânea',
                    onPressed: () => playlistService.deletePlaylist(playlist.id),
                  ),
                ],
              ),
        children: playlist.tracks.isEmpty
            ? [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      const Text(
                        'Coletânea vazia. ',
                        style: TextStyle(color: Colors.white38, fontSize: 12),
                      ),
                      TextButton.icon(
                        onPressed: () =>
                            _showImportByUrlDialog(context, initialPlaylistId: playlist.id),
                        icon: Icon(Icons.add_link, size: 16, color: palette.accent),
                        label: Text(
                          'Adicionar música por link',
                          style: TextStyle(color: palette.accent, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                )
              ]
            : playlist.tracks.map((track) {
                final isTrackDownloaded = downloadService.isDownloaded(track.id);
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 16),
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: CachedNetworkImage(
                      imageUrl: track.thumbnailUrl,
                      width: 40,
                      height: 40,
                      fit: BoxFit.cover,
                    ),
                  ),
                  title: Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                  subtitle: Text(
                    isTrackDownloaded ? '${track.artist} • Offline' : track.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isTrackDownloaded ? palette.accent : Colors.white54,
                      fontSize: 11,
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildDownloadTrackButton(
                        track,
                        downloadService,
                        palette,
                        iconSize: 19,
                        compact: true,
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        padding: const EdgeInsets.all(4),
                        icon: Icon(Icons.playlist_add, color: palette.primaryLight, size: 19),
                        tooltip: 'Incluir em outra Coletânea',
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (ctx) => AddToPlaylistDialog(track: track),
                          );
                        },
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        padding: const EdgeInsets.all(4),
                        icon: const Icon(Icons.remove_circle_outline, color: Colors.white38, size: 19),
                        tooltip: 'Remover desta Coletânea',
                        onPressed: () =>
                            playlistService.removeTrackFromPlaylist(playlist.id, track.id),
                      ),
                    ],
                  ),
                  onTap: () => playerService.playPlaylist(
                    playlist,
                    startIndex: playlist.tracks.indexOf(track),
                  ),
                );
              }).toList(),
      ),
    );
  }

  void _showSharePlaylistDialog(Playlist playlist, AppThemePalette palette) {
    final shareCode = PlaylistService.generateShareCode(playlist);
    final shareMessage = PlaylistService.generateShareMessage(playlist);
    final match = RegExp(r'(?:daplayer://playlist/|[?&]daplayer=)([A-Za-z0-9_\-=]+)')
        .firstMatch(shareCode);
    if (match != null) {
      _lastHandledShareCode = match.group(1);
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: palette.cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            Icon(Icons.share, color: palette.accent),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Compartilhar "${playlist.name}"',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Envie esta coletânea (${playlist.tracks.length} músicas) pelo WhatsApp! O link gerado é clicável: quem receber pode clicar direto no link para ouvir todas as músicas em sequência ou importar a coletânea inteira no DaPlayer!',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: palette.tileBg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white12),
                ),
                child: SelectableText(
                  shareCode,
                  maxLines: 3,
                  style: TextStyle(
                    color: palette.accent,
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF25D366),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: shareMessage));
                  final waUri = Uri.parse(
                    'https://wa.me/?text=${Uri.encodeComponent(shareMessage)}',
                  );
                  if (ctx.mounted) Navigator.of(ctx).pop();
                  await launchUrl(waUri, mode: LaunchMode.externalApplication);
                },
                icon: const Icon(Icons.send, color: Colors.white, size: 18),
                label: const Text(
                  'Enviar Direto no WhatsApp',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 10),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: palette.primary,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  await Clipboard.setData(ClipboardData(text: shareCode));
                  if (ctx.mounted) Navigator.of(ctx).pop();
                  messenger.showSnackBar(
                    SnackBar(
                      content: const Text(
                        'Link clicável da coletânea copiado!',
                      ),
                      backgroundColor: palette.primary,
                    ),
                  );
                },
                icon: const Icon(Icons.link, color: Colors.white, size: 18),
                label: const Text(
                  'Copiar Link Clicável da Coletânea',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: palette.accent,
                  side: BorderSide(color: palette.accent),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  await Clipboard.setData(ClipboardData(text: shareMessage));
                  if (ctx.mounted) Navigator.of(ctx).pop();
                  messenger.showSnackBar(
                    SnackBar(
                      content: const Text(
                        'Mensagem completa com links clicáveis copiada!',
                      ),
                      backgroundColor: palette.primary,
                    ),
                  );
                },
                icon: const Icon(Icons.chat_bubble_outline, size: 18),
                label: const Text(
                  'Copiar Lista com Links (WhatsApp / Telegram)',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Fechar', style: TextStyle(color: Colors.white54)),
          ),
        ],
      ),
    );
  }

  Widget _buildDownloadTrackButton(
    Track track,
    DownloadService downloadService,
    AppThemePalette palette, {
    double iconSize = 22,
    bool compact = false,
  }) {
    final isDownloading = downloadService.isDownloading(track.id);
    final isDownloaded = downloadService.isDownloaded(track.id);
    final progress = downloadService.getProgress(track.id);

    if (isDownloading) {
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 10),
        child: Tooltip(
          message: 'Baixando ${(progress * 100).round()}%...',
          child: SizedBox(
            width: iconSize,
            height: iconSize,
            child: CircularProgressIndicator(
              value: progress > 0.05 ? progress : null,
              strokeWidth: 2.2,
              color: palette.accent,
            ),
          ),
        ),
      );
    }

    if (isDownloaded) {
      return IconButton(
        visualDensity: compact ? VisualDensity.compact : null,
        constraints: compact ? const BoxConstraints(minWidth: 32, minHeight: 32) : null,
        padding: compact ? const EdgeInsets.all(4) : null,
        icon: Icon(Icons.offline_pin, color: palette.accent, size: iconSize),
        tooltip: 'Baixada no dispositivo (toca offline) • Clique para remover download',
        onPressed: () async {
          final confirm = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: palette.cardBg,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Text('Música Baixada Offline', style: TextStyle(color: Colors.white)),
              content: Text(
                '"${track.title}" já está salva no seu dispositivo e toca sempre sem gastar internet.\n\nDeseja remover o arquivo baixado?',
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Manter Offline', style: TextStyle(color: Colors.white60)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('Remover Download', style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
          );
          if (confirm == true) {
            await downloadService.removeDownload(track.id);
          }
        },
      );
    }

    return IconButton(
      visualDensity: compact ? VisualDensity.compact : null,
      constraints: compact ? const BoxConstraints(minWidth: 32, minHeight: 32) : null,
      padding: compact ? const EdgeInsets.all(4) : null,
      icon: Icon(Icons.download_for_offline_outlined, color: Colors.white70, size: iconSize),
      tooltip: 'Baixar música para ouvir offline',
      onPressed: () async {
        final messenger = ScaffoldMessenger.of(context);
        final ok = await downloadService.downloadTrack(track);
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              ok
                  ? '"${track.title}" baixada! Agora sempre tocará offline.'
                  : 'Não foi possível baixar "${track.title}".',
            ),
            backgroundColor: ok ? palette.primary : Colors.redAccent,
          ),
        );
      },
    );
  }

  void _showRenamePlaylistDialog(
    Playlist playlist,
    PlaylistService playlistService,
    AppThemePalette palette,
  ) {
    final nameCtrl = TextEditingController(text: playlist.name);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: palette.cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Editar Nome da Coletânea', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Novo nome da coletânea',
            hintStyle: const TextStyle(color: Colors.white38),
            filled: true,
            fillColor: palette.tileBg,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
          ),
          onSubmitted: (val) async {
            if (val.trim().isNotEmpty) {
              await playlistService.renamePlaylist(playlist.id, val.trim());
              if (ctx.mounted) Navigator.of(ctx).pop();
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: palette.primary,
            ),
            onPressed: () async {
              if (nameCtrl.text.trim().isNotEmpty) {
                await playlistService.renamePlaylist(playlist.id, nameCtrl.text.trim());
                if (ctx.mounted) Navigator.of(ctx).pop();
              }
            },
            child: const Text('Salvar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildTrackTile(
    Track track,
    AudioPlayerService playerService,
    List<Track> queue,
    AppThemePalette palette,
  ) {
    final downloadService = Provider.of<DownloadService>(context);
    final isCurrent = playerService.currentTrack?.id == track.id;
    final isDownloaded = downloadService.isDownloaded(track.id);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isCurrent ? palette.activeTileBg : palette.tileBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isCurrent ? palette.primaryLight : Colors.white.withValues(alpha: 0.04),
        ),
      ),
      child: ListTile(
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: CachedNetworkImage(
            imageUrl: track.thumbnailUrl,
            width: 52,
            height: 52,
            fit: BoxFit.cover,
            placeholder: (context, url) => Container(
              color: Colors.white10,
              child: const Icon(Icons.music_note, color: Colors.white30),
            ),
          ),
        ),
        title: Text(
          track.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: isCurrent ? palette.primaryLight : Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: isCurrent && playerService.isBuffering
            ? Text(
                'Pré-carregando áudio... • ${track.artist}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: palette.accent, fontSize: 12, fontWeight: FontWeight.w500),
              )
            : Text(
                isDownloaded ? '${track.artist} • Offline' : track.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isDownloaded ? palette.accent : Colors.white54,
                  fontSize: 12,
                ),
              ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildDownloadTrackButton(
              track,
              downloadService,
              palette,
              iconSize: 21,
              compact: true,
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
              padding: const EdgeInsets.all(4),
              icon: const Icon(Icons.playlist_add, color: Colors.white70, size: 22),
              tooltip: 'Adicionar à Coletânea',
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (ctx) => AddToPlaylistDialog(track: track),
                );
              },
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              padding: const EdgeInsets.all(4),
              icon: isCurrent && playerService.isBuffering
                  ? SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: palette.accent,
                      ),
                    )
                  : Icon(
                      isCurrent && playerService.isPlaying
                          ? Icons.pause_circle_filled
                          : Icons.play_circle_filled,
                      color: palette.primaryLight,
                      size: 30,
                    ),
              onPressed: () {
                if (isCurrent) {
                  playerService.togglePlayPause();
                } else {
                  playerService.playQueue(queue, startIndex: queue.indexOf(track));
                }
              },
            ),
          ],
        ),
        onTap: () {
          playerService.playQueue(queue, startIndex: queue.indexOf(track));
        },
      ),
    );
  }

  void _showCreatePlaylistDialog(PlaylistService playlistService, AppThemePalette palette) {
    final nameCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: palette.cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Criar Nova Coletânea', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Nome da coletânea (ex: Minhas Favoritas)',
            hintStyle: const TextStyle(color: Colors.white38),
            filled: true,
            fillColor: palette.tileBg,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: palette.primary,
            ),
            onPressed: () async {
              if (nameCtrl.text.trim().isNotEmpty) {
                await playlistService.createPlaylist(nameCtrl.text.trim());
                if (ctx.mounted) Navigator.of(ctx).pop();
              }
            },
            child: const Text('Criar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
