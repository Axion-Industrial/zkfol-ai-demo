from __future__ import annotations

import unittest

from zkfol.cli import ExampleInputs, select_examples
from zkfol.fast_beta import beta_all_fast
from zkfol.witness import MatrixInterpretation, PointerRangeCheck


class NegativeControlTests(unittest.TestCase):
    def test_corrupting_power_output_is_detected(self) -> None:
        example = select_examples("power", ExampleInputs(power_base=2, power_exponent=4))[0]
        rows = example.witness.as_lists()
        rows[2][-1] += 1
        bad = MatrixInterpretation(rows, name=example.witness.name)
        direct = tuple(example.predicate.evaluate(bad, x) for x in range(1, bad.length + 1))
        beta = tuple(beta_all_fast(example.predicate, bad))
        self.assertEqual(direct, beta)
        self.assertFalse(all(value == 0 for value in direct))

    def test_pointer_range_failure_is_detected(self) -> None:
        example = select_examples("fibonacci", ExampleInputs(fibonacci_n=6))[0]
        rows = example.witness.as_lists()
        rows[2][-1] = example.witness.length + 1
        bad = MatrixInterpretation(rows, name=example.witness.name)
        self.assertFalse(PointerRangeCheck(3).is_satisfied(bad))
        self.assertFalse(all(check.is_satisfied(bad) for check in example.range_checks))


if __name__ == "__main__":
    unittest.main()
