"""Shared assembly for builder-driven zkfol-zinc-ccs-v2 exports.

Every formulation exporter ends the same way: check the builder's
constraints, serialize them, and wrap them in the schema envelope
(dimensions, ccs, wire_names, constraint_breakdown, stats, summary
attachment, optional relation check). This module owns that envelope so a
schema change happens in one place; each exporter contributes only what is
distinctive about its statement — claims, bindings, and extra sections such
as ``crt`` or ``recurrence_descriptor``, which appear between ``ccs`` and
``wire_names`` in the order given.
"""

from __future__ import annotations

from typing import Any

from .constraint_summary import attach_constraint_summary
from .direct_fibonacci import _breakdown, _max_abs_from_export_parts
from .metadata import ADAPTER_VERSION
from .r1cs import R1CSBuilder, check_export_relation


def assemble_builder_export(
    builder: R1CSBuilder,
    *,
    name: str,
    description: str,
    adapter_kind: str,
    soundness_note: str,
    row_orientation: str,
    profile: str,
    length: int,
    public_claims: list[dict[str, str]],
    public_bindings: list[dict[str, Any]],
    benchmark_claim: dict[str, Any],
    exact_arithmetic: dict[str, Any],
    sections: dict[str, Any] | None = None,
    max_bits: int | None = None,
    check: bool = False,
) -> dict[str, Any]:
    builder.check_all_constraints()
    constraints = [constraint.to_json() for constraint in builder.constraints]
    max_abs = _max_abs_from_export_parts(builder.public_inputs, builder.witness_values, constraints)
    breakdown = _breakdown(constraints)
    public_input_names = [
        builder.public_input_names.get(i, f"public_input_{i}") for i in range(len(builder.public_inputs))
    ]
    export: dict[str, Any] = {
        "schema": "zkfol-zinc-ccs-v2",
        "name": name,
        "description": description,
        "adapter_kind": adapter_kind,
        "adapter_version": ADAPTER_VERSION,
        "soundness_note": soundness_note,
        "row_orientation": row_orientation,
        "fibonacci_profile": profile,
        "dimensions": {
            "arity": 2,
            "length": length,
            "max_bits": max_bits
            if max_bits is not None
            else max((value.bit_length() for value in builder.witness_values), default=1),
            "public_inputs": len(builder.public_inputs),
            "public_input_names": public_input_names,
            "witness_variables": len(builder.witness_values),
            "z_len": len(builder.z_vector()),
            "constraints": len(constraints),
        },
        "ccs": {
            "public_inputs": [str(value) for value in builder.public_inputs],
            "public_input_names": public_input_names,
            "public_claims": public_claims,
            "public_bindings": public_bindings,
            "witness": [str(value) for value in builder.witness_values],
            "constraints": constraints,
        },
        **(sections or {}),
        "wire_names": {str(k): v for k, v in sorted(builder.wire_names.items())},
        "constraint_breakdown": breakdown,
        "benchmark_claim": benchmark_claim,
        "exact_arithmetic": exact_arithmetic,
        "stats": {
            "bit_wires": 0,
            "b_wires": 0,
            "selector_wires": 0,
            "constraint_breakdown": breakdown,
            "max_abs_value_bit_length": int(max_abs).bit_length(),
            "max_abs_value_decimal": str(max_abs),
        },
    }
    attach_constraint_summary(export)
    if check:
        check_export_relation(export)
    return export


def relation_constant_binding(name: str, value: int | str) -> dict[str, Any]:
    return {"public_index": None, "binding_kind": "relation_constant", "name": name, "value": str(value)}
