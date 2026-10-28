import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';
import '../services/audio_player_service.dart';
import '../services/playlist_service.dart';

class FloatingMiniPlayer extends StatelessWidget {
  final VoidCallback onExpandToFull;
  final VoidCallback onCloseToTray;

  const FloatingMiniPlayer({
    super.key,
    required this.onExpandToFull,
    required this.onCloseToTray,
  });

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final playerService = Provider.of<AudioPlayerService>(context);
    final playlistService = Provider.of<PlaylistService>(context);
    final track = playerService.currentTrack;

    final isFavorite = track != null &&
        playlistService.playlists.any(
          (pl) => pl.id == 'default_collection' && pl.tracks.any((t) => t.id == track.id),
        );

    return Material(
      color: Colors.transparent,
      child: Center(
        child: Container(
          width: 420,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          decoration: BoxDecoration(
            color: const Color(0xFF1B1B1E), // Preto fosco idêntico ao modelo.webp
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.65),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
            border: Border.all(color: Colors.white.withValues(alpha: 0.08), width: 1),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Linha Superior: Nome da Música (Discreto) e Botão Fechar para Bandeja
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      track != null
                          ? '${track.title} • ${track.artist}'
                          : 'DaPlayer • Nenhuma música selecionada',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: onCloseToTray,
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.all(2.0),
                      child: Icon(
                        Icons.close,
                        size: 14,
                        color: Colors.white.withValues(alpha: 0.4),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Barra de Progresso Fina Idêntica ao modelo.webp
              ProgressBar(
                progress: playerService.position,
                total: playerService.duration,
                buffered: playerService.position,
                progressBarColor: Colors.white,
                baseBarColor: Colors.white.withValues(alpha: 0.25),
                bufferedBarColor: Colors.white.withValues(alpha: 0.35),
                thumbColor: Colors.white,
                barHeight: 2.8,
                thumbRadius: 5.5,
                thumbGlowRadius: 10.0,
                timeLabelLocation: TimeLabelLocation.none,
                onSeek: (duration) {
                  playerService.seek(duration);
                },
              ),
              const SizedBox(height: 4),

              // Rótulos de Tempo Abaixo da Barra (Esquerda: 02:59 | Direita: 04:38)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _formatDuration(playerService.position),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                  Text(
                    _formatDuration(playerService.duration),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Linha de Controles: Menu ☰ | Voltar | Play/Pause Circular Branco | Avançar | Coração ♥
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // 1. Ícone Menu (3 Barras) -> Restaura janela principal
                  IconButton(
                    icon: const Icon(Icons.menu, color: Colors.white, size: 24),
                    tooltip: 'Abrir DaPlayer Completo',
                    onPressed: onExpandToFull,
                  ),

                  // 2. Ícone Voltar Música |◀
                  IconButton(
                    icon: const Icon(Icons.skip_previous, color: Colors.white, size: 28),
                    tooltip: 'Música Anterior',
                    onPressed: () => playerService.previous(),
                  ),

                  // 3. Botão Play/Pause Central Branco com Ícone Preto
                  GestureDetector(
                    onTap: () => playerService.togglePlayPause(),
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black26,
                            blurRadius: 8,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Center(
                        child: playerService.isLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: Colors.black,
                                ),
                              )
                            : Icon(
                                playerService.isPlaying ? Icons.pause : Icons.play_arrow,
                                color: Colors.black,
                                size: 28,
                              ),
                      ),
                    ),
                  ),

                  // 4. Ícone Avançar Música ▶|
                  IconButton(
                    icon: const Icon(Icons.skip_next, color: Colors.white, size: 28),
                    tooltip: 'Próxima Música',
                    onPressed: () => playerService.next(),
                  ),

                  // 5. Ícone Coração (Favoritos) ♥
                  IconButton(
                    icon: Icon(
                      isFavorite ? Icons.favorite : Icons.favorite_border,
                      color: isFavorite ? const Color(0xFFF72585) : Colors.white,
                      size: 24,
                    ),
                    tooltip: isFavorite ? 'Remover dos Favoritos' : 'Adicionar aos Favoritos',
                    onPressed: () async {
                      if (track != null) {
                        if (isFavorite) {
                          await playlistService.removeTrackFromPlaylist('default_collection', track.id);
                        } else {
                          await playlistService.addTrackToPlaylist('default_collection', track);
                        }
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
