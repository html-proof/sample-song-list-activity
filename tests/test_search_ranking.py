from unittest.mock import AsyncMock
from uuid import uuid4

import pytest

from music_hub.config import Settings
from music_hub.search import MatchTier, deduplicate, detect_intent, normalize, rank_songs
from music_hub.search.intent import QueryIntent
from music_hub.search.ranking import score_song, song_identity
from music_hub.services.search import SearchService


def song(title, artist="", album="", language="", popularity="", track_id=None):
    return {
        "track_id": track_id or title.lower().replace(" ", "-"),
        "title": title,
        "artists": artist,
        "album": album,
        "language": language,
        "popularity": popularity,
    }


def rank(songs, query, limit=10):
    return rank_songs(songs, query, detect_intent(query), limit)


def titles(results):
    return [item["title"] for item in results]


# -- normalization -----------------------------------------------------------


def test_normalize_folds_case_punctuation_entities_and_spacing():
    assert normalize("  Pattalam!!  ") == "pattalam"
    assert normalize("Rock &amp; Roll") == "rock roll"
    assert normalize("Ｐａｔｔａｌａｍ") == "pattalam"
    assert normalize("A   B\tC") == "a b c"
    assert normalize(None) == ""


def test_normalize_keeps_non_latin_scripts():
    assert normalize("പട്ടാളം") == "പട്ടാളം"


# -- the ordering the brief asks for -----------------------------------------


def test_exact_title_outranks_every_other_match():
    results = rank(
        [
            song("Pattalam Police"),
            song("Veera Pattalam Anthem"),
            song("Something Else", artist="Pattalam"),
            song("Pattalam"),
            song("Pattalan"),
        ],
        "pattalam",
    )
    assert titles(results)[0] == "Pattalam"


def test_full_expected_ordering_for_pattalam():
    results = rank(
        [
            song("Random Trending Song", language="Malayalam", popularity="99999"),
            song("Pattalan"),
            song("Ente Pattalam Vannu"),
            song("Pattalam Police"),
            song("Pattalam"),
        ],
        "pattalam",
    )
    assert titles(results) == [
        "Pattalam",             # exact title
        "Pattalam Police",      # title starts with query
        "Ente Pattalam Vannu",  # query is a whole word in the title
        "Pattalan",             # fuzzy / typo, last
    ]
    # The popular but irrelevant track is gone, not merely demoted.
    assert "Random Trending Song" not in titles(results)


def test_popularity_never_overtakes_a_weaker_text_match():
    results = rank(
        [song("Pattalam Police", popularity="9999999"), song("Pattalam", popularity="0")],
        "pattalam",
    )
    assert titles(results) == ["Pattalam", "Pattalam Police"]


def test_prefix_match_cannot_outscore_an_exact_title():
    """A summed score would let prefix+word+contains bonuses beat an exact hit."""
    exact_tier, _ = score_song(song("Pattalam"), "pattalam")
    prefix_tier, _ = score_song(
        song("Pattalam Police", artist="Pattalam", album="Pattalam"), "pattalam"
    )
    assert exact_tier is MatchTier.EXACT_TITLE
    assert exact_tier > prefix_tier


def test_artist_match_does_not_push_down_the_requested_song():
    results = rank(
        [song("Unrelated Song", artist="Pattalam"), song("Pattalam")],
        "pattalam",
    )
    assert titles(results)[0] == "Pattalam"


def test_scores_follow_the_published_tier_table():
    assert score_song(song("Pattalam"), "pattalam")[0] == MatchTier.EXACT_TITLE
    assert score_song(song("Pattalam Police"), "pattalam")[0] == MatchTier.TITLE_PREFIX
    assert score_song(song("X", artist="Pattalam"), "pattalam")[0] == MatchTier.EXACT_ARTIST
    assert score_song(song("X", album="Pattalam"), "pattalam")[0] == MatchTier.EXACT_ALBUM
    assert score_song(song("Ente Pattalam Vannu"), "pattalam")[0] == MatchTier.TITLE_WORD
    assert score_song(song("Superpattalam"), "pattalam")[0] == MatchTier.TITLE_CONTAINS
    assert score_song(song("X", artist="The Pattalam Band"), "pattalam")[0] == (
        MatchTier.ARTIST_CONTAINS
    )
    assert score_song(song("X", album="Pattalam Hits"), "pattalam")[0] == (
        MatchTier.ALBUM_CONTAINS
    )


def test_irrelevant_results_are_dropped_once_enough_matches_exist():
    results = rank(
        [
            song("Pattalam"),
            song("Pattalam Police"),
            song("Pattalam Returns"),
            song("Ente Pattalam"),
            song("Super Pattalam Hits"),
            song("Completely Unrelated"),
        ],
        "pattalam",
    )
    assert "Completely Unrelated" not in titles(results)


def test_a_thin_result_set_is_padded_rather_than_left_empty():
    results = rank([song("Pattalam"), song("Unrelated A"), song("Unrelated B")], "pattalam")
    assert titles(results)[0] == "Pattalam"
    assert len(results) == 3
    assert [item["search_score"] for item in results][1:] == [0.0, 0.0]


# -- fuzzy is a fallback, never a competitor ---------------------------------


def test_fuzzy_matches_are_suppressed_when_strong_matches_exist():
    results = rank(
        [
            song("Pattalan"),  # typo neighbour
            song("Pattalam"),
            song("Pattalam Police"),
            song("Pattalam Returns"),
            song("Ente Pattalam"),
            song("Super Pattalam Hits"),
        ],
        "pattalam",
    )
    assert "Pattalan" not in titles(results)


def test_fuzzy_matches_survive_when_there_is_little_else():
    results = rank([song("Pattalan"), song("Pattalam Police")], "pattalam")
    assert "Pattalan" in titles(results)


def test_fuzzy_never_precedes_an_exact_match():
    results = rank([song("Pattalan"), song("Pattalam")], "pattalam")
    assert titles(results) == ["Pattalam", "Pattalan"]


# -- language queries --------------------------------------------------------


def test_language_queries_are_detected():
    assert detect_intent("malayalam").intent is QueryIntent.LANGUAGE
    assert detect_intent("malayalam songs").language == "malayalam"
    assert detect_intent("top hindi hits").language == "hindi"
    assert detect_intent("pattalam").intent is QueryIntent.SONG


def test_language_query_filters_on_metadata_not_on_title_text():
    results = rank(
        [
            song("A Song About Malayalam", language="Hindi"),
            song("Kaliyachan", language="Malayalam", popularity="500"),
            song("Ente Kadha", language="Malayalam", popularity="900"),
        ],
        "malayalam",
    )
    assert titles(results) == ["Ente Kadha", "Kaliyachan"]


def test_artist_and_album_query_intents():
    assert detect_intent("ar rahman artist").intent is QueryIntent.ARTIST
    assert detect_intent("sarkar movie").intent is QueryIntent.ALBUM


# -- deduplication -----------------------------------------------------------


def test_the_same_song_from_two_providers_appears_once():
    gaana = song("Pattalam", artist="Deepak Dev", album="Pattalam", track_id="g1")
    saavn = song("Pattalam", artist="Deepak Dev", album="Pattalam", track_id="s1")
    assert song_identity(gaana) == song_identity(saavn)
    assert len(deduplicate([gaana, saavn])) == 1


def test_deduplication_keeps_the_more_complete_record():
    thin = song("Pattalam", track_id="g1")
    rich = dict(song("Pattalam", artist="Deepak Dev", album="Pattalam", track_id="s1"),
                stream_urls={"urls": {"high": "https://example.com/a.mp4"}}, duration="240")
    thin_identity = song_identity(thin)
    rich_identity = song_identity(rich)
    kept = deduplicate([thin, rich])
    # Different identities (thin has no artist/album), so both survive here.
    assert thin_identity != rich_identity
    assert len(kept) == 2

    duplicate_thin = song("Pattalam", artist="Deepak Dev", album="Pattalam", track_id="g2")
    kept = deduplicate([duplicate_thin, rich])
    assert len(kept) == 1
    assert kept[0]["stream_urls"]


def test_distinct_songs_are_not_collapsed():
    covers = [
        song("Pattalam", artist="A", track_id="1"),
        song("Pattalam", artist="B", track_id="2"),
    ]
    assert len(deduplicate(covers)) == 2


def test_the_same_id_from_different_providers_is_not_collapsed():
    gaana = dict(song("Pattalam", track_id="123"), provider="gaana")
    saavn = dict(song("Different Song", track_id="123"), provider="jiosaavn")
    assert len(deduplicate([gaana, saavn])) == 2


def test_deduplication_is_resilient_to_junk_entries():
    assert deduplicate([None, "nonsense", song("Pattalam")]) == [song("Pattalam")]


# -- end to end through the service -----------------------------------------


def make_service():
    provider = AsyncMock()
    history = AsyncMock()
    cache = AsyncMock()
    cache.get_json.return_value = None
    settings = Settings(database_url=None, redis_url=None)
    return SearchService(provider, history, cache, settings), provider, cache


@pytest.mark.asyncio
async def test_service_reorders_the_providers_raw_response():
    service, provider, _ = make_service()
    provider.search_songs.return_value = [
        song("Random Malayalam Trending Song", language="Malayalam", popularity="99999"),
        song("Popular Unrelated Track", popularity="88888"),
        song("Pattalam"),
    ]

    result = await service.search(uuid4(), "pattalam", "songs", 10)

    assert titles(result["songs"])[0] == "Pattalam"


def test_search_endpoint_defaults_to_twenty_results():
    from music_hub.api.v1.search import search as search_endpoint

    default = search_endpoint.__defaults__[2]
    assert default.default == 20


@pytest.mark.asyncio
async def test_service_overfetches_so_ranking_has_candidates():
    service, provider, _ = make_service()
    provider.search_songs.return_value = [song("Pattalam")]

    await service.search(uuid4(), "pattalam", "songs", 5)

    assert provider.search_songs.await_args.args[1] >= 30


@pytest.mark.asyncio
async def test_service_returns_songs_artists_and_albums_as_separate_sections():
    service, provider, _ = make_service()
    provider.search_songs.return_value = [song("Pattalam")]
    provider.search_albums.return_value = [{"album_id": "1", "title": "Pattalam"}]
    provider.search_artists.return_value = [{"artist_id": "1", "name": "Pattalam"}]

    result = await service.search(uuid4(), "pattalam", "all", 10)

    assert list(result) == ["songs", "albums", "artists"]
    assert titles(result["songs"]) == ["Pattalam"]
    assert result["albums"][0]["title"] == "Pattalam"
    assert result["artists"][0]["name"] == "Pattalam"


@pytest.mark.asyncio
async def test_results_from_two_providers_are_merged_and_deduplicated():
    service, provider, _ = make_service()
    second = AsyncMock()
    service.providers = [provider, second]
    provider.search_songs.return_value = [song("Pattalam", artist="Deepak Dev", track_id="g1")]
    second.search_songs.return_value = [
        song("Pattalam", artist="Deepak Dev", track_id="s1"),
        song("Pattalam Police", track_id="s2"),
    ]

    result = await service.search(uuid4(), "pattalam", "songs", 10)

    assert titles(result["songs"]) == ["Pattalam", "Pattalam Police"]


@pytest.mark.asyncio
async def test_one_failing_provider_does_not_fail_the_search():
    service, provider, _ = make_service()
    second = AsyncMock()
    second.search_songs.side_effect = RuntimeError("upstream down")
    service.providers = [provider, second]
    provider.search_songs.return_value = [song("Pattalam")]

    result = await service.search(uuid4(), "pattalam", "songs", 10)

    assert titles(result["songs"]) == ["Pattalam"]


@pytest.mark.asyncio
async def test_cache_key_changes_with_every_keystroke():
    service, provider, cache = make_service()
    provider.search_songs.return_value = [song("Pattalam")]

    await service.search(uuid4(), "pattala", "songs", 10)
    first = cache.get_json.await_args.args[0]
    await service.search(uuid4(), "pattalam", "songs", 10)
    second = cache.get_json.await_args.args[0]

    assert first != second


@pytest.mark.asyncio
async def test_cache_key_ignores_incidental_query_formatting():
    service, provider, cache = make_service()
    provider.search_songs.return_value = [song("Pattalam")]

    await service.search(uuid4(), "Pattalam", "songs", 10)
    first = cache.get_json.await_args.args[0]
    await service.search(uuid4(), "  pattalam!  ", "songs", 10)
    second = cache.get_json.await_args.args[0]

    assert first == second


@pytest.mark.asyncio
async def test_search_ranking_ignores_listening_history():
    """Search answers the query; personalization belongs to recommendations."""
    service, provider, _ = make_service()
    provider.search_songs.return_value = [song("Pattalam Police"), song("Pattalam")]

    result = await service.search(uuid4(), "pattalam", "songs", 10)

    assert titles(result["songs"])[0] == "Pattalam"
    service.history.get_recent_songs.assert_not_called()
