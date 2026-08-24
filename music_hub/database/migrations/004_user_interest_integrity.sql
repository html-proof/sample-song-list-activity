BEGIN;

-- Keep every learned preference under the owning user. Sources are separated
-- so removing a like/history row never destroys an explicit onboarding choice.
CREATE TABLE IF NOT EXISTS user_interest_signals (
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    provider TEXT NOT NULL DEFAULT 'gaana',
    entity_type TEXT NOT NULL
        CHECK (entity_type IN ('song', 'artist', 'album', 'language', 'search')),
    entity_id TEXT NOT NULL CHECK (length(trim(entity_id)) > 0),
    source TEXT NOT NULL CHECK (length(trim(source)) > 0),
    score DOUBLE PRECISION NOT NULL DEFAULT 0,
    occurrences INTEGER NOT NULL DEFAULT 1 CHECK (occurrences >= 0),
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    first_seen_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_seen_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, provider, entity_type, entity_id, source)
);

CREATE INDEX IF NOT EXISTS user_interest_signals_rank_idx
    ON user_interest_signals (user_id, entity_type, score DESC, last_seen_at DESC);
CREATE INDEX IF NOT EXISTS user_interest_signals_source_idx
    ON user_interest_signals (user_id, source);

ALTER TABLE user_interest_signals ENABLE ROW LEVEL SECURITY;

ALTER TABLE recommendation_profiles
    ADD COLUMN IF NOT EXISTS learning_reset_at TIMESTAMPTZ;
ALTER TABLE recommendation_profiles
    ALTER COLUMN model_version SET DEFAULT 'weighted-v2';

CREATE OR REPLACE FUNCTION set_user_interest_signal(
    p_user_id UUID,
    p_provider TEXT,
    p_entity_type TEXT,
    p_entity_id TEXT,
    p_source TEXT,
    p_score DOUBLE PRECISION,
    p_metadata JSONB DEFAULT '{}'::jsonb
)
RETURNS VOID AS $$
BEGIN
    IF p_entity_id IS NULL OR length(trim(p_entity_id)) = 0 THEN
        RETURN;
    END IF;
    INSERT INTO user_interest_signals (
        user_id, provider, entity_type, entity_id, source, score,
        occurrences, metadata, first_seen_at, last_seen_at
    ) VALUES (
        p_user_id, COALESCE(NULLIF(p_provider, ''), 'gaana'), p_entity_type,
        trim(p_entity_id), p_source, p_score, 1, COALESCE(p_metadata, '{}'::jsonb),
        now(), now()
    )
    ON CONFLICT (user_id, provider, entity_type, entity_id, source) DO UPDATE
    SET score = EXCLUDED.score,
        occurrences = 1,
        metadata = EXCLUDED.metadata,
        last_seen_at = now();
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION add_user_interest_signal(
    p_user_id UUID,
    p_provider TEXT,
    p_entity_type TEXT,
    p_entity_id TEXT,
    p_source TEXT,
    p_delta DOUBLE PRECISION,
    p_metadata JSONB DEFAULT '{}'::jsonb
)
RETURNS VOID AS $$
BEGIN
    IF p_entity_id IS NULL OR length(trim(p_entity_id)) = 0 OR p_delta = 0 THEN
        RETURN;
    END IF;
    INSERT INTO user_interest_signals (
        user_id, provider, entity_type, entity_id, source, score,
        occurrences, metadata, first_seen_at, last_seen_at
    ) VALUES (
        p_user_id, COALESCE(NULLIF(p_provider, ''), 'gaana'), p_entity_type,
        trim(p_entity_id), p_source, p_delta, 1,
        COALESCE(p_metadata, '{}'::jsonb), now(), now()
    )
    ON CONFLICT (user_id, provider, entity_type, entity_id, source) DO UPDATE
    SET score = user_interest_signals.score + EXCLUDED.score,
        occurrences = user_interest_signals.occurrences + 1,
        metadata = user_interest_signals.metadata || EXCLUDED.metadata,
        last_seen_at = now();
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sync_language_interest()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP IN ('DELETE', 'UPDATE') THEN
        DELETE FROM user_interest_signals
        WHERE user_id = OLD.user_id AND provider = 'all'
          AND entity_type = 'language'
          AND entity_id = lower(OLD.language_code)
          AND source = 'onboarding_language';
    END IF;
    IF TG_OP IN ('INSERT', 'UPDATE') THEN
        PERFORM set_user_interest_signal(
            NEW.user_id, 'all', 'language', lower(NEW.language_code),
            'onboarding_language', NEW.priority::DOUBLE PRECISION
        );
        RETURN NEW;
    END IF;
    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sync_selected_artist_interest()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP IN ('DELETE', 'UPDATE') THEN
        DELETE FROM user_interest_signals
        WHERE user_id = OLD.user_id AND provider = OLD.provider
          AND entity_type = 'artist'
          AND entity_id = OLD.provider_artist_id
          AND source = 'onboarding_artist';
    END IF;
    IF TG_OP IN ('INSERT', 'UPDATE') THEN
        PERFORM set_user_interest_signal(
            NEW.user_id, NEW.provider, 'artist', NEW.provider_artist_id,
            'onboarding_artist', 10.0 * NEW.preference_score,
            jsonb_build_object('artist_name', NEW.artist_name)
        );
        RETURN NEW;
    END IF;
    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sync_liked_song_interest()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP IN ('DELETE', 'UPDATE') THEN
        DELETE FROM user_interest_signals
        WHERE user_id = OLD.user_id AND source = 'liked_song'
          AND (
            (provider = OLD.provider AND entity_type = 'song' AND entity_id = OLD.song_id)
            OR (provider = OLD.provider AND entity_type = 'artist' AND entity_id = COALESCE(OLD.artist_id, ''))
            OR (provider = 'all' AND entity_type = 'language' AND entity_id = lower(COALESCE(OLD.language, '')))
          );
    END IF;
    IF TG_OP IN ('INSERT', 'UPDATE') THEN
        PERFORM set_user_interest_signal(
            NEW.user_id, NEW.provider, 'song', NEW.song_id, 'liked_song', 12.0
        );
        PERFORM set_user_interest_signal(
            NEW.user_id, NEW.provider, 'artist', NEW.artist_id, 'liked_song', 8.0
        );
        PERFORM set_user_interest_signal(
            NEW.user_id, 'all', 'language', lower(NEW.language), 'liked_song', 4.0
        );
        RETURN NEW;
    END IF;
    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sync_followed_artist_interest()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP IN ('DELETE', 'UPDATE') THEN
        DELETE FROM user_interest_signals
        WHERE user_id = OLD.user_id AND provider = OLD.provider
          AND entity_type = 'artist' AND entity_id = OLD.artist_id
          AND source = 'followed_artist';
    END IF;
    IF TG_OP IN ('INSERT', 'UPDATE') THEN
        PERFORM set_user_interest_signal(
            NEW.user_id, NEW.provider, 'artist', NEW.artist_id,
            'followed_artist', 14.0,
            jsonb_build_object('artist_name', NEW.artist_name)
        );
        RETURN NEW;
    END IF;
    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION learn_from_listening_history()
RETURNS TRIGGER AS $$
DECLARE
    completion_bonus DOUBLE PRECISION :=
        CASE WHEN COALESCE(NEW.completion_percentage, 0) >= 0.9 THEN 4.0 ELSE 0.0 END;
BEGIN
    PERFORM add_user_interest_signal(
        NEW.user_id, NEW.provider, 'song', NEW.song_id,
        'listening_history', 1.0 + completion_bonus
    );
    PERFORM add_user_interest_signal(
        NEW.user_id, NEW.provider, 'artist', NEW.artist_id,
        'listening_history', 0.75 + completion_bonus
    );
    PERFORM add_user_interest_signal(
        NEW.user_id, 'all', 'language', lower(NEW.language),
        'listening_history', 0.5 + completion_bonus / 2.0
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION learn_from_music_event()
RETURNS TRIGGER AS $$
DECLARE
    delta DOUBLE PRECISION := CASE NEW.event_type::TEXT
        WHEN 'play' THEN 1.0
        WHEN 'complete' THEN 5.0
        WHEN 'like' THEN 10.0
        WHEN 'repeat' THEN 6.0
        WHEN 'add_playlist' THEN 7.0
        WHEN 'download' THEN 5.0
        WHEN 'share' THEN 3.0
        WHEN 'skip' THEN -6.0
        WHEN 'unlike' THEN -10.0
        WHEN 'remove_playlist' THEN -7.0
        ELSE 0.0
    END;
BEGIN
    PERFORM add_user_interest_signal(
        NEW.user_id, NEW.provider, 'song', NEW.song_id, 'music_event', delta
    );
    PERFORM add_user_interest_signal(
        NEW.user_id, NEW.provider, 'artist', NEW.artist_id, 'music_event', delta * 0.7
    );
    PERFORM add_user_interest_signal(
        NEW.user_id, 'all', 'language', lower(NEW.language), 'music_event', delta * 0.4
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION learn_from_search_history()
RETURNS TRIGGER AS $$
BEGIN
    PERFORM add_user_interest_signal(
        NEW.user_id, 'all', 'search', NEW.normalized_query,
        'search_history', CASE WHEN NEW.clicked_result_id IS NULL THEN 0.5 ELSE 1.5 END
    );
    IF NEW.clicked_result_id IS NOT NULL
       AND NEW.result_type IN ('song', 'artist', 'album') THEN
        PERFORM add_user_interest_signal(
            NEW.user_id, 'gaana', NEW.result_type, NEW.clicked_result_id,
            'search_click', 3.0
        );
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS user_languages_interest_sync ON user_languages;
CREATE TRIGGER user_languages_interest_sync
    AFTER INSERT OR UPDATE OR DELETE ON user_languages
    FOR EACH ROW EXECUTE FUNCTION sync_language_interest();

DROP TRIGGER IF EXISTS user_artists_interest_sync ON user_artists;
CREATE TRIGGER user_artists_interest_sync
    AFTER INSERT OR UPDATE OR DELETE ON user_artists
    FOR EACH ROW EXECUTE FUNCTION sync_selected_artist_interest();

DROP TRIGGER IF EXISTS liked_songs_interest_sync ON liked_songs;
CREATE TRIGGER liked_songs_interest_sync
    AFTER INSERT OR UPDATE OR DELETE ON liked_songs
    FOR EACH ROW EXECUTE FUNCTION sync_liked_song_interest();

DROP TRIGGER IF EXISTS followed_artists_interest_sync ON followed_artists;
CREATE TRIGGER followed_artists_interest_sync
    AFTER INSERT OR UPDATE OR DELETE ON followed_artists
    FOR EACH ROW EXECUTE FUNCTION sync_followed_artist_interest();

DROP TRIGGER IF EXISTS listening_history_interest_learn ON listening_history;
CREATE TRIGGER listening_history_interest_learn
    AFTER INSERT ON listening_history
    FOR EACH ROW EXECUTE FUNCTION learn_from_listening_history();

DROP TRIGGER IF EXISTS music_events_interest_learn ON music_events;
CREATE TRIGGER music_events_interest_learn
    AFTER INSERT ON music_events
    FOR EACH ROW EXECUTE FUNCTION learn_from_music_event();

DROP TRIGGER IF EXISTS search_history_interest_learn ON search_history;
CREATE TRIGGER search_history_interest_learn
    AFTER INSERT ON search_history
    FOR EACH ROW EXECUTE FUNCTION learn_from_search_history();

-- Backfill durable, explicit signals. Learned history starts fresh after this
-- migration so scores cannot be accidentally doubled during repeated deploys.
INSERT INTO user_interest_signals (
    user_id, provider, entity_type, entity_id, source, score, occurrences, metadata
)
SELECT user_id, 'all', 'language', lower(language_code),
       'onboarding_language', priority::DOUBLE PRECISION, 1, '{}'::jsonb
FROM user_languages
ON CONFLICT (user_id, provider, entity_type, entity_id, source) DO UPDATE
SET score = EXCLUDED.score, occurrences = 1, last_seen_at = now();

INSERT INTO user_interest_signals (
    user_id, provider, entity_type, entity_id, source, score, occurrences, metadata
)
SELECT user_id, provider, 'artist', provider_artist_id,
       'onboarding_artist', 10.0 * preference_score, 1,
       jsonb_build_object('artist_name', artist_name)
FROM user_artists
ON CONFLICT (user_id, provider, entity_type, entity_id, source) DO UPDATE
SET score = EXCLUDED.score, occurrences = 1,
    metadata = EXCLUDED.metadata, last_seen_at = now();

INSERT INTO user_interest_signals (
    user_id, provider, entity_type, entity_id, source, score, occurrences, metadata
)
SELECT user_id, provider, 'song', song_id, 'liked_song', 12.0, 1, '{}'::jsonb
FROM liked_songs
ON CONFLICT (user_id, provider, entity_type, entity_id, source) DO UPDATE
SET score = EXCLUDED.score, occurrences = 1, last_seen_at = now();

INSERT INTO user_interest_signals (
    user_id, provider, entity_type, entity_id, source, score, occurrences, metadata
)
SELECT user_id, provider, 'artist', artist_id, 'followed_artist', 14.0, 1,
       jsonb_build_object('artist_name', artist_name)
FROM followed_artists
ON CONFLICT (user_id, provider, entity_type, entity_id, source) DO UPDATE
SET score = EXCLUDED.score, occurrences = 1,
    metadata = EXCLUDED.metadata, last_seen_at = now();

-- A playlist track now carries its owner directly as well as through playlist_id.
-- The composite foreign key prevents a track from ever being attached to another
-- user's playlist by a faulty query.
ALTER TABLE playlist_tracks ADD COLUMN IF NOT EXISTS user_id UUID;
UPDATE playlist_tracks pt
SET user_id = p.user_id
FROM playlists p
WHERE pt.playlist_id = p.id AND pt.user_id IS NULL;
ALTER TABLE playlist_tracks ALTER COLUMN user_id SET NOT NULL;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'playlists_id_user_id_unique'
    ) THEN
        ALTER TABLE playlists
            ADD CONSTRAINT playlists_id_user_id_unique UNIQUE (id, user_id);
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'playlist_tracks_owner_fk'
    ) THEN
        ALTER TABLE playlist_tracks
            ADD CONSTRAINT playlist_tracks_owner_fk
            FOREIGN KEY (playlist_id, user_id)
            REFERENCES playlists(id, user_id) ON DELETE CASCADE;
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS playlist_tracks_user_order_idx
    ON playlist_tracks (user_id, playlist_id, position, added_at);
CREATE INDEX IF NOT EXISTS liked_songs_user_created_idx
    ON liked_songs (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS followed_artists_user_followed_idx
    ON followed_artists (user_id, followed_at DESC);
CREATE INDEX IF NOT EXISTS playlists_user_updated_idx
    ON playlists (user_id, updated_at DESC);
CREATE INDEX IF NOT EXISTS downloads_user_updated_idx
    ON downloads (user_id, updated_at DESC);

COMMIT;
