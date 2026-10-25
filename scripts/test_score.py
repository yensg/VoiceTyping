import unittest
from score import score


class ScoreTests(unittest.TestCase):
    def test_normalization_and_known_substitution(self):
        result = score([{'reference': 'Fail in red.', 'hypothesis': 'fail in bread', 'key_terms': ['red']}])
        self.assertEqual(result['wer'], 1 / 3)
        self.assertEqual(result['key_term_misses'], [{'row': 1, 'term': 'red'}])
        self.assertEqual(score([{'reference': 'CODEX, café!', 'hypothesis': 'codex café'}])['wer'], 0)

    def test_insertions_deletions_and_empty_reference(self):
        self.assertEqual(score([{'reference': 'one two', 'hypothesis': 'one'}])['word_edits'], 1)
        self.assertEqual(score([{'reference': '', 'hypothesis': 'noise'}])['word_edits'], 1)
        self.assertIsNone(score([])['wer'])
