import 'package:audio_service/audio_service.dart';
import '../models/track.dart';

class DaPlayerAudioHandler extends BaseAudioHandler with SeekHandler {
  Future<void> Function()? onPlay;
  Future<void> Function()? onPause;
  Future<void> Function()? onNext;
  Future<void> Function()? onPrevious;
  Future<void> Function(Duration)? onSeek;

  DaPlayerAudioHandler({
    this.onPlay,
    this.onPause,
    this.onNext,
    this.onPrevious,
    this.onSeek,
  });

  void updateTrack(Track track, {bool hasNext = false, bool hasPrevious = false}) {
    mediaItem.add(
      MediaItem(
        id: track.id,
        album: 'DaPlayer',
        title: track.title,
        artist: track.artist,
        duration: track.duration,
        artUri: Uri.tryParse(track.thumbnailUrl),
      ),
    );

    updatePlaybackState(
      isPlaying: true,
      position: Duration.zero,
      bufferedPosition: Duration.zero,
      hasNext: hasNext,
      hasPrevious: hasPrevious,
    );
  }

  void updatePlaybackState({
    required bool isPlaying,
    required Duration position,
    required Duration bufferedPosition,
    required bool hasNext,
    required bool hasPrevious,
    bool isLoading = false,
  }) {
    final controls = <MediaControl>[
      if (hasPrevious) MediaControl.skipToPrevious,
      if (isPlaying) MediaControl.pause else MediaControl.play,
      if (hasNext) MediaControl.skipToNext,
    ];

    final compactIndices = List.generate(controls.length, (i) => i);

    playbackState.add(
      playbackState.value.copyWith(
        controls: controls,
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        androidCompactActionIndices: compactIndices,
        processingState: isLoading
            ? AudioProcessingState.loading
            : AudioProcessingState.ready,
        playing: isPlaying,
        updatePosition: position,
        bufferedPosition: bufferedPosition,
      ),
    );
  }

  @override
  Future<void> play() async {
    if (onPlay != null) await onPlay!();
  }

  @override
  Future<void> pause() async {
    if (onPause != null) await onPause!();
  }

  @override
  Future<void> skipToNext() async {
    if (onNext != null) await onNext!();
  }

  @override
  Future<void> skipToPrevious() async {
    if (onPrevious != null) await onPrevious!();
  }

  @override
  Future<void> seek(Duration position) async {
    if (onSeek != null) await onSeek!(position);
  }

  @override
  Future<void> stop() async {
    if (onPause != null) await onPause!();
    playbackState.add(
      playbackState.value.copyWith(
        processingState: AudioProcessingState.idle,
        playing: false,
      ),
    );
    await super.stop();
  }
}
