BEGIN;

CREATE TABLE IF NOT EXISTS general_settings (
    user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    app_language TEXT NOT NULL DEFAULT 'en',
    theme_mode TEXT NOT NULL DEFAULT 'system'
        CHECK (theme_mode IN ('system', 'light', 'dark')),
    dynamic_artwork_colors BOOLEAN NOT NULL DEFAULT TRUE,
    animations_enabled BOOLEAN NOT NULL DEFAULT TRUE,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS playback_settings (
    user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    streaming_quality TEXT NOT NULL DEFAULT 'auto'
        CHECK (streaming_quality IN ('auto', 'low', 'medium', 'high')),
    mobile_streaming_quality TEXT NOT NULL DEFAULT 'medium'
        CHECK (mobile_streaming_quality IN ('auto', 'low', 'medium', 'high')),
    wifi_streaming_quality TEXT NOT NULL DEFAULT 'high'
        CHECK (wifi_streaming_quality IN ('auto', 'low', 'medium', 'high')),
    autoplay BOOLEAN NOT NULL DEFAULT TRUE,
    normalize_volume BOOLEAN NOT NULL DEFAULT TRUE,
    gapless_playback BOOLEAN NOT NULL DEFAULT TRUE,
    crossfade_seconds SMALLINT NOT NULL DEFAULT 0 CHECK (crossfade_seconds BETWEEN 0 AND 12),
    explicit_content BOOLEAN NOT NULL DEFAULT TRUE,
    auto_resume BOOLEAN NOT NULL DEFAULT TRUE,
    repeat_mode TEXT NOT NULL DEFAULT 'off' CHECK (repeat_mode IN ('off', 'all', 'one')),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS download_settings (
    user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    quality TEXT NOT NULL DEFAULT 'high' CHECK (quality IN ('low', 'medium', 'high')),
    wifi_only BOOLEAN NOT NULL DEFAULT TRUE,
    auto_download_liked BOOLEAN NOT NULL DEFAULT FALSE,
    auto_download_playlists BOOLEAN NOT NULL DEFAULT FALSE,
    delete_played_after_days INTEGER CHECK (delete_played_after_days IS NULL OR delete_played_after_days BETWEEN 1 AND 365),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS recommendation_settings (
    user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    enabled BOOLEAN NOT NULL DEFAULT TRUE,
    use_listening_history BOOLEAN NOT NULL DEFAULT TRUE,
    use_search_history BOOLEAN NOT NULL DEFAULT TRUE,
    use_likes BOOLEAN NOT NULL DEFAULT TRUE,
    cross_language_discovery BOOLEAN NOT NULL DEFAULT TRUE,
    discover_new_artists BOOLEAN NOT NULL DEFAULT TRUE,
    exploration_level SMALLINT NOT NULL DEFAULT 20 CHECK (exploration_level BETWEEN 0 AND 100),
    diversity_level SMALLINT NOT NULL DEFAULT 50 CHECK (diversity_level BETWEEN 0 AND 100),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS notification_settings (
    user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    enabled BOOLEAN NOT NULL DEFAULT TRUE,
    artist_releases BOOLEAN NOT NULL DEFAULT TRUE,
    new_music BOOLEAN NOT NULL DEFAULT TRUE,
    recommendations BOOLEAN NOT NULL DEFAULT TRUE,
    playlist_updates BOOLEAN NOT NULL DEFAULT TRUE,
    download_complete BOOLEAN NOT NULL DEFAULT TRUE,
    headphone_health BOOLEAN NOT NULL DEFAULT TRUE,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS privacy_settings (
    user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    save_listening_history BOOLEAN NOT NULL DEFAULT TRUE,
    save_search_history BOOLEAN NOT NULL DEFAULT TRUE,
    personalized_recommendations BOOLEAN NOT NULL DEFAULT TRUE,
    analytics_enabled BOOLEAN NOT NULL DEFAULT TRUE,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS user_devices (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    device_id TEXT NOT NULL,
    platform TEXT NOT NULL CHECK (platform IN ('android', 'ios', 'web', 'windows', 'macos', 'linux')),
    device_name TEXT,
    fcm_token TEXT,
    app_version TEXT,
    notifications_enabled BOOLEAN NOT NULL DEFAULT TRUE,
    last_active_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(user_id, device_id)
);

INSERT INTO playback_settings (user_id, streaming_quality, autoplay, explicit_content)
SELECT user_id,
       CASE WHEN audio_quality = 'very_high' THEN 'high' ELSE audio_quality END,
       autoplay,
       explicit_content
FROM user_preferences
ON CONFLICT (user_id) DO NOTHING;

INSERT INTO notification_settings (user_id, artist_releases, recommendations)
SELECT user_id, followed_artists, recommendations
FROM notification_preferences
ON CONFLICT (user_id) DO NOTHING;

CREATE INDEX IF NOT EXISTS user_devices_user_active_idx
    ON user_devices (user_id, last_active_at DESC);

DO $$
DECLARE table_name TEXT;
BEGIN
    FOREACH table_name IN ARRAY ARRAY[
        'general_settings', 'playback_settings', 'download_settings',
        'recommendation_settings', 'notification_settings',
        'privacy_settings', 'user_devices'
    ]
    LOOP
        EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', table_name);
    END LOOP;
END $$;

COMMIT;
