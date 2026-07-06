"""Detector-driven compilation from a FOL predicate to a doubling export.

The pass in two stages: :func:`detect_linear_recurrence` extracts a
recurrence descriptor from the predicate (or refuses with a reason), and
:func:`compile_doubling_export` emits a logarithmic trace driven by the
descriptor alone — coefficients (p, q) and bases (x1, x2) parameterize the
general order-2 pair walk in :mod:`doubling_trace`; nothing here is
Fibonacci-specific. Recurrences of other orders are refused pending the
general companion matrix-power emitter.

The emitted value uses the standard reduction of any order-2 recurrence to
the (0, 1)-initialized kernel sequence U (U(1)=1, U(2)=p):

    x(n) = x2 * U(n-1) + q * x1 * U(n-2)

so the trace walks the pair (U(e), U(e+1)) to e = n-2 by doubling, and the
final binding is a free linear combination. Legality reminder: this rewrite
proves the value claim x(n) = <constant>; it is not a trace attestation.
"""

from __future__ import annotations

from typing import Any

from zkfol.ast import Formula

from .direct_fibonacci import _short_decimal
from .doubling_trace import TrackedValue, emit_geometric_trace, emit_pair_trace
from .export_scaffold import assemble_builder_export, relation_constant_binding
from .fast_doubling_fibonacci import _doubling_schedule
from .r1cs import R1CSBuilder
from .recurrence import detect_linear_recurrence


class RecurrenceCompileError(ValueError):
    pass


def compile_doubling_export(
    predicate: Formula, n: int, *, cell_values: dict[int, int] | None = None, check: bool = False
) -> dict[str, Any]:
    detection = detect_linear_recurrence(predicate)
    if detection.descriptor is None:
        raise RecurrenceCompileError(f"predicate is not a supported linear recurrence: {detection.reason}")
    descriptor = detection.descriptor
    coefficients = dict(descriptor.coefficients)
    cell_rows = [c[1] for c in coefficients.values() if isinstance(c, tuple)]

    builder = R1CSBuilder(public_inputs=[0], public_input_names={0: "public_zero"})
    if descriptor.order == 2 and not cell_rows:
        p, q = coefficients[-1], coefficients[-2]
        # bases at any contiguous start (s, s+1); walk positions with the
        # first base at position 1 — the recurrence is shift-invariant.
        (start_index, x1), (_, x2) = descriptor.initial_values
        position = n - start_index + 1
        if position < 1:
            raise RecurrenceCompileError(f"n={n} precedes the base case index {start_index}")
        if position == 1:
            final_lin, output = builder.const(x1), x1
        elif position == 2:
            final_lin, output = builder.const(x2), x2
        else:
            a, b = emit_pair_trace(builder, _doubling_schedule(position - 2), "cfin", p=p, q=q)
            final = b.scale(x2) + a.scale(q * x1)
            final_lin, output = final.lin, final.value
        steps = len(_doubling_schedule(position - 2)) if position >= 3 else 0
    elif descriptor.order == 1 and cell_rows:
        coeff_row = cell_rows[0]
        pinned = dict(descriptor.coefficient_pins).get(coeff_row)
        supplied = None if cell_values is None else cell_values.get(coeff_row)
        if pinned is not None and supplied is not None and supplied != pinned:
            raise RecurrenceCompileError(
                f"cell_values supplies {supplied} for coefficient row {coeff_row}, "
                f"but the predicate pins it to {pinned}"
            )
        base_value = pinned if pinned is not None else supplied
        if base_value is None:
            raise RecurrenceCompileError(
                f"the coefficient is the trace-constant cell row {coeff_row}; its public "
                "value must be supplied via cell_values"
            )
        (start_index, start_value), = descriptor.initial_values
        exponent = n - start_index
        if exponent < 0:
            raise RecurrenceCompileError(f"n={n} precedes the base case index {start_index}")
        base_wire = builder.alloc_witness(f"coeff_row_{coeff_row}", base_value)
        base = TrackedValue(builder.wire(base_wire), base_value)
        builder.add_constraint(
            base.lin, builder.const(1), builder.const(base_value),
            f"public_binding:coefficient_cell_row_{coeff_row}",
        )
        if exponent == 0:
            final_lin, output = builder.const(start_value), start_value
        else:
            power = emit_geometric_trace(builder, _doubling_schedule(exponent), base, "geo")
            final = power.scale(start_value)
            final_lin, output = final.lin, final.value
        steps = len(_doubling_schedule(exponent)) if exponent >= 1 else 0
    else:
        raise RecurrenceCompileError(
            f"recognized an order-{descriptor.order} recurrence with coefficients "
            f"{descriptor.coefficients}; the general companion matrix-power emitter "
            "for this shape is future work"
        )
    builder.add_constraint(
        final_lin, builder.const(1), builder.const(output),
        "public_binding:claim_recurrence_n_exact",
    )
    statement_line = (
        f"Concrete computation: term n={n} of the order-{descriptor.order} recurrence with "
        f"coefficients {descriptor.coefficients} and bases {descriptor.initial_values}"
        + (f", coefficient cell values {cell_values}" if cell_rows else "")
        + f"; value {_short_decimal(output)}."
    )
    sections: dict[str, Any] = {
        "recurrence_descriptor": {
            "order": descriptor.order,
            "index_row": descriptor.index_row,
            "value_row": descriptor.value_row,
            "coefficients": list(descriptor.coefficients),
            "initial_values": list(descriptor.initial_values),
        },
        "zkfol": {
            "pointer_rows": [],
            "paper_reference": "Detector-compiled formulation; see recurrence.py for the licensing analysis.",
            "mathematical_description": statement_line,
            "witness_convention": (
                "Kernel pair (U(e), U(e+1)) walked by general doubling identities; "
                "final value bound as x2*U(n-1) + q*x1*U(n-2)."
            ),
        },
    }
    return assemble_builder_export(
        builder,
        name=f"recurrence_dbl_o{descriptor.order}_n{n}",
        description=statement_line,
        adapter_kind="detector_driven_order2_doubling_to_integer_r1cs_ccs",
        soundness_note=(
            "Compiled from the FOL predicate by C-finite detection; the doubling trace is "
            "parameterized entirely by the extracted descriptor (coefficients and bases). "
            "Value claim, not a trace attestation."
        ),
        row_orientation="products_and_positive_binding",
        profile="detector-compiled-doubling",
        length=steps,
        public_claims=[
            {"name": "claim_n", "value": str(n), "encoded_as": "public_relation_structure"},
            {"name": "claim_recurrence_n_exact", "value": str(output), "encoded_as": "public_ccs_constant"},
        ],
        public_bindings=[
            relation_constant_binding("claim_n", n),
            relation_constant_binding("claim_recurrence_n_exact", output),
        ],
        benchmark_claim={
            "public_final": True,
            "description": statement_line,
            "concrete_statement": [statement_line],
        },
        exact_arithmetic={
            "modulus": None,
            "modulus_note": "No modular reduction is used in this export.",
            "n": n,
            "output_bit_length": output.bit_length(),
            "output_decimal_digits": len(str(output)),
            "output_decimal_preview": _short_decimal(output),
        },
        sections=sections,
        check=check,
    )
