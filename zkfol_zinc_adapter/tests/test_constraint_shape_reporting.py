from __future__ import annotations

import json
from pathlib import Path

from zkfol_zinc_adapter.constraint_summary import attach_constraint_summary, compute_constraint_summary, format_constraint_summary
from zkfol_zinc_adapter.direct_fibonacci import build_direct_fibonacci_ccs_export
from zkfol_zinc_adapter.explain import format_export_summary
from zkfol_zinc_adapter.view import format_inspection


def test_compact_fibonacci_reports_variables_degree_and_bit_bound():
    export = build_direct_fibonacci_ccs_export(10, check=True)
    summary = compute_constraint_summary(export)
    assert summary["scalar_variables_unpadded"] == 12
    assert summary["private_witness_variables"] == 10
    assert summary["public_input_variables"] == 1
    assert summary["ccs_declared_degree"] == 2
    assert summary["max_simplified_degree_over_private_witness"] == 1
    assert summary["bit_bound_delta"] >= 6
    assert export["zinc_constraint_summary"]["bit_bound_delta"] == summary["bit_bound_delta"]


def test_explain_and_inspect_include_constraint_shape():
    export = build_direct_fibonacci_ccs_export(10, check=True)
    explain = format_export_summary(export)
    inspect = format_inspection(export, matrix=False)
    for text in (explain, inspect):
        assert "Zinc constraint shape" in text
        assert "scalar" in text.lower()
        assert "degree" in text.lower()
        assert "bit-bound" in text.lower() or "bit_bound" in text.lower()


def test_summary_can_be_attached_to_legacy_export(synthetic_export):
    path = synthetic_export(name="legacy_shape", constraints=3, witness_variables=2, max_bits=7)
    data = json.loads(Path(path).read_text())
    data.pop("zinc_constraint_summary", None)
    attach_constraint_summary(data)
    assert data["zinc_constraint_summary"]["scalar_variables_unpadded"] == 4
    assert data["zinc_constraint_summary"]["ccs_declared_degree"] == 2
    assert data["stats"]["zinc_bit_bound_delta"] >= 0
    assert "variables=" in format_constraint_summary(data)
