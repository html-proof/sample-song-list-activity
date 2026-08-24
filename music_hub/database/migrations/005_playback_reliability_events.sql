-- Playback failures must never be learned as user dislike. These event types
-- keep transport intent and provider/network failures separate in analytics.
ALTER TYPE music_event_type ADD VALUE IF NOT EXISTS 'user_pressed_next';
ALTER TYPE music_event_type ADD VALUE IF NOT EXISTS 'user_pressed_previous';
ALTER TYPE music_event_type ADD VALUE IF NOT EXISTS 'track_failed_to_play';
ALTER TYPE music_event_type ADD VALUE IF NOT EXISTS 'network_failure';
ALTER TYPE music_event_type ADD VALUE IF NOT EXISTS 'track_end';
