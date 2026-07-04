"""Fast-doubling exact-Fibonacci CCS exporter.

The compact direct trace in :mod:`zkfol_zinc_adapter.direct_fibonacci` proves
F_n with a length-n trace: one row per index. This module proves the same
public claim with a logarithmic trace using the doubling identities

    F(2k)   = F(k) * (2*F(k+1) - F(k))
    F(2k+1) = F(k)^2 + F(k+1)^2

Walking the bits of n most-significant-first with state pair
(a, b) = (F(k), F(k+1)) costs exactly three multiplication rows per bit:
t1 = a*(2b - a), t2 = a^2, t3 = b^2. The next state needs no wires or copy
rows of its own: after a doubling step the pair is (t1, t2 + t3) for bit 0
and (t2 + t3, t1 + t2 + t3) for bit 1, all linear forms over existing wires,
which the next step's multiplication slots absorb directly.

The claim binding is identical to the compact profile: n is public relation
structure (it is the bit pattern of the trace itself) and the exact integer
F_n is a public CCS constant on the final row. Nothing is reduced modulo
2^64. This is the formulation for value claims ("F_n equals this integer");
it deliberately does not attest the step-by-step trace.
"""

from __future__ import annotations

from typing import Any

from .direct_fibonacci import FIBONACCI_REFERENCE, _short_decimal
from .doubling_trace import emit_doubling_trace
from .export_scaffold import assemble_builder_export, relation_constant_binding
from .metadata import ADAPTER_VERSION
from .r1cs import R1CSBuilder


def _doubling_schedule(n: int) -> list[int]:
    """Bits of n after the leading one, most significant first."""
    return [int(bit) for bit in bin(n)[3:]]


def build_fast_doubling_fibonacci_ccs_export(n: int, *, check: bool = False) -> dict[str, Any]:
    if n < 1:
        raise ValueError("n must be positive")

    public_inputs = [0]
    public_input_names = {0: "public_zero"}
    builder = R1CSBuilder(public_inputs=public_inputs, public_input_names=public_input_names)

    final = emit_doubling_trace(builder, _doubling_schedule(n), "exact")
    output = final.value
    builder.add_constraint(
        final.lin, builder.const(1), builder.const(output),
        "public_binding:claim_fibonacci_n_exact",
    )

    steps = len(_doubling_schedule(n))
    fib_digits = len(str(output))
    fib_bits = output.bit_length()
    statement_line = f"Concrete computation: exact non-modular Fibonacci F_{n} = {_short_decimal(output)}."

    sections: dict[str, Any] = {
        "zkfol": {
            "pointer_rows": [],
            "paper_reference": FIBONACCI_REFERENCE,
            "mathematical_description": (
                f"Exact integer Fibonacci via fast doubling: state (F(k), F(k+1)) advanced along the "
                f"{steps} bits of n after the leading bit, proving public relation constant F_{n}."
            ),
            "witness_convention": (
                "Three product wires per doubling step: c=F(2k), a_sq=F(k)^2, b_sq=F(k+1)^2. "
                "The state pair is not materialised; it is carried as linear forms."
            ),
        },
        "exposition": {
            "adapter_version": ADAPTER_VERSION,
            "what_this_file_is": (
                "A self-contained exact-integer Fibonacci benchmark input for the Rust Zinc runner, "
                "using the fast-doubling (logarithmic trace) formulation of the same public claim as "
                "the compact direct profile."
            ),
            "concrete_statement": [
                statement_line,
                f"Output size: {fib_bits} bits; no modulo 2^64 reduction is used.",
                "Public claim: n is the trace's bit pattern; the exact Fibonacci output is a public CCS constant.",
            ],
            "what_is_being_proved": (
                f"Knowledge of doubling-step values consistent with the identities "
                f"F(2k)=F(k)(2F(k+1)-F(k)) and F(2k+1)=F(k)^2+F(k+1)^2 along the bits of {n}, "
                f"ending at the public relation constant F_{n}. This is a value claim, not a "
                "step-by-step trace attestation."
            ),
            "pipeline": [
                {"stage": "Fast-doubling schedule", "meaning": f"The bits of n={n} after the leading bit fix {steps} doubling steps."},
                {"stage": "Integer R1CS/CCS", "meaning": "Three product rows per step; state carried as linear forms; final positive binding row."},
                {"stage": "Zinc prove/verify", "meaning": "The Rust runner checks the integer relation, pads CCS dimensions, then invokes Zinc."},
            ],
            "benchmarking_notes": [
                "Same public claim as fibonacci_exact_n{n}; logarithmic trace instead of length-n trace.",
                "Values remain exact wide integers; combine with CRT residue channels to shrink integer width.",
            ],
        },
    }
    return assemble_builder_export(
        builder,
        name=f"fibonacci_fastdbl_n{n}",
        description=f"Exact non-modular integer Fibonacci F_{n} via fast doubling (log-n trace).",
        adapter_kind="fast_doubling_fibonacci_to_integer_r1cs_ccs",
        soundness_note=(
            "Fast-doubling formulation of the exact Fibonacci value claim. The trace walks the bits "
            "of n with the identities F(2k)=F(k)(2F(k+1)-F(k)) and F(2k+1)=F(k)^2+F(k+1)^2; each bit "
            "costs three multiplication rows and the state pair is carried as linear forms over "
            "existing wires. The public claim (exact F_n) matches the compact direct profile; the "
            "witness relation is a different, logarithmic trace. Nothing is reduced modulo 2^64."
        ),
        row_orientation="products_and_positive_binding",
        profile="fast-doubling",
        length=steps,
        public_claims=[
            {"name": "claim_n", "value": str(n), "encoded_as": "public_relation_structure"},
            {"name": "claim_fibonacci_n_exact", "value": str(output), "encoded_as": "public_ccs_constant"},
        ],
        public_bindings=[
            relation_constant_binding("claim_n", n),
            relation_constant_binding("claim_fibonacci_n_exact", output),
        ],
        benchmark_claim={
            "public_final": True,
            "description": (
                f"Public relation constants bind n={n} (as the trace bit pattern) and exact F_{n}; "
                "arithmetic is over the integers, not modulo 2^64. Fast-doubling formulation."
            ),
            "concrete_statement": [statement_line, f"Output size: {fib_bits} bits; no modulo 2^64 reduction is used."],
        },
        exact_arithmetic={
            "modulus": None,
            "modulus_note": "No modular reduction is used in this FOL-Zinc benchmark.",
            "n": n,
            "fibonacci_indexing": "fib(1)=fib(2)=1, equivalent to standard F_n with F_0=0,F_1=1 for n>=1.",
            "output_bit_length": fib_bits,
            "output_decimal_digits": fib_digits,
            "output_decimal_preview": _short_decimal(output),
        },
        sections=sections,
        check=check,
    )
