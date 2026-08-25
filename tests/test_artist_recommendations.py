from music_hub.recommendations.artist_identity import (
    artist_identity,
    deduplicate_artists,
    normalize,
)
from music_hub.recommendations.artist_scoring import (
    apply_source_quotas,
    artist_score,
    artist_search_score,
    rank_artists,
    rank_search_results,
)


class TestArtistIdentity:
    def test_casing_spacing_and_punctuation_collapse_to_one_identity(self):
        variants = [
            {"name": "Arijit Singh"},
            {"name": "ARIJIT SINGH"},
            {"name": "arijit  singh"},
            {"name": "Arijit-Singh"},
        ]
        assert len({artist_identity(item) for item in variants}) == 1

    def test_accents_normalise(self):
        assert normalize("Björk") == normalize("Bjork")

    def test_duplicates_collapse_to_a_single_row(self):
        merged = deduplicate_artists(
            [
                {"name": "Arijit Singh", "artist_id": "1"},
                {"name": "ARIJIT SINGH", "artist_id": "2"},
                {"name": "Arijit singh", "artist_id": "3"},
                {"name": "Shreya Ghoshal", "artist_id": "4"},
            ]
        )
        assert [item["name"] for item in merged] == ["Arijit Singh", "Shreya Ghoshal"]

    def test_every_provider_id_for_a_merged_artist_is_retained(self):
        merged = deduplicate_artists(
            [
                {"name": "Arijit Singh", "artist_id": "1"},
                {"name": "arijit singh", "artist_id": "2", "artwork_url": "u"},
            ]
        )
        assert set(merged[0]["provider_ids"]) == {"1", "2"}

    def test_the_richer_record_wins_but_keeps_its_position(self):
        merged = deduplicate_artists(
            [
                {"name": "Arijit Singh", "artist_id": "1"},
                {"name": "Sid Sriram", "artist_id": "9"},
                {"name": "arijit singh", "artist_id": "2", "artwork_url": "art"},
            ]
        )
        assert merged[0]["artwork_url"] == "art"
        assert merged[1]["name"] == "Sid Sriram"

    def test_same_name_in_different_languages_stays_separate(self):
        merged = deduplicate_artists(
            [
                {"name": "Rahul", "artist_id": "1", "language": "Tamil"},
                {"name": "Rahul", "artist_id": "2", "language": "Hindi"},
            ]
        )
        assert len(merged) == 2

    def test_an_unnamed_row_is_dropped_rather_than_merged_with_others(self):
        merged = deduplicate_artists([{"artist_id": ""}, {"name": "Real", "artist_id": "5"}])
        assert [item.get("name") for item in merged] == ["Real"]


class TestArtistSearchRanking:
    QUERY = "arijit"

    def test_an_exact_name_outranks_everything(self):
        assert artist_search_score({"name": "Arijit"}, self.QUERY) == 1000

    def test_a_prefix_beats_a_mid_word_substring(self):
        prefix = artist_search_score({"name": "Arijit Singh"}, self.QUERY)
        contains = artist_search_score({"name": "Best of Arijit collection"}, self.QUERY)
        assert prefix > contains

    def test_the_typed_artist_comes_first_even_when_listed_last(self):
        ranked = rank_search_results(
            [
                {"name": "Arijit Singh Fan Mix"},
                {"name": "Songs Like Arijit"},
                {"name": "Arijit Singh"},
            ],
            self.QUERY,
        )
        assert ranked[0]["name"] == "Arijit Singh"

    def test_full_name_query_ranks_the_full_name_first(self):
        ranked = rank_search_results(
            [
                {"name": "Arijit Singh Live"},
                {"name": "Arijit Singh"},
            ],
            "arijit singh",
        )
        assert ranked[0]["name"] == "Arijit Singh"

    def test_a_near_miss_still_scores_above_an_unrelated_name(self):
        close = artist_search_score({"name": "Arijit Sing"}, self.QUERY)
        unrelated = artist_search_score({"name": "Shreya Ghoshal"}, self.QUERY)
        assert close > unrelated

    def test_an_empty_query_scores_nothing(self):
        assert artist_search_score({"name": "Arijit Singh"}, "   ") == 0


class TestArtistScore:
    LANGUAGES = {"malayalam": 3, "tamil": 1}

    def score(self, artist, **kwargs):
        return artist_score(
            artist,
            kwargs.get("selected", set()),
            kwargs.get("recent", set()),
            kwargs.get("liked", set()),
            self.LANGUAGES,
        )

    def test_a_selected_artist_outranks_a_liked_one(self):
        selected = self.score({"artist_id": "1"}, selected={"1"})
        liked = self.score({"artist_id": "2"}, liked={"2"})
        assert selected > liked

    def test_a_liked_artist_outranks_a_merely_recent_one(self):
        liked = self.score({"artist_id": "1"}, liked={"1"})
        recent = self.score({"artist_id": "2"}, recent={"2"})
        assert liked > recent

    def test_a_preferred_language_lifts_an_otherwise_unknown_artist(self):
        preferred = self.score({"artist_id": "1", "language": "Malayalam"})
        other = self.score({"artist_id": "2", "language": "Hindi"})
        assert preferred > other

    def test_a_higher_priority_language_outranks_a_lower_one(self):
        malayalam = self.score({"artist_id": "1", "language": "Malayalam"})
        tamil = self.score({"artist_id": "2", "language": "Tamil"})
        assert malayalam > tamil

    def test_popularity_cannot_outweigh_an_explicit_selection(self):
        popular = self.score({"artist_id": "2", "popularity": 10_000_000})
        selected = self.score({"artist_id": "1"}, selected={"1"})
        assert selected > popular

    def test_a_merged_artist_matches_on_any_of_its_provider_ids(self):
        artist = {"artist_id": "9", "provider_ids": ["9", "1"]}
        assert self.score(artist, selected={"1"}) >= 100

    def test_ranking_orders_best_first_and_records_the_score(self):
        ranked = rank_artists(
            candidates=[{"artist_id": "2"}, {"artist_id": "1"}],
            languages=self.LANGUAGES,
            selected_artists={"1"},
            recent_artists=set(),
            liked_artists=set(),
        )
        assert ranked[0]["artist_id"] == "1"
        assert ranked[0]["recommendation_score"] >= 100


class TestSourceQuotas:
    def build(self, source, count):
        return [
            {"artist_id": f"{source}-{index}", "recommendation_source": source}
            for index in range(count)
        ]

    def test_familiar_artists_do_not_fill_the_whole_page(self):
        ranked = [
            *self.build("selected_artist", 40),
            *self.build("discovery", 20),
            *self.build("recent_artist", 20),
        ]
        page = apply_source_quotas(ranked, 20)
        sources = [item["recommendation_source"] for item in page]
        assert sources.count("selected_artist") <= 12
        assert "discovery" in sources

    def test_a_page_is_still_filled_when_a_source_is_missing(self):
        ranked = self.build("discovery", 30)
        assert len(apply_source_quotas(ranked, 20)) == 20

    def test_the_page_never_repeats_an_artist(self):
        ranked = [
            *self.build("selected_artist", 10),
            *self.build("liked_artist", 10),
            *self.build("discovery", 10),
        ]
        page = apply_source_quotas(ranked, 20)
        ids = [item["artist_id"] for item in page]
        assert len(ids) == len(set(ids))

    def test_an_empty_request_returns_nothing(self):
        assert apply_source_quotas(self.build("discovery", 5), 0) == []
