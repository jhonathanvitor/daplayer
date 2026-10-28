import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/audio_player_service.dart';
import '../services/window_mode_service.dart';

class BottomPlayerBar extends StatelessWidget {
  const BottomPlayerBar({super.key});

  @override
  Widget build(BuildContext context) {
    final playerService = Provider.of<AudioPlayerService>(context);
    final track = playerService.currentTrack;

    if (track == null) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF161622),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 15,
            offset: const Offset(0, -3),
          ),
        ],
        border: const Border(
          top: BorderSide(color: Color(0xFF2C2C40), width: 1),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Barra de Progresso Fina Branca (estilo modelo.webp)
            ProgressBar(
              progress: playerService.position,
              total: playerService.duration,
              buffered: playerService.position,
              progressBarColor: Colors.white,
              baseBarColor: Colors.white.withValues(alpha: 0.2),
              bufferedBarColor: Colors.white.withValues(alpha: 0.3),
              thumbColor: Colors.white,
              barHeight: 3.0,
              thumbRadius: 5.5,
              timeLabelTextStyle: const TextStyle(
                color: Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
              onSeek: (duration) {
                playerService.seek(duration);
              },
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                // Capa da Música
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedNetworkImage(
                    imageUrl: track.thumbnailUrl,
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(
                      width: 48,
                      height: 48,
                      color: Colors.white10,
                      child: const Icon(Icons.music_note, color: Colors.white30),
                    ),
                    errorWidget: (context, url, error) => Container(
                      width: 48,
                      height: 48,
                      color: Colors.white10,
                      child: const Icon(Icons.music_note, color: Colors.white30),
                    ),
                  ),
                ),
                const SizedBox(width: 14),

                // Título e Artista
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        track.artist,
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

                // Controles de Reprodução (Voltar, Play/Pause Central Branco, Próxima)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.skip_previous, color: Colors.white),
                      iconSize: 28,
                      tooltip: 'Música Anterior',
                      onPressed: () => playerService.previous(),
                    ),
                    const SizedBox(width: 6),
                    if (playerService.isLoading)
                      const SizedBox(
                        width: 44,
                        height: 44,
                        child: Padding(
                          padding: EdgeInsets.all(8.0),
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        ),
                      )
                    else
                      GestureDetector(
                        onTap: () => playerService.togglePlayPause(),
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black26,
                                blurRadius: 6,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Center(
                            child: Icon(
                              playerService.isPlaying ? Icons.pause : Icons.play_arrow,
                              color: Colors.black,
                              size: 26,
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(width: 6),
                    IconButton(
                      icon: const Icon(Icons.skip_next, color: Colors.white),
                      iconSize: 28,
                      tooltip: 'Próxima Música',
                      onPressed: () => playerService.next(),
                    ),
                  ],
                ),

                const SizedBox(width: 24),

                // Controle de Volume
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      playerService.volume == 0
                          ? Icons.volume_off
                          : playerService.volume < 0.5
                              ? Icons.volume_down
                              : Icons.volume_up,
                      color: Colors.white54,
                      size: 20,
                    ),
                    SizedBox(
                      width: 90,
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                          trackHeight: 3,
                          activeTrackColor: Colors.white,
                          inactiveTrackColor: Colors.white12,
                          thumbColor: Colors.white,
                        ),
                        child: Slider(
                          value: playerService.volume,
                          min: 0.0,
                          max: 1.0,
                          onChanged: (val) => playerService.setVolume(val),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(width: 14),

                // Botão para Minimizar para o Mini Player Flutuante (estilo modelo.webp)
                IconButton(
                  icon: const Icon(Icons.picture_in_picture_alt, color: Colors.white70, size: 22),
                  tooltip: 'Mini Player Flutuante (estilo modelo.webp)',
                  onPressed: () {
                    final windowMode = Provider.of<WindowModeService>(context, listen: false);
                    windowMode.switchToMiniMode();
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
