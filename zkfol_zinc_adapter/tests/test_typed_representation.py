"""Tests for the typed (num/ptr) integer R1CS bridge in the adapter.

The typed route is the default; these tests pin down that it (a) is a valid,
self-consistent integer relation, (b) is dramatically smaller than the bitwise
route while (c) computing identically structured arithmetic, and (d) still
rejects tampered witnesses and binds public claims.
"""

from __future__ import annotations

import copy

import pytest
from zkfol.cli import ExampleInputs, select_examples

from zkfol_zinc_adapter.r1cs import R1CSError, build_ccs_export, check_export_relation

CASES = [
    ("power", ExampleInputs(power_base=3, power_exponent=13)),
    ("efficient", ExampleInputs(efficient_base=2, efficient_exponent=32)),
    ("factorial", ExampleInputs(factorial_n=7)),
    ("fibonacci", ExampleInputs(fibonacci_n=10)),
    ("sk", ExampleInputs()),
]


@pytest.mark.parametrize("selector,inputs", CASES)
def test_typed_export_is_valid_default_representation(selector, inputs):
    example = select_examples(selector, inputs)[0]
    export = build_ccs_export(example)  # default == typed
    check_export_relation(export)
    assert export["representation"] == "typed"
    assert export["zkfol"]["representation"] == "typed"
    assert export["adapter_kind"] == "typed_num_ptr_mkq_to_integer_r1cs_ccs"
    report = export["zkfol"]["reference_report"]
    assert report["all_zero"] is True
    assert report["semantics_agree"] is True
    assert report["pointer_range_ok"] is True
    # The breakdown partitions every constraint.
    assert sum(export["constraint_breakdown"].values()) == export["dimensions"]["constraints"]


@pytest.mark.parametrize("selector,inputs", CASES)
def test_typed_uses_no_bit_decomposition(selector, inputs):
    example = select_examples(selector, inputs)[0]
    export = build_ccs_export(example)
    stats = export["stats"]
    # No paper B-bit wires and no composed-bit lookups in the typed route.
    assert stats["b_wires"] == 0
    bd = export["constraint_breakdown"]
    assert bd["pointer_lookup_bit_equalities"] == 0
    assert bd["booleanity_bit_checks"] == stats["selector_wires"]  # only selectors are boolean
    assert stats["bit_wires"] == stats["selector_wires"]
    # Row-type annotations are present and label exactly the pointer rows as ptr.
    row_types = export["zkfol"]["row_types"]
    ptr_rows = {int(r) for r, t in row_types.items() if t == "ptr"}
    assert ptr_rows == set(example.pointer_rows)


@pytest.mark.parametrize("selector,inputs", CASES)
def test_typed_is_smaller_than_bitwise_but_same_arithmetic(selector, inputs):
    example = select_examples(selector, inputs)[0]
    typed = build_ccs_export(example, representation="typed")
    bitwise = build_ccs_export(example, representation="bitwise")
    check_export_relation(typed)
    check_export_relation(bitwise)
    # The optimisation strictly reduces constraint and witness counts.
    assert typed["dimensions"]["constraints"] < bitwise["dimensions"]["constraints"]
    assert typed["dimensions"]["witness_variables"] < bitwise["dimensions"]["witness_variables"]
    # ...without changing the arithmetic gate structure of mkQ_x(<phi>).
    tb = typed["constraint_breakdown"]
    bb = bitwise["constraint_breakdown"]
    assert tb["mkq_arithmetic_gates"] == bb["mkq_arithmetic_gates"]
    assert tb["mkq_zero_checks"] == bb["mkq_zero_checks"] == typed["dimensions"]["length"]
    # Both routes agree the witness is valid.
    assert typed["zkfol"]["reference_report"]["all_zero"] is True
    assert bitwise["zkfol"]["reference_report"]["all_zero"] is True


def test_typed_export_rejects_tampered_witness():
    example = select_examples("power", ExampleInputs(power_base=2, power_exponent=4))[0]
    export = build_ccs_export(example, public_final=True)
    check_export_relation(export)
    tampered = copy.deepcopy(export)
    original = int(tampered["ccs"]["witness"][0])
    tampered["ccs"]["witness"][0] = str(original + 1)
    with pytest.raises(R1CSError):
        check_export_relation(tampered)


def test_typed_public_final_binds_final_cells():
    example = select_examples("efficient", ExampleInputs(efficient_base=2, efficient_exponent=32))[0]
    export = build_ccs_export(example, public_final=True)  # typed
    check_export_relation(export)
    assert export["benchmark_claim"]["public_final"] is True
    assert export["ccs"]["public_input_names"] == [
        "public_zero",
        "claim_final_base",
        "claim_final_exponent",
        "claim_final_output",
    ]
    assert export["ccs"]["public_inputs"][1:] == ["2", "32", str(2**32)]
    assert export["constraint_breakdown"]["public_input_binding_checks"] == 3


def test_typed_pointer_cells_carry_one_hot_range_check():
    example = select_examples("fibonacci", ExampleInputs(fibonacci_n=6))[0]
    export = build_ccs_export(example)
    length = export["dimensions"]["length"]
    # Two pointer rows (C3, C4), each range-checked at every column.
    assert export["constraint_breakdown"]["pointer_range_one_hot_checks"] == 2 * length
    # The typed route replaces composed-bit lookups with integer-value lookups.
    assert export["constraint_breakdown"]["pointer_lookup_value_equalities"] > 0
    assert export["constraint_breakdown"]["pointer_lookup_bit_equalities"] == 0


def test_unknown_representation_raises():
    example = select_examples("power", ExampleInputs(power_base=2, power_exponent=3))[0]
    with pytest.raises(R1CSError):
        build_ccs_export(example, representation="nonsense")
