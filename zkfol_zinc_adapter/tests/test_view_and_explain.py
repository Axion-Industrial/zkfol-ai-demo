from __future__ import annotations

from zkfol.cli import ExampleInputs, select_examples

from zkfol_zinc_adapter.direct_fibonacci import build_direct_fibonacci_ccs_export
from zkfol_zinc_adapter.explain import format_export_summary
from zkfol_zinc_adapter.r1cs import build_ccs_export
from zkfol_zinc_adapter.view import concrete_statement_lines, format_inspection


def test_explanation_text_mentions_zinc_and_meaning():
    example = select_examples("factorial", ExampleInputs(factorial_n=4))[0]
    export = build_ccs_export(example)
    text = format_export_summary(export)
    assert "What is being proved" in text
    assert "Constraint breakdown" in text
    assert "Zinc" in text
    assert "zero" in text.lower()


def test_inspection_mentions_concrete_power_and_matrix_and_constraints():
    example = select_examples("power", ExampleInputs(power_base=2, power_exponent=4))[0]
    export = build_ccs_export(example, public_final=True)
    text = format_inspection(export, matrix=True, constraints=True, constraint_head=1, constraint_tail=1)
    assert "2^4 = 16" in text
    assert "FOL witness matrix C" in text
    assert "C1 base" in text
    assert "CCS/R1CS constraint preview" in text


def test_inspection_abbreviates_large_fibonacci_matrix_preview():
    export = build_direct_fibonacci_ccs_export(40, check=True, include_witness_rows=True)
    text = format_inspection(export, matrix=True, matrix_head=3, matrix_tail=3)
    assert "FOL witness matrix C" in text
    assert "..." in text
    assert "F_40" in text


def test_concrete_statement_lines_for_fibonacci_are_explicit_and_non_modular():
    export = build_direct_fibonacci_ccs_export(1000, check=True)
    lines = concrete_statement_lines(export)
    joined = "\n".join(lines)
    assert "F_1000" in joined
    assert "no modulo 2^64" in joined
    assert "Public claim" in joined
