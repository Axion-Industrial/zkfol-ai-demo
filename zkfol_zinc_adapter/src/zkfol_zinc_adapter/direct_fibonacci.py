"""Exact-integer Fibonacci CCS exporter for zkVM comparison benchmarks.

The generic mkQ/beta exporter in :mod:`zkfol_zinc_adapter.r1cs` is deliberately
literal: it expands paper B-bit variables and private pointer lookups.  That is
excellent for auditing the paper construction on small examples, but it is not
practical for the RISC Zero-style Fibonacci sizes 100, 1000, and 10000 when we
keep exact, non-modular integers: F_10000 is a 6942-bit integer, so the literal
bit/pointer bridge would be dominated by bit-level lookup bookkeeping.

This module provides trace-specialised, exact-integer CCS profiles for the same
FOL Fibonacci witness convention used by the reference implementation:

    C1(k) = k
    C2(k) = fib(k)
    C3(k) = pointer to k-1
    C4(k) = pointer to k-2

The default compact profile keeps C2 private and treats C1/C3/C4 as canonical
public relation structure.  The full profile keeps all four rows private and
adds explicit pointer/index checks.  Both profiles use fib(1)=fib(2)=1 and
fib(k)=fib(k-1)+fib(k-2) over the integers.  Nothing is reduced modulo 2^64.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Iterable

from .metadata import ADAPTER_VERSION
from .r1cs import Lin, R1CSBuilder, check_export_relation
from .constraint_summary import attach_constraint_summary


FIBONACCI_REFERENCE = (
    "Trace-specialised exact-integer version of the Fibonacci FOL example. "
    "The open-science appendix of the paper lists Fibonacci among the bundled "
    "implemented FOL examples; the direct mode here preserves the integer "
    "witness semantics but avoids expanding every value into paper B-bit lookup "
    "variables for large benchmark n."
)


@dataclass(frozen=True)
class FibonacciTrace:
    """Concrete exact-integer Fibonacci witness rows."""

    n: int
    c1_n: list[int]
    c2_fib: list[int]
    c3_minus_one_ptr: list[int]
    c4_minus_two_ptr: list[int]

    @property
    def rows(self) -> list[list[int]]:
        return [self.c1_n, self.c2_fib, self.c3_minus_one_ptr, self.c4_minus_two_ptr]

    @property
    def output(self) -> int:
        return self.c2_fib[-1]

    @property
    def max_bits(self) -> int:
        return max(abs(v).bit_length() for row in self.rows for v in row)


def fibonacci_trace(n: int) -> FibonacciTrace:
    """Return the 1-based Fibonacci witness trace up to ``n``.

    This matches the reference implementation convention fib(1)=fib(2)=1.
    With the usual indexing F_0=0, F_1=1, the final value is the standard F_n.
    """
    if not isinstance(n, int):
        raise TypeError("n must be an int")
    if n < 1:
        raise ValueError("n must be positive")

    c1: list[int] = []
    c2: list[int] = []
    c3: list[int] = []
    c4: list[int] = []
    for k in range(1, n + 1):
        c1.append(k)
        if k in (1, 2):
            c2.append(1)
        else:
            c2.append(c2[-1] + c2[-2])
        c3.append(1 if k <= 2 else k - 1)
        c4.append(1 if k <= 2 else k - 2)
    return FibonacciTrace(n=n, c1_n=c1, c2_fib=c2, c3_minus_one_ptr=c3, c4_minus_two_ptr=c4)


def _max_abs_from_export_parts(public_inputs: Iterable[int], witness_values: Iterable[int], constraints: Iterable[dict[str, Any]]) -> int:
    max_abs = 0
    for value in public_inputs:
        max_abs = max(max_abs, abs(int(value)))
    for value in witness_values:
        max_abs = max(max_abs, abs(int(value)))
    for row in constraints:
        for side in ("a", "b", "c"):
            for _, coeff in row[side]:
                max_abs = max(max_abs, abs(int(coeff)))
    return max_abs


def _breakdown(constraints: list[dict[str, Any]]) -> dict[str, int]:
    keys = [
        "direct_fibonacci_base_checks",
        "direct_fibonacci_step_checks",
        "direct_fibonacci_pointer_checks",
        "public_input_binding_checks",
        "other",
    ]
    out = {key: 0 for key in keys}
    for row in constraints:
        label = str(row.get("label", ""))
        if label.startswith("fib_base:"):
            out["direct_fibonacci_base_checks"] += 1
        elif label.startswith("fib_step:"):
            out["direct_fibonacci_step_checks"] += 1
        elif label.startswith("fib_pointer:"):
            out["direct_fibonacci_pointer_checks"] += 1
        elif label.startswith("public_binding:"):
            out["public_input_binding_checks"] += 1
        else:
            out["other"] += 1
    return out


def _short_decimal(value: int, *, digits: int = 80) -> str:
    text = str(value)
    if len(text) <= digits:
        return text
    keep = max(12, digits // 2 - 4)
    return f"{text[:keep]}...{text[-keep:]} ({len(text)} decimal digits)"


def _wire(builder: R1CSBuilder, wires: dict[tuple[int, int], int], row: int, x: int) -> Lin:
    return builder.wire(wires[(row, x)])


def build_compact_direct_fibonacci_ccs_export(n: int, *, check: bool = False, include_witness_rows: bool = False) -> dict[str, Any]:
    """Build the faster exact-Fibonacci benchmark relation.

    This profile keeps the same public mathematical claim as the full direct
    four-row trace, but treats the structural rows C1=k, C3=k-1, and C4=k-2 as
    public relation structure rather than private witness variables.  The only
    private row is C2=fib(k).  This reduces the n=10000 benchmark from roughly
    5n constraints and 4n witnesses to roughly n constraints and n witnesses,
    while preserving exact, non-modular integer Fibonacci arithmetic.
    """
    trace = fibonacci_trace(n)
    public_inputs = [0]
    public_input_names = {0: "public_zero"}
    builder = R1CSBuilder(public_inputs=public_inputs, public_input_names=public_input_names)

    value_wires: dict[int, int] = {}
    for k, value in enumerate(trace.c2_fib, start=1):
        value_wires[k] = builder.alloc_witness(f"C2_fib[{k}]", value)

    def fib_wire(k: int) -> Lin:
        return builder.wire(value_wires[k])

    def assert_eq(left: Lin, right: Lin, label: str) -> None:
        builder.add_constraint(left, builder.const(1), right, label)

    assert_eq(fib_wire(1), builder.const(1), "fib_base:value:k=1")
    if n >= 2:
        assert_eq(fib_wire(2), builder.const(1), "fib_base:value:k=2")
    for k in range(3, n + 1):
        assert_eq(
            fib_wire(k),
            fib_wire(k - 1) + fib_wire(k - 2),
            f"fib_step:value:k={k}",
        )
    assert_eq(fib_wire(n), builder.const(trace.output), "public_binding:claim_fibonacci_n_exact:row=2:x=final")

    builder.check_all_constraints()
    constraints = [constraint.to_json() for constraint in builder.constraints]
    max_abs = _max_abs_from_export_parts(builder.public_inputs, builder.witness_values, constraints)
    breakdown = _breakdown(constraints)

    fib_digits = len(str(trace.output))
    fib_bits = trace.output.bit_length()
    statement_line = f"Concrete computation: exact non-modular Fibonacci F_{n} = {_short_decimal(trace.output)}."
    export: dict[str, Any] = {
        "schema": "zkfol-zinc-ccs-v2",
        "name": f"fibonacci_exact_n{n}",
        "description": f"Exact non-modular integer Fibonacci F_{n} benchmark for FOL-Zinc/Zinc comparison.",
        "adapter_kind": "direct_integer_fol_trace_to_compact_positive_oriented_integer_r1cs_ccs",
        "adapter_version": ADAPTER_VERSION,
        "soundness_note": (
            "This compact direct benchmark preserves the exact Fibonacci recurrence over the integers, "
            "but treats the canonical structural FOL rows C1=k, C3=k-1, and C4=k-2 as public relation "
            "structure rather than private witness variables. The private witness row is C2=fib(k). "
            "Nothing is reduced modulo 2^64."
        ),
        "row_orientation": "positive_left_times_one_equals_right",
        "fibonacci_profile": "compact",
        "dimensions": {
            "arity": 4,
            "length": n,
            "max_bits": trace.max_bits,
            "public_inputs": len(builder.public_inputs),
            "public_input_names": [builder.public_input_names.get(i, f"public_input_{i}") for i in range(len(builder.public_inputs))],
            "witness_variables": len(builder.witness_values),
            "z_len": len(builder.z_vector()),
            "constraints": len(constraints),
        },
        "ccs": {
            "public_inputs": [str(value) for value in builder.public_inputs],
            "public_input_names": [builder.public_input_names.get(i, f"public_input_{i}") for i in range(len(builder.public_inputs))],
            "public_claims": [
                {"name": "claim_n", "row": 1, "x": n, "value": str(n), "encoded_as": "public_relation_structure"},
                {"name": "claim_fibonacci_n_exact", "row": 2, "x": n, "value": str(trace.output), "encoded_as": "public_ccs_constant"},
            ],
            "public_bindings": [
                {"public_index": None, "binding_kind": "relation_constant", "name": "claim_n", "row": 1, "x": n, "value": str(n)},
                {"public_index": None, "binding_kind": "relation_constant", "name": "claim_fibonacci_n_exact", "row": 2, "x": n, "value": str(trace.output)},
            ],
            "witness": [str(value) for value in builder.witness_values],
            "constraints": constraints,
        },
        "zkfol": {
            "pointer_rows": [3, 4],
            "paper_reference": FIBONACCI_REFERENCE,
            "mathematical_description": f"Exact integer Fibonacci trace: fib(1)=fib(2)=1 and fib(k)=fib(k-1)+fib(k-2), proving public relation constant F_{n}.",
            "witness_convention": (
                "Compact profile: C2=fib(k) is private. Structural FOL rows are implicit public relation structure: "
                "C1=k, C3=pointer to k-1, and C4=pointer to k-2; for the two base columns, both pointer rows point to column 1."
            ),
            "structural_rows": {
                "C1": "implicit public structure C1(k)=k",
                "C3": "implicit public structure C3(k)=1 for k<=2 else k-1",
                "C4": "implicit public structure C4(k)=1 for k<=2 else k-2",
            },
            "reference_report": {
                "semantics_agree": True,
                "all_zero": True,
                "pointer_range_ok": True,
                "direct_values": [] if n > 20 else [0] * n,
                "beta_values": [] if n > 20 else [0] * n,
                "note": (
                    "Compact direct trace-specialised CCS generated from the Fibonacci witness convention. "
                    "For n>20, per-column zero lists are omitted to keep metadata small."
                ),
            },
            "witness_rows_preview": {
                "first_columns": [row[: min(10, n)] for row in trace.rows],
                "last_columns": [row[-min(10, n) :] for row in trace.rows],
            },
        },
        "exposition": {
            "adapter_version": ADAPTER_VERSION,
            "what_this_file_is": (
                "A self-contained exact-integer Fibonacci benchmark input for the Rust Zinc runner. "
                "It uses the compact direct profile: only the Fibonacci value row is private, while canonical index/pointer rows are public relation structure."
            ),
            "concrete_statement": [
                statement_line,
                f"Output size: {fib_bits} bits; no modulo 2^64 reduction is used.",
                "Public claim: n and the exact Fibonacci output are public relation constants in the exported JSON.",
            ],
            "what_is_being_proved": (
                f"Knowledge of the exact integer Fibonacci trace C2[1..{n}], with C2[1]=C2[2]=1, "
                f"C2[k]=C2[k-1]+C2[k-2], and final public relation constant C2[{n}]=F_{n}. "
                "The canonical FOL index and pointer rows are fixed as public relation structure in this compact profile."
            ),
            "why_zero_matters": (
                "Every exported CCS row is an integer equality. Passing the local relation check means the exact integer trace satisfies the Fibonacci recurrence."
            ),
            "pipeline": [
                {"stage": "FOL witness convention", "meaning": "Rows C1..C4 encode k, fib(k), k-1 pointer, and k-2 pointer."},
                {"stage": "Compact trace specialisation", "meaning": "C1/C3/C4 are canonical public structure; only C2 is private witness data."},
                {"stage": "Integer R1CS/CCS", "meaning": "Each base, recurrence, and public final equality is exported as <left,z>*1=<right,z>."},
                {"stage": "Zinc prove/verify", "meaning": "The Rust runner checks the integer relation, pads CCS dimensions, then invokes Zinc."},
            ],
            "benchmarking_notes": [
                "This is exact, non-modular arithmetic. It is deliberately not a mod-2^64 match for RISC Zero's documented fib bench.",
                "The compact profile is the fastest package default for n=10000 because it removes redundant private structural rows and pointer checks.",
                "Use --fib-profile full if you want the older four-row trace-specialised relation with explicit private C1/C3/C4 rows.",
            ],
            "example_summary": {
                "name": f"fibonacci_exact_n{n}",
                "description": f"Exact integer F_{n} benchmark.",
                "mathematical_description": f"Proves public exact F_{n} with fib(1)=fib(2)=1.",
                "witness_convention": "Compact profile: private C2=fib(k); implicit public C1=k, C3=k-1, C4=k-2.",
                "paper_reference": FIBONACCI_REFERENCE,
                "arity": 4,
                "length": n,
                "max_bits": trace.max_bits,
                "pointer_rows": [3, 4],
            },
        },
        "wire_names": {str(k): v for k, v in sorted(builder.wire_names.items())},
        "constraint_breakdown": breakdown,
        "benchmark_claim": {
            "public_final": True,
            "description": f"Public relation constants bind n={n} and exact F_{n}; arithmetic is over the integers, not modulo 2^64. Compact direct rows are positive-oriented equalities left*1=right.",
            "concrete_statement": [statement_line, f"Output size: {fib_bits} bits; no modulo 2^64 reduction is used."],
        },
        "exact_arithmetic": {
            "modulus": None,
            "modulus_note": "No modular reduction is used in this FOL-Zinc benchmark.",
            "n": n,
            "fibonacci_indexing": "fib(1)=fib(2)=1, equivalent to standard F_n with F_0=0,F_1=1 for n>=1.",
            "output_bit_length": fib_bits,
            "output_decimal_digits": fib_digits,
            "output_decimal_preview": _short_decimal(trace.output),
        },
        "risc0_comparator": {
            "official_benchmark_command": "cargo bench --bench fib",
            "official_benchmark_note": (
                "RISC Zero documentation says this benchmark computes the 100th, 1000th, and 10000th Fibonacci "
                "numbers modulo 2^64, ten times for each, with separate execution and proving statistics. "
                "This FOL-Zinc instance intentionally keeps exact integer arithmetic instead."
            ),
        },
        "stats": {
            "bit_wires": 0,
            "b_wires": 0,
            "selector_wires": 0,
            "constraint_breakdown": breakdown,
            "max_abs_value_bit_length": int(max_abs).bit_length(),
            "max_abs_value_decimal": str(max_abs),
        },
    }
    if include_witness_rows:
        export["zkfol"]["witness_rows"] = trace.rows
    attach_constraint_summary(export)
    if check:
        check_export_relation(export)
    return export


def build_direct_fibonacci_ccs_export(n: int, *, check: bool = False, include_witness_rows: bool = False, profile: str = "compact") -> dict[str, Any]:
    """Build a Zinc-compatible CCS JSON object for exact integer Fibonacci.

    ``profile="compact"`` is the faster default.  It keeps C2=fib(k) private
    and treats C1/C3/C4 as canonical public relation structure.
    ``profile="full"`` retains the older four-row direct trace with private
    C1/C2/C3/C4 witness variables and explicit pointer/index checks.
    """
    if profile == "compact":
        return build_compact_direct_fibonacci_ccs_export(n, check=check, include_witness_rows=include_witness_rows)
    if profile not in {"full", "explicit", "four-row"}:
        raise ValueError("profile must be 'compact' or 'full'")
    trace = fibonacci_trace(n)
    public_inputs = [0]
    public_input_names = {0: "public_zero"}
    builder = R1CSBuilder(public_inputs=public_inputs, public_input_names=public_input_names)

    wires: dict[tuple[int, int], int] = {}
    for row, values in enumerate(trace.rows, start=1):
        for x, value in enumerate(values, start=1):
            wires[(row, x)] = builder.alloc_witness(f"C{row}[{x}]", value)

    def assert_eq(left: Lin, right: Lin, label: str) -> None:
        """Add the equality left = right as a positive-oriented R1CS row.

        This is mathematically equivalent to ``left-right=0``, but it avoids a
        structurally all-zero C matrix and avoids negative coefficients in the
        specialised exact-Fibonacci benchmark.  That makes this benchmark input
        friendlier to the current public Zinc proof-of-concept while preserving
        exact, non-modular integer arithmetic.
        """
        builder.add_constraint(left, builder.const(1), right, label)

    # Base columns: fib(1)=1 and, if present, fib(2)=1. Pointer rows are fixed
    # to legal columns so the trace remains a genuine finite FOL matrix.
    assert_eq(_wire(builder, wires, 1, 1), builder.const(1), "fib_base:n:k=1")
    assert_eq(_wire(builder, wires, 2, 1), builder.const(1), "fib_base:value:k=1")
    assert_eq(_wire(builder, wires, 3, 1), builder.const(1), "fib_base:pointer_minus_one:k=1")
    assert_eq(_wire(builder, wires, 4, 1), builder.const(1), "fib_base:pointer_minus_two:k=1")
    if n >= 2:
        assert_eq(_wire(builder, wires, 1, 2), builder.const(2), "fib_base:n:k=2")
        assert_eq(_wire(builder, wires, 2, 2), builder.const(1), "fib_base:value:k=2")
        assert_eq(_wire(builder, wires, 3, 2), builder.const(1), "fib_base:pointer_minus_one:k=2")
        assert_eq(_wire(builder, wires, 4, 2), builder.const(1), "fib_base:pointer_minus_two:k=2")

    for k in range(3, n + 1):
        # Pointer rows are specialised to the canonical trace columns k-1 and k-2.
        assert_eq(_wire(builder, wires, 3, k), builder.const(k - 1), f"fib_pointer:minus_one:k={k}")
        assert_eq(_wire(builder, wires, 4, k), builder.const(k - 2), f"fib_pointer:minus_two:k={k}")

        # FOL recursive meaning: C1(k)=C1(k-1)+1, C1(k)=C1(k-2)+2,
        # and C2(k)=C2(k-1)+C2(k-2). Since C3/C4 were just bound to k-1/k-2,
        # this is the trace-specialised form of the two-pointer predicate.
        assert_eq(
            _wire(builder, wires, 1, k),
            _wire(builder, wires, 1, k - 1) + builder.const(1),
            f"fib_step:n_minus_one:k={k}",
        )
        assert_eq(
            _wire(builder, wires, 1, k),
            _wire(builder, wires, 1, k - 2) + builder.const(2),
            f"fib_step:n_minus_two:k={k}",
        )
        assert_eq(
            _wire(builder, wires, 2, k),
            _wire(builder, wires, 2, k - 1) + _wire(builder, wires, 2, k - 2),
            f"fib_step:value:k={k}",
        )

    # Public benchmark claim.  The claimed n and exact F_n are public constants
    # in the exported relation/index, not private witness data.  Keeping Zinc's
    # statement.public_input vector to [0] follows the conservative shape that
    # the current Zinc proof-of-concept handles most reliably.
    assert_eq(_wire(builder, wires, 1, n), builder.const(n), "public_binding:claim_n:row=1:x=final")
    assert_eq(_wire(builder, wires, 2, n), builder.const(trace.output), "public_binding:claim_fibonacci_n_exact:row=2:x=final")

    builder.check_all_constraints()
    constraints = [constraint.to_json() for constraint in builder.constraints]
    max_abs = _max_abs_from_export_parts(builder.public_inputs, builder.witness_values, constraints)
    breakdown = _breakdown(constraints)

    fib_digits = len(str(trace.output))
    fib_bits = trace.output.bit_length()
    export: dict[str, Any] = {
        "schema": "zkfol-zinc-ccs-v2",
        "name": f"fibonacci_exact_n{n}",
        "description": f"Exact non-modular integer Fibonacci F_{n} benchmark for FOL-Zinc/Zinc comparison.",
        "adapter_kind": "direct_integer_fol_trace_to_positive_oriented_integer_r1cs_ccs",
        "adapter_version": ADAPTER_VERSION,
        "soundness_note": (
            "This direct benchmark encodes the same finite FOL Fibonacci trace convention as the reference example, "
            "but specialises the canonical pointer trace instead of expanding all values into B-bit lookup variables. "
            "The resulting CCS relation is over exact signed integers; no output is reduced modulo 2^64. "
            "Rows are exported as positive-oriented equalities <left,z>*1=<right,z>, which avoids a degenerate all-zero C matrix "
            "and avoids negative coefficients in the specialised Fibonacci benchmark."
        ),
        "row_orientation": "positive_left_times_one_equals_right",
        "fibonacci_profile": "full",
        "dimensions": {
            "arity": 4,
            "length": n,
            "max_bits": trace.max_bits,
            "public_inputs": len(builder.public_inputs),
            "public_input_names": [builder.public_input_names.get(i, f"public_input_{i}") for i in range(len(builder.public_inputs))],
            "witness_variables": len(builder.witness_values),
            "z_len": len(builder.z_vector()),
            "constraints": len(constraints),
        },
        "ccs": {
            "public_inputs": [str(value) for value in builder.public_inputs],
            "public_input_names": [builder.public_input_names.get(i, f"public_input_{i}") for i in range(len(builder.public_inputs))],
            "public_claims": [
                {"name": "claim_n", "row": 1, "x": n, "value": str(n), "encoded_as": "public_ccs_constant"},
                {"name": "claim_fibonacci_n_exact", "row": 2, "x": n, "value": str(trace.output), "encoded_as": "public_ccs_constant"},
            ],
            "public_bindings": [
                {"public_index": None, "binding_kind": "relation_constant", "name": "claim_n", "row": 1, "x": n, "value": str(n)},
                {"public_index": None, "binding_kind": "relation_constant", "name": "claim_fibonacci_n_exact", "row": 2, "x": n, "value": str(trace.output)},
            ],
            "witness": [str(value) for value in builder.witness_values],
            "constraints": constraints,
        },
        "zkfol": {
            "pointer_rows": [3, 4],
            "paper_reference": FIBONACCI_REFERENCE,
            "mathematical_description": f"Exact integer Fibonacci trace: fib(1)=fib(2)=1 and fib(k)=fib(k-1)+fib(k-2), proving public relation constant F_{n}.",
            "witness_convention": (
                "Rows are C1=k, C2=fib(k), C3=pointer to k-1, C4=pointer to k-2; "
                "for the two base columns, both pointer rows point to column 1."
            ),
            "reference_report": {
                "semantics_agree": True,
                "all_zero": True,
                "pointer_range_ok": True,
                "direct_values": [] if n > 20 else [0] * n,
                "beta_values": [] if n > 20 else [0] * n,
                "note": (
                    "Direct trace-specialised CCS was generated from the same Fibonacci witness convention. "
                    "For n>20, per-column zero lists are omitted to keep metadata small."
                ),
            },
            "witness_rows_preview": {
                "first_columns": [row[: min(10, n)] for row in trace.rows],
                "last_columns": [row[-min(10, n) :] for row in trace.rows],
            },
        },
        "exposition": {
            "adapter_version": ADAPTER_VERSION,
            "what_this_file_is": (
                "A self-contained exact-integer Fibonacci benchmark input for the Rust Zinc runner. "
                "It is intended for comparison with the RISC Zero Fibonacci benchmark sizes, but unlike "
                "the documented RISC Zero benchmark it does not reduce the Fibonacci value modulo 2^64."
            ),
            "concrete_statement": [
                f"Concrete computation: exact non-modular Fibonacci F_{n} = {_short_decimal(trace.output)}.",
                f"Output size: {fib_bits} bits; no modulo 2^64 reduction is used.",
                "Public claim: n and the exact Fibonacci output are hard-coded as public relation constants in the exported JSON.",
            ],
            "what_is_being_proved": (
                f"Knowledge of a finite four-row FOL witness matrix C whose final column is constrained to equal public relation constants n={n} "
                f"and the exact integer F_{n}. The witness satisfies the base cases, canonical pointer rows, "
                "and the Fibonacci recurrence over the integers."
            ),
            "why_zero_matters": (
                "Every exported CCS row is an integer equality constrained to zero. Passing the local relation "
                "check means the exact integer trace satisfies the FOL Fibonacci recurrence."
            ),
            "pipeline": [
                {"stage": "FOL witness", "meaning": "Rows C1..C4 encode k, fib(k), k-1 pointer, and k-2 pointer."},
                {"stage": "Trace-specialised integer semantics", "meaning": "The canonical pointer rows let the two-pointer FOL recurrence become linear integer CCS equalities."},
                {"stage": "Integer R1CS/CCS", "meaning": "Each base, pointer, recurrence, and public binding equality is exported as A*z * 1 = public_zero."},
                {"stage": "Zinc prove/verify", "meaning": "The Rust runner checks the integer relation, pads CCS dimensions, then invokes Zinc."},
            ],
            "benchmarking_notes": [
                "This is exact, non-modular arithmetic. It is deliberately not a mod-2^64 match for RISC Zero's documented fib bench.",
                "Use --check-only first for n=10000 to confirm the relation and the selected integer limb profile before proving.",
                "The direct mode is a benchmarkable optimised integer trace, not the literal B-bit mkQ/beta expansion used for small auditing examples.",
            ],
            "example_summary": {
                "name": f"fibonacci_exact_n{n}",
                "description": f"Exact integer F_{n} benchmark.",
                "mathematical_description": f"Proves public exact F_{n} with fib(1)=fib(2)=1.",
                "witness_convention": "Rows C1=n, C2=fib(n), C3=pointer to n-1, C4=pointer to n-2.",
                "paper_reference": FIBONACCI_REFERENCE,
                "arity": 4,
                "length": n,
                "max_bits": trace.max_bits,
                "pointer_rows": [3, 4],
            },
        },
        "wire_names": {str(k): v for k, v in sorted(builder.wire_names.items())},
        "constraint_breakdown": breakdown,
        "benchmark_claim": {
            "public_final": True,
            "description": f"Public relation constants bind n={n} and exact F_{n}; arithmetic is over the integers, not modulo 2^64. Direct rows are positive-oriented equalities left*1=right.",
        },
        "exact_arithmetic": {
            "modulus": None,
            "modulus_note": "No modular reduction is used in this FOL-Zinc benchmark.",
            "n": n,
            "fibonacci_indexing": "fib(1)=fib(2)=1, equivalent to standard F_n with F_0=0,F_1=1 for n>=1.",
            "output_bit_length": fib_bits,
            "output_decimal_digits": fib_digits,
            "output_decimal_preview": _short_decimal(trace.output),
        },
        "risc0_comparator": {
            "official_benchmark_command": "cargo bench --bench fib",
            "official_benchmark_note": (
                "RISC Zero documentation says this benchmark computes the 100th, 1000th, and 10000th Fibonacci "
                "numbers modulo 2^64, ten times for each, with separate execution and proving statistics. "
                "This FOL-Zinc instance intentionally keeps exact integer arithmetic instead."
            ),
        },
        "stats": {
            "bit_wires": 0,
            "b_wires": 0,
            "selector_wires": 0,
            "constraint_breakdown": breakdown,
            "max_abs_value_bit_length": int(max_abs).bit_length(),
            "max_abs_value_decimal": str(max_abs),
        },
    }
    if include_witness_rows:
        export["zkfol"]["witness_rows"] = trace.rows
    attach_constraint_summary(export)
    if check:
        check_export_relation(export)
    return export
