from __future__ import annotations

import copy

import pytest
from zkfol.cli import ExampleInputs, select_examples

from zkfol_zinc_adapter import __version__
from zkfol_zinc_adapter.r1cs import R1CSError, build_ccs_export, check_export_relation


def test_power_export_checks_reference_semantics():
    example = select_examples("power", ExampleInputs(power_base=3, power_exponent=3))[0]
    export = build_ccs_export(example)
    check_export_relation(export)
    assert export["zkfol"]["reference_report"]["all_zero"] is True
    assert export["dimensions"]["constraints"] > 0


def test_factorial_export_checks_pointer_ranges():
    example = select_examples("factorial", ExampleInputs(factorial_n=4))[0]
    export = build_ccs_export(example)
    check_export_relation(export)
    assert export["zkfol"]["reference_report"]["pointer_range_ok"] is True


def test_export_carries_exposition_breakdown_and_current_version():
    example = select_examples("power", ExampleInputs(power_base=3, power_exponent=3))[0]
    export = build_ccs_export(example)
    assert export["adapter_version"] == __version__
    assert "what_is_being_proved" in export["exposition"]
    assert export["constraint_breakdown"]["mkq_zero_checks"] == export["dimensions"]["length"]
    assert sum(export["constraint_breakdown"].values()) == export["dimensions"]["constraints"]


def test_public_final_large_power_binds_final_cells_as_public_inputs():
    example = select_examples("efficient", ExampleInputs(efficient_base=2, efficient_exponent=32))[0]
    export = build_ccs_export(example, public_final=True)
    check_export_relation(export)
    assert export["schema"] == "zkfol-zinc-ccs-v2"
    assert export["benchmark_claim"]["public_final"] is True
    assert export["ccs"]["public_input_names"] == [
        "public_zero",
        "claim_final_base",
        "claim_final_exponent",
        "claim_final_output",
    ]
    assert export["ccs"]["public_inputs"][1:] == ["2", "32", str(2**32)]
    assert export["constraint_breakdown"]["public_input_binding_checks"] == 3


def test_checker_rejects_tampered_witness_values():
    example = select_examples("power", ExampleInputs(power_base=2, power_exponent=4))[0]
    export = build_ccs_export(example, public_final=True)
    check_export_relation(export)
    tampered = copy.deepcopy(export)
    original = int(tampered["ccs"]["witness"][0])
    tampered["ccs"]["witness"][0] = str(original + 1)
    with pytest.raises(R1CSError):
        check_export_relation(tampered)


def test_checker_rejects_out_of_range_constraint_indices():
    example = select_examples("power", ExampleInputs(power_base=2, power_exponent=3))[0]
    export = build_ccs_export(example)
    bad = copy.deepcopy(export)
    bad["ccs"]["constraints"][0]["a"].append([bad["dimensions"]["z_len"] + 99, "1"])
    with pytest.raises(R1CSError):
        check_export_relation(bad)
