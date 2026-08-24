BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

DO $$
BEGIN
    CREATE TYPE music_event_type AS ENUM (
        'impression', 'play', 'pause', 'resume', 'skip', 'complete',
        'like', 'unlike', 'repeat', 'add_playlist', 'remove_playlist',
        'share', 'download'
    );
EXCEPTION
    WHEN duplicate_object THEN NULL;
END $$;

CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    firebase_uid TEXT UNIQUE NOT NULL,
    display_name TEXT,
    email TEXT,
    photo_url TEXT,
    onboarding_completed BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_login_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS user_languages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    language_code TEXT NOT NULL,
    priority SMALLINT NOT NULL DEFAULT 1 CHECK (priority BETWEEN 1 AND 100),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (user_id, language_code)
);

CREATE TABLE IF NOT EXISTS user_artists (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    provider TEXT NOT NULL DEFAULT 'gaana',
    provider_artist_id TEXT NOT NULL,
    artist_name TEXT NOT NULL,
    artist_image TEXT,
    preference_score REAL NOT NULL DEFAULT 1.0 CHECK (preference_score >= 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (user_id, provider, provider_artist_id)
);

CREATE TABLE IF NOT EXISTS user_preferences (
    user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    explicit_content BOOLEAN NOT NULL DEFAULT TRUE,
    autoplay BOOLEAN NOT NULL DEFAULT TRUE,
    audio_quality TEXT NOT NULL DEFAULT 'high'
        CHECK (audio_quality IN ('low', 'medium', 'high', 'very_high')),
    settings JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS listening_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    provider TEXT NOT NULL DEFAULT 'gaana',
    song_id TEXT NOT NULL,
    seokey TEXT,
    song_name TEXT,
    artist_id TEXT,
    artist_name TEXT,
    album_id TEXT,
    album_name TEXT,
    language TEXT,
    artwork_url TEXT,
    duration_ms INTEGER CHECK (duration_ms IS NULL OR duration_ms >= 0),
    played_ms INTEGER NOT NULL DEFAULT 0 CHECK (played_ms >= 0),
    completion_percentage REAL
        CHECK (completion_percentage IS NULL OR completion_percentage BETWEEN 0 AND 1),
    source TEXT,
    started_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    session_id UUID,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS music_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    event_type music_event_type NOT NULL,
    provider TEXT NOT NULL DEFAULT 'gaana',
    song_id TEXT,
    artist_id TEXT,
    album_id TEXT,
    language TEXT,
    source TEXT,
    position_ms INTEGER CHECK (position_ms IS NULL OR position_ms >= 0),
    session_id UUID,
    idempotency_key TEXT,
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS search_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    query TEXT NOT NULL,
    normalized_query TEXT,
    result_type TEXT,
    clicked_result_id TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS liked_songs (
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    provider TEXT NOT NULL DEFAULT 'gaana',
    song_id TEXT NOT NULL,
    seokey TEXT,
    song_name TEXT,
    artist_id TEXT,
    artist_name TEXT,
    album_id TEXT,
    language TEXT,
    artwork_url TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, provider, song_id)
);

CREATE TABLE IF NOT EXISTS followed_artists (
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    provider TEXT NOT NULL DEFAULT 'gaana',
    artist_id TEXT NOT NULL,
    artist_name TEXT,
    artwork_url TEXT,
    notifications_enabled BOOLEAN NOT NULL DEFAULT TRUE,
    followed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, provider, artist_id)
);

CREATE TABLE IF NOT EXISTS playlists (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name TEXT NOT NULL CHECK (length(trim(name)) > 0),
    description TEXT,
    is_public BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS playlist_tracks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    playlist_id UUID NOT NULL REFERENCES playlists(id) ON DELETE CASCADE,
    provider TEXT NOT NULL DEFAULT 'gaana',
    song_id TEXT NOT NULL,
    song_name TEXT,
    artist_name TEXT,
    album_name TEXT,
    artwork_url TEXT,
    duration_ms INTEGER CHECK (duration_ms IS NULL OR duration_ms >= 0),
    position INTEGER NOT NULL CHECK (position >= 0),
    added_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (playlist_id, provider, song_id)
);

CREATE TABLE IF NOT EXISTS downloads (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    provider TEXT NOT NULL DEFAULT 'gaana',
    song_id TEXT NOT NULL,
    device_id TEXT,
    status TEXT NOT NULL DEFAULT 'requested'
        CHECK (status IN ('requested', 'ready', 'removed', 'failed')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (user_id, provider, song_id, device_id)
);

CREATE TABLE IF NOT EXISTS notification_preferences (
    user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    new_releases BOOLEAN NOT NULL DEFAULT TRUE,
    followed_artists BOOLEAN NOT NULL DEFAULT TRUE,
    recommendations BOOLEAN NOT NULL DEFAULT TRUE,
    push_token TEXT,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS recommendation_profiles (
    user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    profile JSONB NOT NULL DEFAULT '{}'::jsonb,
    model_version TEXT NOT NULL DEFAULT 'weighted-v1',
    generated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at TIMESTAMPTZ
);

CREATE UNIQUE INDEX IF NOT EXISTS music_events_idempotency_idx
    ON music_events (user_id, idempotency_key)
    WHERE idempotency_key IS NOT NULL;
CREATE INDEX IF NOT EXISTS listening_history_user_created_idx
    ON listening_history (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS listening_history_user_song_idx
    ON listening_history (user_id, provider, song_id, created_at DESC);
CREATE INDEX IF NOT EXISTS music_events_user_created_idx
    ON music_events (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS music_events_user_song_idx
    ON music_events (user_id, song_id, created_at DESC);
CREATE INDEX IF NOT EXISTS search_history_user_created_idx
    ON search_history (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS playlist_tracks_order_idx
    ON playlist_tracks (playlist_id, position, added_at);
CREATE INDEX IF NOT EXISTS user_languages_user_priority_idx
    ON user_languages (user_id, priority DESC);
CREATE INDEX IF NOT EXISTS user_artists_user_score_idx
    ON user_artists (user_id, preference_score DESC);

DROP TRIGGER IF EXISTS users_set_updated_at ON users;
CREATE TRIGGER users_set_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
DROP TRIGGER IF EXISTS preferences_set_updated_at ON user_preferences;
CREATE TRIGGER preferences_set_updated_at
    BEFORE UPDATE ON user_preferences
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
DROP TRIGGER IF EXISTS playlists_set_updated_at ON playlists;
CREATE TRIGGER playlists_set_updated_at
    BEFORE UPDATE ON playlists
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
DROP TRIGGER IF EXISTS downloads_set_updated_at ON downloads;
CREATE TRIGGER downloads_set_updated_at
    BEFORE UPDATE ON downloads
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Firebase tokens are verified by FastAPI, not Supabase Auth. Block direct
-- PostgREST access; the backend connects with a trusted database role.
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_languages ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_artists ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_preferences ENABLE ROW LEVEL SECURITY;
ALTER TABLE listening_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE music_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE search_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE liked_songs ENABLE ROW LEVEL SECURITY;
ALTER TABLE followed_artists ENABLE ROW LEVEL SECURITY;
ALTER TABLE playlists ENABLE ROW LEVEL SECURITY;
ALTER TABLE playlist_tracks ENABLE ROW LEVEL SECURITY;
ALTER TABLE downloads ENABLE ROW LEVEL SECURITY;
ALTER TABLE notification_preferences ENABLE ROW LEVEL SECURITY;
ALTER TABLE recommendation_profiles ENABLE ROW LEVEL SECURITY;

COMMIT;
