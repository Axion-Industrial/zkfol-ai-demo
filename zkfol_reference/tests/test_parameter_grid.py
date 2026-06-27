from __future__ import annotations

import unittest

from zkfol.cli import ExampleInputs, select_examples, validate_example

POWER_CASES = [(0, 0), (2, 0), (2, 5), (3, 4)]
EFFICIENT_POWER_CASES = [(2, 8), (3, 5), (5, 3)]
FACTORIAL_CASES = [1, 2, 5, 7]
FIBONACCI_CASES = [1, 2, 6, 10]


class ParameterGridTests(unittest.TestCase):
    def assert_valid(self, selector: str, inputs: ExampleInputs) -> None:
        example = select_examples(selector, inputs)[0]
        report = validate_example(example, symbolic=False)
        self.assertTrue(report.pointer_range_ok, report)
        self.assertTrue(report.semantics_agree, report)
        self.assertTrue(report.all_zero, report)
        self.assertTrue(report.valid, report)

    def test_standard_power_grid(self) -> None:
        for base, exponent in POWER_CASES:
            with self.subTest(base=base, exponent=exponent):
                self.assert_valid("power", ExampleInputs(power_base=base, power_exponent=exponent))

    def test_efficient_power_grid(self) -> None:
        for base, exponent in EFFICIENT_POWER_CASES:
            with self.subTest(base=base, exponent=exponent):
                self.assert_valid("efficient", ExampleInputs(efficient_base=base, efficient_exponent=exponent))

    def test_factorial_grid(self) -> None:
        for n in FACTORIAL_CASES:
            with self.subTest(n=n):
                self.assert_valid("factorial", ExampleInputs(factorial_n=n))

    def test_fibonacci_grid(self) -> None:
        for n in FIBONACCI_CASES:
            with self.subTest(n=n):
                self.assert_valid("fibonacci", ExampleInputs(fibonacci_n=n))

    def test_symbolic_route_matches_fast_route_on_small_arithmetic_examples(self) -> None:
        inputs = ExampleInputs(power_base=2, power_exponent=3, efficient_base=2, efficient_exponent=5, factorial_n=4, fibonacci_n=6)
        for selector in ("power", "efficient", "factorial", "fibonacci"):
            with self.subTest(selector=selector):
                example = select_examples(selector, inputs)[0]
                fast = validate_example(example, symbolic=False)
                symbolic = validate_example(example, symbolic=True)
                self.assertEqual(fast.direct_values, symbolic.direct_values)
                self.assertEqual(fast.beta_values, symbolic.beta_values)
                self.assertTrue(symbolic.valid)


if __name__ == "__main__":
    unittest.main()
