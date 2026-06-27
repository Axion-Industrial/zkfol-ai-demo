from __future__ import annotations

import unittest

from zkfol.sk import (
    K_COMBINATOR,
    S_COMBINATOR,
    pretty_sk_term,
    sk_pair_int,
    sk_predicate,
    sk_sred_incorrect_target_int,
    sk_sred_source_int,
    sk_sred_target_int,
    sk_witness,
)
from zkfol.witness import MatrixInterpretation


class SkTests(unittest.TestCase):
    def test_bundled_sk_witness_is_valid(self) -> None:
        witness = sk_witness()
        predicate = sk_predicate()
        values = tuple(predicate.evaluate(witness, x) for x in range(1, witness.length + 1))
        self.assertEqual(values, (0,) * witness.length)
        self.assertTrue(witness.pointer_values_in_range(6))
        self.assertTrue(witness.pointer_values_in_range(7))

    def test_sred_rule_matches_the_included_paper(self) -> None:
        x = K_COMBINATOR
        y = S_COMBINATOR
        z = K_COMBINATOR
        self.assertEqual(pretty_sk_term(sk_sred_source_int(x, y, z)), "(((S K) S) K)")
        self.assertEqual(pretty_sk_term(sk_sred_target_int(x, y, z)), "((K K) (S K))")

    def test_incorrect_s_target_is_a_negative_control(self) -> None:
        x = K_COMBINATOR
        y = S_COMBINATOR
        z = K_COMBINATOR
        bad_col = (
            sk_sred_source_int(x, y, z),
            sk_sred_incorrect_target_int(x, y, z),
            x,
            y,
            z,
            1,
            1,
            1,
        )
        witness = MatrixInterpretation.from_columns([bad_col], name="SK")
        self.assertNotEqual(sk_predicate().evaluate(witness, 1), 0)


if __name__ == "__main__":
    unittest.main()
