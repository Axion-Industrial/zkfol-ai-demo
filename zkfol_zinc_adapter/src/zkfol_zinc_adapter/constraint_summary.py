"""Practical summaries of the Zinc/CCS constraint shape.

This module deliberately separates the paper-level FOL/AIR dimensions from the
concrete scalar CCS/R1CS bridge used by this adapter.  The headline values here
answer questions such as: how many scalar variables does Zinc receive, what is
the constraint degree, and what integer bit bound is materialised?
"""

from __future__ import annotations

from typing import Any, Mapping


def _as_int(value: Any) -> int:
    if value is None:
        return 0
    if isinstance(value, bool):
        return int(value)
    if isinstance(value, int):
        return value
    if isinstance(value, str):
        return int(value)
    # JSON numbers are already int in normal Python json output, but keep a
    # defensive fallback for Decimal-like objects.
    return int(value)


def _bit_length(value: Any) -> int:
    return abs(_as_int(value)).bit_length()


def _next_power_of_two(value: int) -> int:
    value = max(1, int(value))
    return 1 << (value - 1).bit_length()


def _lin_degree_over_private_witness(terms: list[Any], *, public_inputs: int) -> int:
    """Degree of a linear form after fixing public inputs and the one coordinate.

    z is ordered as public inputs, then the constant-one coordinate, then private
    witness entries.  A form involving only public inputs/one is constant for a
    fixed instance; a form involving any witness coordinate is degree one.
    """
    constant_one_index = int(public_inputs)
    for term in terms or []:
        if not isinstance(term, (list, tuple)) or len(term) < 2:
            continue
        idx = int(term[0])
        coeff = _as_int(term[1])
        if coeff == 0:
            continue
        if idx > constant_one_index:
            return 1
    return 0


def compute_constraint_summary(export: Mapping[str, Any]) -> dict[str, Any]:
    """Compute the practical Zinc constraint-shape summary for an export."""
    dims = export.get("dimensions", {}) if isinstance(export.get("dimensions"), Mapping) else {}
    ccs = export.get("ccs", {}) if isinstance(export.get("ccs"), Mapping) else {}
    constraints = ccs.get("constraints", []) if isinstance(ccs.get("constraints"), list) else []
    public_values = ccs.get("public_inputs", []) if isinstance(ccs.get("public_inputs"), list) else []
    witness_values = ccs.get("witness", []) if isinstance(ccs.get("witness"), list) else []

    public_input_variables = int(dims.get("public_inputs") or len(public_values) or 0)
    private_witness_variables = int(dims.get("witness_variables") or len(witness_values) or 0)
    scalar_variables_unpadded = int(dims.get("z_len") or (public_input_variables + 1 + private_witness_variables))
    constraints_unpadded = int(dims.get("constraints") or len(constraints) or 0)
    padded_dim = _next_power_of_two(max(constraints_unpadded, scalar_variables_unpadded))

    public_bits = max((_bit_length(v) for v in public_values), default=0)
    witness_bits = max((_bit_length(v) for v in witness_values), default=0)
    coeff_bits = 0
    max_simplified_degree = 0
    bilinear_rows = 0
    linear_rows_after_fixing_public = 0
    constant_rows_after_fixing_public = 0
    max_terms_per_linear_form = 0
    max_terms_per_constraint_row = 0

    for row in constraints:
        if not isinstance(row, Mapping):
            continue
        row_terms_total = 0
        row_degrees = []
        for side in ("a", "b", "c"):
            terms = row.get(side, [])
            if not isinstance(terms, list):
                terms = []
            max_terms_per_linear_form = max(max_terms_per_linear_form, len(terms))
            row_terms_total += len(terms)
            for term in terms:
                if isinstance(term, (list, tuple)) and len(term) >= 2:
                    coeff_bits = max(coeff_bits, _bit_length(term[1]))
            row_degrees.append(_lin_degree_over_private_witness(terms, public_inputs=public_input_variables))
        max_terms_per_constraint_row = max(max_terms_per_constraint_row, row_terms_total)
        product_degree = row_degrees[0] + row_degrees[1]
        row_degree = max(product_degree, row_degrees[2])
        max_simplified_degree = max(max_simplified_degree, row_degree)
        if product_degree >= 2:
            bilinear_rows += 1
        elif row_degree == 1:
            linear_rows_after_fixing_public += 1
        else:
            constant_rows_after_fixing_public += 1

    materialized_bit_bound = max(public_bits, witness_bits, coeff_bits)
    name = str(export.get("name", ""))
    adapter_kind = str(export.get("adapter_kind", ""))
    if name.startswith("fibonacci_exact") and "compact" in adapter_kind:
        target_use_case = "compact exact-integer Fibonacci benchmark"
    elif name.startswith("fibonacci_exact"):
        target_use_case = "full exact-integer Fibonacci trace benchmark"
    elif name.startswith("efficient_power"):
        target_use_case = "efficient repeated-squaring power benchmark"
    elif name.startswith("standard_power"):
        target_use_case = "standard recursive power benchmark"
    else:
        target_use_case = "exported FOL-Zinc instance"

    return {
        "target_use_case": target_use_case,
        "constraint_model": "integer R1CS encoded as Zinc CCS_Z",
        "ccs_declared_degree": 2,
        "max_simplified_degree_over_private_witness": max_simplified_degree,
        "degree_explanation": (
            "Zinc receives R1CS/CCS rows of the form <A,z>*<B,z>=<C,z>, so the declared CCS degree is 2. "
            "After public inputs and the constant-one coordinate are fixed, some specialised rows simplify to degree 1."
        ),
        "constraints_unpadded": constraints_unpadded,
        "scalar_variables_unpadded": scalar_variables_unpadded,
        "private_witness_variables": private_witness_variables,
        "public_input_variables": public_input_variables,
        "constant_one_coordinates": 1,
        "padded_ccs_dimension_estimate": padded_dim,
        "bit_bound_delta": materialized_bit_bound,
        "max_public_input_bit_length": public_bits,
        "max_witness_value_bit_length": witness_bits,
        "max_constraint_coefficient_bit_length": coeff_bits,
        "bit_bound_explanation": (
            "bit_bound_delta is the largest absolute bit length among public input values, private witness values, "
            "and integer constraint coefficients materialised by this adapter. It is the practical delta-style bound "
            "for the exported integer relation, not a requirement that Zinc's sampled prime exceed every value."
        ),
        "bilinear_rows_observed": bilinear_rows,
        "linear_rows_after_fixing_public": linear_rows_after_fixing_public,
        "constant_rows_after_fixing_public": constant_rows_after_fixing_public,
        "max_terms_per_linear_form": max_terms_per_linear_form,
        "max_terms_per_constraint_row": max_terms_per_constraint_row,
        "paper_level_fol_shape": {
            "arity_ar_C": dims.get("arity"),
            "length_len_C": dims.get("length"),
            "max_B_bit_width": dims.get("max_bits"),
        },
    }


def attach_constraint_summary(export: dict[str, Any]) -> dict[str, Any]:
    """Add/update summary fields in an export JSON object and return it."""
    summary = compute_constraint_summary(export)
    export["zinc_constraint_summary"] = summary
    stats = export.setdefault("stats", {})
    if isinstance(stats, dict):
        stats.setdefault("max_abs_value_bit_length", summary["bit_bound_delta"])
        stats["max_abs_public_input_bit_length"] = summary["max_public_input_bit_length"]
        stats["max_abs_witness_bit_length"] = summary["max_witness_value_bit_length"]
        stats["max_abs_constraint_coefficient_bit_length"] = summary["max_constraint_coefficient_bit_length"]
        stats["zinc_bit_bound_delta"] = summary["bit_bound_delta"]
        stats["ccs_declared_degree"] = summary["ccs_declared_degree"]
        stats["max_simplified_constraint_degree"] = summary["max_simplified_degree_over_private_witness"]
    return export


def format_constraint_summary(export: Mapping[str, Any], *, padded: int | None = None) -> str:
    """Return a one-line practical summary for console benchmark output."""
    summary = compute_constraint_summary(export)
    pad = padded if padded is not None else summary["padded_ccs_dimension_estimate"]
    return (
        f"variables={summary['scalar_variables_unpadded']:,} scalar z entries "
        f"({summary['private_witness_variables']:,} private + {summary['public_input_variables']:,} public + 1 one); "
        f"constraints={summary['constraints_unpadded']:,}; "
        f"degree={summary['ccs_declared_degree']} CCS"
        f"/simplified≤{summary['max_simplified_degree_over_private_witness']}; "
        f"bit_bound_delta={summary['bit_bound_delta']:,} bits; "
        f"padded_dim≈{int(pad):,}"
    )
