from music_hub.schemas.history import MusicEventCreate, MusicEventType


def test_playback_failure_is_not_a_user_skip() -> None:
    failed = MusicEventCreate(
        event_type=MusicEventType.track_failed_to_play,
        song_id="song-1",
    )
    pressed_next = MusicEventCreate(
        event_type=MusicEventType.user_pressed_next,
        song_id="song-1",
    )

    assert failed.event_type != pressed_next.event_type
    assert failed.event_type != MusicEventType.skip


def test_network_and_track_end_events_are_supported() -> None:
    assert MusicEventCreate(
        event_type="network_failure", song_id="song-1"
    ).event_type is MusicEventType.network_failure
    assert MusicEventCreate(
        event_type="track_end", song_id="song-1"
    ).event_type is MusicEventType.track_end
