import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'package:audio_service/audio_service.dart';

import 'services/youtube_service.dart';
import 'services/tray_service.dart';
import 'services/audio_player_service.dart';
import 'services/playlist_service.dart';
import 'services/mobile_audio_handler.dart';
import 'repositories/auth_repository.dart';
import 'providers/auth_provider.dart';
import 'services/database_service.dart';
import 'screens/main_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  DatabaseService.initialize();

  final ytService = YouTubeService();
  final trayService = TrayService();
  final playerService = AudioPlayerService(
    ytService: ytService,
    trayService: trayService,
  );
  final playlistService = PlaylistService();

  // Configuração para Mobile (Android e iOS) - MediaSession & Tela de Bloqueio
  if (Platform.isAndroid || Platform.isIOS) {
    try {
      final audioHandler = await AudioService.init(
        builder: () => DaPlayerAudioHandler(
          onPlay: playerService.resume,
          onPause: playerService.pause,
          onNext: playerService.next,
          onPrevious: playerService.previous,
          onSeek: playerService.seek,
        ),
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'com.daplayer.daplayer.channel.audio',
          androidNotificationChannelName: 'DaPlayer Reprodução',
          androidNotificationChannelDescription: 'Controles de reprodução de música',
          androidNotificationOngoing: true,
          androidStopForegroundOnPause: true,
          androidNotificationIcon: 'mipmap/ic_launcher',
          notificationColor: Color(0xFF9D4EDD),
        ),
      );
      playerService.attachMobileHandler(audioHandler);
    } catch (e) {
      debugPrint('Erro ao inicializar AudioService: $e');
    }
  }

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

    // Impede o fechamento total imediato para esconder na bandeja
    await windowManager.setPreventClose(true);

    // Conecta a bandeja para restaurar ou ocultar a janela
    await trayService.initTray(
      onPlayPause: playerService.togglePlayPause,
      onNext: playerService.next,
      onPrevious: playerService.previous,
      onTrayClick: () async {
        final isVisible = await windowManager.isVisible();
        if (isVisible) {
          await windowManager.hide();
        } else {
          await windowManager.show();
          await windowManager.focus();
        }
      },
      onOpenFullPlayer: () async {
        await windowManager.show();
        await windowManager.focus();
      },
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

  // Intercepta quando o usuário clica no "X" para minimizar para a bandeja
  @override
  void onWindowClose() async {
    await windowManager.hide();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DaPlayer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0F0F17),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF9D4EDD),
          secondary: Color(0xFFF72585),
          surface: Color(0xFF161622),
        ),
        fontFamily: 'Roboto',
        useMaterial3: true,
      ),
      home: const MainScreen(),
    );
  }
}
