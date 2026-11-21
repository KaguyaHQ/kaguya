"""Fixed examples for the read-only classification prototype."""

import unittest

from reproduce_tag_classification import analyze, build_mapping, ratio_matches


class TagClassificationTest(unittest.TestCase):
    def test_taxonomy_mapping_ignores_secondary_parents_and_technical_tags(self):
        tags = [
            {"id": "g1", "name": "Theme", "cat": "cont"},
            {"id": "g2", "name": "Story theme", "cat": "cont"},
            {"id": "g3", "name": "Erotic content", "cat": "ero"},
            {"id": "g4", "name": "Appearance", "cat": "cont"},
            {"id": "g5", "name": "Interface", "cat": "tech"},
        ]
        parents = [
            {"id": "g2", "parent": "g1", "main": True},
            {"id": "g3", "parent": "g1", "main": True},
            {"id": "g4", "parent": "g1", "main": False},
            {"id": "g5", "parent": "g1", "main": True},
            {"id": "g1", "parent": "g2", "main": True},
        ]
        mapping = build_mapping(tags, parents)
        self.assertEqual(mapping["g2"]["classification"], "narrative")
        self.assertEqual(mapping["g3"]["classification"], "ero")
        self.assertEqual(mapping["g4"]["classification"], "neutral")
        self.assertEqual(mapping["g5"]["classification"], "neutral")
        self.assertEqual(list(mapping.items()), list(build_mapping(tags[::-1], parents[::-1]).items()))

    def test_missing_theme_root_fails_instead_of_silently_classifying(self):
        with self.assertRaises(ValueError):
            build_mapping([], [])

    def test_vote_weight_and_ratio_boundaries(self):
        self.assertFalse(ratio_matches(0, 0))
        self.assertFalse(ratio_matches(19, 0))
        self.assertTrue(ratio_matches(15, 5))
        self.assertFalse(ratio_matches(14, 6))

    def novel(self, **changes):
        return {"id": "v65000", "title": "Example", "c_votecount": 0,
                "sexual_avg": 200, "image_votes": 5, "no_description": False, **changes}

    def test_a_positive_nukige_tag_is_evidence_not_an_automatic_replacement_rule(self):
        mapping = {"g214": {"classification": "ero", "name": "Nukige"}}
        result = analyze(mapping, [["v65000", "g214", 3, 1, 3]], [self.novel()])[0]
        self.assertTrue(result["explicit_nukige_tag"])
        self.assertFalse(result["ratio_match"])
        self.assertFalse(result["reconstructed_original_match"])

    def test_legacy_cover_heuristic_does_not_apply_to_newer_ids(self):
        old = analyze({}, [], [self.novel(id="v55000")])[0]
        new = analyze({}, [], [self.novel()])[0]
        self.assertTrue(old["legacy_cover_match"])
        self.assertFalse(new["legacy_cover_match"])
        self.assertFalse(old["ratio_match"])

    def test_disputed_tag_weight_cannot_help_the_ratio(self):
        mapping = {"g214": {"classification": "ero", "name": "Nukige"}}
        result = analyze(mapping, [["v65000", "g214", 0, 1, 3]], [self.novel()])[0]
        self.assertFalse(result["explicit_nukige_tag"])
        self.assertFalse(result["ratio_match"])

    def test_bestiality_ties_are_reported_and_resolved_consistently(self):
        mapping = {
            "g2": {"classification": "neutral", "name": "Other"},
            "g183": {"classification": "ero", "name": "Bestiality"},
        }
        signals = [["v65000", "g183", 1, 1, 1], ["v65000", "g2", 1, 1, 1]]
        result = analyze(mapping, signals, [self.novel()])[0]
        self.assertTrue(result["bestiality_rank_tied"])
        self.assertFalse(result["legacy_bestiality_match"])
        self.assertEqual(result, analyze(mapping, signals[::-1], [self.novel()])[0])


if __name__ == "__main__":
    unittest.main()
