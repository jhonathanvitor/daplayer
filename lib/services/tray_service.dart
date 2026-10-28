import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:system_tray/system_tray.dart';
import 'package:window_manager/window_manager.dart';

class TrayService {
  final SystemTray _systemTray = SystemTray();
  final Menu _menu = Menu();

  VoidCallback? onPlayPausePressed;
  VoidCallback? onNextPressed;
  VoidCallback? onPreviousPressed;
  VoidCallback? onTrayClick;
  VoidCallback? onOpenMiniPlayer;
  VoidCallback? onOpenFullPlayer;

  bool _initialized = false;
  String _currentTitle = 'Nenhuma música tocando';
  String _currentArtist = '';
  bool _isPlaying = false;

  Future<void> initTray({
    VoidCallback? onPlayPause,
    VoidCallback? onNext,
    VoidCallback? onPrevious,
    VoidCallback? onTrayClick,
    VoidCallback? onOpenMiniPlayer,
    VoidCallback? onOpenFullPlayer,
  }) async {
    if (!Platform.isLinux && !Platform.isWindows && !Platform.isMacOS) {
      return;
    }

    onPlayPausePressed = onPlayPause;
    onNextPressed = onNext;
    onPreviousPressed = onPrevious;
    this.onTrayClick = onTrayClick;
    this.onOpenMiniPlayer = onOpenMiniPlayer;
    this.onOpenFullPlayer = onOpenFullPlayer;

    try {
      final iconPath = Platform.isWindows ? 'assets/icon.ico' : 'assets/tray_icon.png';

      await _systemTray.initSystemTray(
        title: "DaPlayer",
        iconPath: iconPath,
        toolTip: "DaPlayer - Player de Coletâneas",
      );

      // Evento de clique no ícone da barra de sistema (abre o mini player flutuante)
      _systemTray.registerSystemTrayEventHandler((eventName) {
        if (eventName == kSystemTrayEventClick) {
          this.onTrayClick?.call();
        } else if (eventName == kSystemTrayEventRightClick) {
          _systemTray.popUpContextMenu();
        }
      });

      await _rebuildMenu();
      _initialized = true;
    } catch (e) {
      debugPrint('Aviso: Falha ao inicializar System Tray: $e');
    }
  }

  Future<void> updateTrayInfo({
    required String title,
    required String artist,
    required bool isPlaying,
  }) async {
    _currentTitle = title;
    _currentArtist = artist;
    _isPlaying = isPlaying;

    if (!_initialized) return;

    try {
      final tooltip = artist.isNotEmpty
          ? 'DaPlayer: $title - $artist'
          : 'DaPlayer: $title';
      await _systemTray.setToolTip(tooltip);
      await _rebuildMenu();
    } catch (e) {
      debugPrint('Erro ao atualizar bandeja do sistema: $e');
    }
  }

  Future<void> _rebuildMenu() async {
    final songLabel = _currentArtist.isNotEmpty
        ? '🎵 $_currentTitle ($_currentArtist)'
        : '🎵 $_currentTitle';

    await _menu.buildFrom([
      MenuItemLabel(label: songLabel, enabled: false),
      MenuSeparator(),
      MenuItemLabel(
        label: _isPlaying ? '⏸  Pausar' : '▶  Reproduzir',
        onClicked: (menuItem) => onPlayPausePressed?.call(),
      ),
      MenuItemLabel(
        label: '⏭  Próxima Faixa',
        onClicked: (menuItem) => onNextPressed?.call(),
      ),
      MenuItemLabel(
        label: '⏮  Faixa Anterior',
        onClicked: (menuItem) => onPreviousPressed?.call(),
      ),
      MenuSeparator(),
      MenuItemLabel(
        label: '📱  Mini Player Flutuante',
        onClicked: (menuItem) => onOpenMiniPlayer?.call(),
      ),
      MenuItemLabel(
        label: '🪟  Abrir DaPlayer Completo',
        onClicked: (menuItem) => onOpenFullPlayer?.call(),
      ),
      MenuSeparator(),
      MenuItemLabel(
        label: '❌  Encerrar DaPlayer',
        onClicked: (menuItem) {
          windowManager.destroy();
        },
      ),
    ]);

    await _systemTray.setContextMenu(_menu);
  }
}
