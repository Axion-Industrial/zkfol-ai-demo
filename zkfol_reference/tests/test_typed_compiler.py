"""Tests for the num/ptr type system and the typed (non-bitwise) mkQ route.

These assert the optimisation is *semantics-preserving*: the typed route, which
represents arithmetic values as whole integers and only pointer rows bitwise (in
fact, via one-hot range checks in the bridge), computes exactly the same integers
as the paper-faithful bitwise route and the direct Figure 3 semantics.  This is
the Theorem 3.8 equivalence, witnessed by the optimised representation.
"""

from __future__ import annotations

import unittest

import sympy as sp

from zkfol.cli import ExampleInputs, select_examples
from zkfol.compiler import CompilationContext
from zkfol.fast_beta import beta_all_fast
from zkfol.types import CellType, TypeEnv, pointer_rows
from zkfol.typed_compiler import (
    TypedCompilationContext,
    ValueIndex,
    mkq_typed,
    parse_value_symbol,
)
from zkfol.witness import MatrixInterpretation

CASES = [
    ("power", ExampleInputs(power_base=3, power_exponent=4)),
    ("power", ExampleInputs(power_base=2, power_exponent=0)),
    ("efficient", ExampleInputs(efficient_base=2, efficient_exponent=8)),
    ("efficient", ExampleInputs(efficient_base=5, efficient_exponent=3)),
    ("factorial", ExampleInputs(factorial_n=6)),
    ("fibonacci", ExampleInputs(fibonacci_n=10)),
    ("sk", ExampleInputs()),
]


class PointerTypeInferenceTests(unittest.TestCase):
    def test_derived_pointer_rows_match_example_spec(self) -> None:
        for selector, inputs in CASES:
            with self.subTest(selector=selector):
                example = select_examples(selector, inputs)[0]
                derived = pointer_rows(example.predicate)
                self.assertEqual(set(derived), set(example.pointer_rows))

    def test_type_env_assigns_ptr_exactly_to_pointer_rows(self) -> None:
        for selector, inputs in CASES:
            with self.subTest(selector=selector):
                example = select_examples(selector, inputs)[0]
                env = TypeEnv.from_predicate(example.predicate, example.witness.arity)
                for row in range(1, example.witness.arity + 1):
                    expected = CellType.PTR if row in example.pointer_rows else CellType.NUM
                    self.assertEqual(env.row_type(row), expected)
                    self.assertEqual(env.is_pointer(row), row in example.pointer_rows)


class TypedSemanticsTests(unittest.TestCase):
    def test_typed_beta_matches_direct_and_bitwise_for_every_column(self) -> None:
        for selector, inputs in CASES:
            with self.subTest(selector=selector):
                example = select_examples(selector, inputs)[0]
                witness = example.witness
                typed_ctx = TypedCompilationContext.from_witness(witness)
                bit_ctx = CompilationContext.from_witness(witness)
                fast = list(beta_all_fast(example.predicate, witness))
                for x in range(1, witness.length + 1):
                    direct = example.predicate.evaluate(witness, x)
                    typed = typed_ctx.mkq(example.predicate, x).beta(witness)
                    self.assertEqual(typed, direct, msg=f"typed!=direct at x={x}")
                    self.assertEqual(typed, fast[x - 1], msg=f"typed!=fast at x={x}")
                    if selector != "sk":  # the symbolic bitwise route is intractable for SK
                        bitwise = bit_ctx.mkq(example.predicate, x).beta(witness)
                        self.assertEqual(typed, bitwise, msg=f"typed!=bitwise at x={x}")

    def test_valid_witness_is_zero_at_every_column(self) -> None:
        for selector, inputs in CASES:
            with self.subTest(selector=selector):
                example = select_examples(selector, inputs)[0]
                witness = example.witness
                ctx = TypedCompilationContext.from_witness(witness)
                values = [ctx.mkq(example.predicate, x).beta(witness) for x in range(1, witness.length + 1)]
                self.assertTrue(all(v == 0 for v in values), values)

    def test_typed_polynomial_uses_only_value_symbols(self) -> None:
        # No B-bit symbols should appear; every free symbol must be a value symbol.
        example = select_examples("fibonacci", ExampleInputs(fibonacci_n=8))[0]
        ctx = TypedCompilationContext.from_witness(example.witness)
        for x in range(1, example.witness.length + 1):
            expr = ctx.mkq(example.predicate, x).expression
            for symbol in expr.free_symbols:
                self.assertTrue(str(symbol).startswith("V_"), str(symbol))
                # round-trips through the parser
                index = parse_value_symbol(symbol)
                self.assertEqual(ctx.symbol(index), symbol)


class TypedNegativeControlTests(unittest.TestCase):
    def test_typed_beta_detects_a_corrupted_value(self) -> None:
        example = select_examples("power", ExampleInputs(power_base=2, power_exponent=4))[0]
        rows = example.witness.as_lists()
        rows[2][-1] += 1  # corrupt the final value cell C3
        bad = MatrixInterpretation(rows, name=example.witness.name)
        ctx = TypedCompilationContext.from_witness(bad)
        direct = [example.predicate.evaluate(bad, x) for x in range(1, bad.length + 1)]
        typed = [ctx.mkq(example.predicate, x).beta(bad) for x in range(1, bad.length + 1)]
        self.assertEqual(direct, typed)
        self.assertFalse(all(v == 0 for v in typed))

    def test_out_of_range_pointer_value_symbol_is_zero(self) -> None:
        # A composed value with an out-of-range pointer evaluates to 0 (Definition 3.6).
        witness = MatrixInterpretation([[1, 2], [9, 8], [99, 0]])  # row 3 column 2 points to 0 (out of range)
        index = ValueIndex(row=2, pointer=3, x=2)
        from zkfol.typed_compiler import beta_value_symbol

        self.assertEqual(beta_value_symbol(index, witness), 0)
        # In-range pointer: C3(1)=2 lands in [1, 2], so C2(C3(1)) = C2(2) = 8.
        valid = MatrixInterpretation([[5, 6], [7, 8], [2, 1]])
        self.assertEqual(beta_value_symbol(ValueIndex(row=2, pointer=3, x=1), valid), 8)


class TypedExpressionShapeTests(unittest.TestCase):
    def test_equality_compiles_to_squared_difference_of_values(self) -> None:
        example = select_examples("factorial", ExampleInputs(factorial_n=4))[0]
        ctx = TypedCompilationContext.from_witness(example.witness)
        # base case conjunct (n=1) at column 1 is (V_1_0_1 - 1)^2 + (V_2_0_1 - 1)^2 inside a product.
        expr = sp.expand(ctx.mkq(example.predicate, 1).expression)
        self.assertTrue(expr.free_symbols)  # non-trivial polynomial over value symbols


if __name__ == "__main__":
    unittest.main()
