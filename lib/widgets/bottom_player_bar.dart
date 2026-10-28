import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/audio_player_service.dart';

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
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
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
            // Barra de Progresso da Música
            ProgressBar(
              progress: playerService.position,
              total: playerService.duration,
              buffered: playerService.position,
              progressBarColor: const Color(0xFF9D4EDD),
              baseBarColor: Colors.white12,
              bufferedBarColor: Colors.white24,
              thumbColor: const Color(0xFFC77DFF),
              barHeight: 3.5,
              thumbRadius: 6.0,
              timeLabelTextStyle: const TextStyle(
                color: Colors.white54,
                fontSize: 11,
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
                    width: 52,
                    height: 52,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(
                      width: 52,
                      height: 52,
                      color: Colors.white10,
                      child: const Icon(Icons.music_note, color: Colors.white30),
                    ),
                    errorWidget: (context, url, error) => Container(
                      width: 52,
                      height: 52,
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

                // Controles de Reprodução (Voltar, Play/Pause, Próxima)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.skip_previous, color: Colors.white),
                      iconSize: 28,
                      onPressed: () => playerService.previous(),
                    ),
                    const SizedBox(width: 4),
                    if (playerService.isLoading)
                      const SizedBox(
                        width: 42,
                        height: 42,
                        child: Padding(
                          padding: EdgeInsets.all(8.0),
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Color(0xFFC77DFF),
                          ),
                        ),
                      )
                    else
                      IconButton(
                        icon: Icon(
                          playerService.isPlaying
                              ? Icons.pause_circle_filled
                              : Icons.play_circle_filled,
                          color: const Color(0xFF9D4EDD),
                        ),
                        iconSize: 42,
                        onPressed: () => playerService.togglePlayPause(),
                      ),
                    const SizedBox(width: 4),
                    IconButton(
                      icon: const Icon(Icons.skip_next, color: Colors.white),
                      iconSize: 28,
                      onPressed: () => playerService.next(),
                    ),
                  ],
                ),

                const SizedBox(width: 20),

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
                      width: 100,
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 5),
                          trackHeight: 3,
                          activeTrackColor: const Color(0xFF9D4EDD),
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
              ],
            ),
          ],
        ),
      ),
    );
  }
}
