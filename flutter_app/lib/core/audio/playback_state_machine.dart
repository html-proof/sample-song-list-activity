enum PlaybackPhase {
  idle,
  loading,
  buffering,
  playing,
  paused,
  completed,
  recoverableError,
  fatalError,
}

enum PlaybackSignal {
  loadRequested,
  bufferingStarted,
  playbackStarted,
  playRequested,
  pauseRequested,
  completed,
  recoverableFailure,
  retryStarted,
  fatalFailure,
  stopped,
}

class PlaybackMachineState {
  const PlaybackMachineState({
    this.phase = PlaybackPhase.idle,
    this.wantsToPlay = false,
    this.recoveryAttempt = 0,
    this.message,
  });

  final PlaybackPhase phase;
  final bool wantsToPlay;
  final int recoveryAttempt;
  final String? message;

  bool get isRecovering =>
      phase == PlaybackPhase.recoverableError ||
      (phase == PlaybackPhase.loading && recoveryAttempt > 0);

  PlaybackMachineState transition(
    PlaybackSignal signal, {
    bool? autoPlay,
    String? message,
  }) {
    return switch (signal) {
      PlaybackSignal.loadRequested => PlaybackMachineState(
        phase: PlaybackPhase.loading,
        wantsToPlay: autoPlay ?? wantsToPlay,
      ),
      PlaybackSignal.bufferingStarted => PlaybackMachineState(
        phase: PlaybackPhase.buffering,
        wantsToPlay: wantsToPlay,
        recoveryAttempt: recoveryAttempt,
      ),
      PlaybackSignal.playbackStarted => const PlaybackMachineState(
        phase: PlaybackPhase.playing,
        wantsToPlay: true,
      ),
      PlaybackSignal.playRequested => PlaybackMachineState(
        phase: phase == PlaybackPhase.paused ? PlaybackPhase.buffering : phase,
        wantsToPlay: true,
        recoveryAttempt: recoveryAttempt,
      ),
      PlaybackSignal.pauseRequested => const PlaybackMachineState(
        phase: PlaybackPhase.paused,
      ),
      PlaybackSignal.completed => const PlaybackMachineState(
        phase: PlaybackPhase.completed,
      ),
      PlaybackSignal.recoverableFailure => PlaybackMachineState(
        phase: PlaybackPhase.recoverableError,
        wantsToPlay: wantsToPlay,
        recoveryAttempt: recoveryAttempt + 1,
        message: message,
      ),
      PlaybackSignal.retryStarted => PlaybackMachineState(
        phase: PlaybackPhase.loading,
        wantsToPlay: wantsToPlay,
        recoveryAttempt: recoveryAttempt,
      ),
      PlaybackSignal.fatalFailure => PlaybackMachineState(
        phase: PlaybackPhase.fatalError,
        message: message,
      ),
      PlaybackSignal.stopped => const PlaybackMachineState(),
    };
  }
}
