import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import 'services/youtube_service.dart';
import 'services/tray_service.dart';
import 'services/audio_player_service.dart';
import 'services/playlist_service.dart';
import 'services/window_mode_service.dart';
import 'repositories/auth_repository.dart';
import 'providers/auth_provider.dart';
import 'screens/main_screen.dart';
import 'widgets/floating_mini_player.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final windowModeService = WindowModeService();
  final ytService = YouTubeService();
  final trayService = TrayService();
  final playerService = AudioPlayerService(
    ytService: ytService,
    trayService: trayService,
  );
  final playlistService = PlaylistService();

  // Configuração para Desktop (Linux, Windows, macOS)
  if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
    await windowManager.ensureInitialized();

    const windowOptions = WindowOptions(
      size: Size(1180, 750),
      minimumSize: Size(850, 580),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      title: 'DaPlayer',
    );

    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });

    // Impede o fechamento total imediato para esconder na bandeja ou mini player
    await windowManager.setPreventClose(true);

    // Conecta a bandeja aos modos de janela
    await trayService.initTray(
      onPlayPause: playerService.togglePlayPause,
      onNext: playerService.next,
      onPrevious: playerService.previous,
      onTrayClick: windowModeService.toggleMiniOrRestore,
      onOpenMiniPlayer: windowModeService.switchToMiniMode,
      onOpenFullPlayer: windowModeService.switchToFullMode,
    );
  }

  final authRepository = LocalSqliteAuthRepository();
  final authProvider = AuthProvider(repository: authRepository);

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AudioPlayerService>.value(value: playerService),
        ChangeNotifierProvider<PlaylistService>.value(value: playlistService),
        ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
        ChangeNotifierProvider<WindowModeService>.value(value: windowModeService),
      ],
      child: const DaPlayerApp(),
    ),
  );
}

class DaPlayerApp extends StatefulWidget {
  const DaPlayerApp({super.key});

  @override
  State<DaPlayerApp> createState() => _DaPlayerAppState();
}

class _DaPlayerAppState extends State<DaPlayerApp> with WindowListener {
  @override
  void initState() {
    super.initState();
    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      windowManager.addListener(this);
    }
  }

  @override
  void dispose() {
    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      windowManager.removeListener(this);
    }
    super.dispose();
  }

  // Intercepta quando o usuário clica no "X" ou minimiza
  @override
  void onWindowClose() async {
    final windowMode = Provider.of<WindowModeService>(context, listen: false);
    // Transforma no Mini Player Flutuante do modelo.webp
    await windowMode.switchToMiniMode();
  }

  @override
  Widget build(BuildContext context) {
    final windowMode = Provider.of<WindowModeService>(context);

    return MaterialApp(
      title: 'DaPlayer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: windowMode.isMiniMode
            ? Colors.transparent
            : const Color(0xFF0F0F17),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF9D4EDD),
          secondary: Color(0xFFF72585),
          surface: Color(0xFF161622),
        ),
        fontFamily: 'Roboto',
        useMaterial3: true,
      ),
      home: windowMode.isMiniMode
          ? FloatingMiniPlayer(
              onExpandToFull: windowMode.switchToFullMode,
              onCloseToTray: windowMode.hideToTray,
            )
          : const MainScreen(),
    );
  }
}
