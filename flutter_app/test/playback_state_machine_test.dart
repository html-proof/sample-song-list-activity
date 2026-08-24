import 'package:flutter_test/flutter_test.dart';
import 'package:music_hub_app/core/audio/playback_state_machine.dart';

void main() {
  test('pause cancels pending play while buffering', () {
    final loading = const PlaybackMachineState().transition(
      PlaybackSignal.loadRequested,
      autoPlay: true,
    );
    final buffering = loading.transition(PlaybackSignal.bufferingStarted);
    final paused = buffering.transition(PlaybackSignal.pauseRequested);

    expect(buffering.phase, PlaybackPhase.buffering);
    expect(buffering.wantsToPlay, isTrue);
    expect(paused.phase, PlaybackPhase.paused);
    expect(paused.wantsToPlay, isFalse);
  });

  test('recoverable failures retain intent and count bounded attempts', () {
    final playing = const PlaybackMachineState().transition(
      PlaybackSignal.playbackStarted,
    );
    final failed = playing.transition(
      PlaybackSignal.recoverableFailure,
      message: 'temporary',
    );
    final retrying = failed.transition(PlaybackSignal.retryStarted);

    expect(failed.phase, PlaybackPhase.recoverableError);
    expect(failed.wantsToPlay, isTrue);
    expect(failed.recoveryAttempt, 1);
    expect(retrying.phase, PlaybackPhase.loading);
    expect(retrying.isRecovering, isTrue);
  });

  test('fatal failure reaches a safe stopped intent', () {
    final failed = const PlaybackMachineState(
      phase: PlaybackPhase.buffering,
      wantsToPlay: true,
    ).transition(PlaybackSignal.fatalFailure, message: 'unavailable');

    expect(failed.phase, PlaybackPhase.fatalError);
    expect(failed.wantsToPlay, isFalse);
    expect(failed.message, 'unavailable');
  });
}
