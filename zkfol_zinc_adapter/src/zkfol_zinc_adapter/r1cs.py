"""Compile zkFOL mkQ/beta checks to integer R1CS/CCS.

The paper describes a direct AIR for Zinc.  The current public Zinc prototype
exposes a CCS/R1CS-style API, so this module materialises an equivalent
benchmarking layer:

* the reference implementation still supplies the FOL AST, witness matrix, and
  ``mkQ`` expressions;
* every ``B`` bit is represented as a private R1CS witness variable;
* booleanity constraints enforce that ``B`` variables are bits;
* selector/multiplexer constraints enforce the pointer lookups
  ``B_i,j,x,nu = B_i,0,C_j(x),nu`` and the range condition
  ``1 <= C_j(x) <= len(C)``;
* each ``mkQ_x(<phi>)`` expression is compiled to an arithmetic circuit and
  constrained to be zero.

This is deliberately unoptimised and benchmark-friendly: it prioritises clear,
auditable constraints over minimising row count.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Iterable, Mapping

import sympy as sp

try:
    from zkfol.compiler import BIndex, CompilationContext, beta_symbol, parse_b_symbol
    from zkfol.examples import ExampleSpec
    from zkfol.fast_beta import beta_all_fast
    from zkfol.witness import MatrixInterpretation
except ModuleNotFoundError:  # Allows docs/utility commands and direct Fibonacci helpers before zkfol_reference is installed.
    BIndex = object  # type: ignore[assignment]
    ExampleSpec = object  # type: ignore[assignment]
    MatrixInterpretation = object  # type: ignore[assignment]

    class CompilationContext:  # type: ignore[no-redef]
        @classmethod
        def from_witness(cls, *_args: Any, **_kwargs: Any) -> "CompilationContext":
            raise R1CSError("zkfol_reference is not installed; run ./zkfol_zinc_adapter/folzinc setup first")

    def beta_symbol(*_args: Any, **_kwargs: Any) -> int:  # type: ignore[no-redef]
        raise R1CSError("zkfol_reference is not installed; run ./zkfol_zinc_adapter/folzinc setup first")

    def parse_b_symbol(*_args: Any, **_kwargs: Any) -> Any:  # type: ignore[no-redef]
        raise R1CSError("zkfol_reference is not installed; run ./zkfol_zinc_adapter/folzinc setup first")

    def beta_all_fast(*_args: Any, **_kwargs: Any) -> list[int]:  # type: ignore[no-redef]
        raise R1CSError("zkfol_reference is not installed; run ./zkfol_zinc_adapter/folzinc setup first")

from .metadata import ADAPTER_VERSION, build_exposition, constraint_breakdown
from .constraint_summary import attach_constraint_summary


class R1CSError(ValueError):
    """Raised when R1CS construction or validation fails."""


@dataclass(frozen=True)
class Lin:
    """Integer linear combination over the final CCS z-vector.

    Keys are z-vector indices.  The final z vector is laid out as
    public inputs, then one distinguished constant-one coordinate, then private
    witness variables.  Thus the one-coordinate index is
    ``len(public_inputs)`` and private witness variables start immediately after
    it.  The common default ``public_inputs=[0]`` gives z[0]=public zero,
    z[1]=one, and private variables from z[2], but public-final exports have
    more public coordinates.
    """

    terms: tuple[tuple[int, int], ...] = ()

    @staticmethod
    def zero() -> "Lin":
        return Lin(())

    @staticmethod
    def from_terms(terms: Mapping[int, int] | Iterable[tuple[int, int]]) -> "Lin":
        acc: dict[int, int] = {}
        iterable = terms.items() if isinstance(terms, Mapping) else terms
        for index, coeff in iterable:
            if coeff == 0:
                continue
            if index < 0:
                raise R1CSError(f"negative z-index {index}")
            acc[index] = acc.get(index, 0) + int(coeff)
            if acc[index] == 0:
                del acc[index]
        return Lin(tuple(sorted(acc.items())))

    @staticmethod
    def const(value: int, *, one_index: int = 1) -> "Lin":
        return Lin.from_terms({one_index: value})

    @staticmethod
    def wire(z_index: int) -> "Lin":
        return Lin.from_terms({z_index: 1})

    def __add__(self, other: "Lin") -> "Lin":
        return Lin.from_terms([*self.terms, *other.terms])

    def __sub__(self, other: "Lin") -> "Lin":
        return self + other.scale(-1)

    def scale(self, coeff: int) -> "Lin":
        if coeff == 0:
            return Lin.zero()
        return Lin.from_terms((index, c * coeff) for index, c in self.terms)

    def is_constant(self, *, one_index: int = 1) -> bool:
        return all(index == one_index for index, _ in self.terms)

    def constant_value(self, *, one_index: int = 1) -> int | None:
        if not self.terms:
            return 0
        if len(self.terms) == 1 and self.terms[0][0] == one_index:
            return self.terms[0][1]
        return None

    def eval(self, values_by_z_index: Mapping[int, int]) -> int:
        total = 0
        for index, coeff in self.terms:
            try:
                value = values_by_z_index[index]
            except KeyError as exc:
                raise R1CSError(f"missing value for z[{index}]") from exc
            total += coeff * value
        return total

    def to_json_terms(self) -> list[list[int | str]]:
        # Coefficients are emitted as decimal strings.  Earlier versions used
        # JSON numbers and therefore fit i64; decimal strings let b2int contain
        # coefficients such as 2**256 while remaining unambiguous.  The z-index
        # stays a JSON number because it is a structural array index.
        out: list[list[int | str]] = []
        for index, coeff in self.terms:
            if not isinstance(index, int) or index < 0:
                raise R1CSError(f"invalid z index {index!r}")
            if not isinstance(coeff, int):
                raise R1CSError(f"coefficient at z[{index}] is not an int: {coeff!r}")
            out.append([index, str(coeff)])
        return out


@dataclass(frozen=True)
class Constraint:
    """One R1CS row: <A,z> * <B,z> = <C,z>."""

    a: Lin
    b: Lin
    c: Lin
    label: str

    def to_json(self) -> dict[str, Any]:
        return {
            "a": self.a.to_json_terms(),
            "b": self.b.to_json_terms(),
            "c": self.c.to_json_terms(),
            "label": self.label,
        }


@dataclass(frozen=True)
class PublicBinding:
    """One public benchmark claim bound to a witness entry.

    The constraint is b2int(C_row(x)) == public_inputs[public_index].
    """

    public_index: int
    name: str
    row: int
    x: int
    value: int


@dataclass
class R1CSBuilder:
    """Mutable builder for an integer R1CS instance."""

    public_inputs: list[int] = field(default_factory=lambda: [0])
    public_input_names: dict[int, str] = field(default_factory=lambda: {0: "public_zero"})
    constraints: list[Constraint] = field(default_factory=list)
    witness_values: list[int] = field(default_factory=list)
    wire_names: dict[int, str] = field(default_factory=dict)
    bit_wires: set[int] = field(default_factory=set)
    b_wires: dict[BIndex, int] = field(default_factory=dict)
    selector_wires: dict[tuple[int, int, int], int] = field(default_factory=dict)

    def __post_init__(self) -> None:
        if not self.public_inputs:
            raise R1CSError("at least one public input is required; index 0 is conventionally public_zero")
        self.values_by_z_index: dict[int, int] = {}
        for index, value in enumerate(self.public_inputs):
            if not isinstance(value, int):
                raise R1CSError(f"public input {index} is not an int: {value!r}")
            self.values_by_z_index[index] = int(value)
            self.wire_names[index] = self.public_input_names.get(index, f"public_input_{index}")
        self.values_by_z_index[self.one_index] = 1
        self.wire_names[self.one_index] = "one"

    @property
    def one_index(self) -> int:
        return len(self.public_inputs)

    @property
    def next_z_index(self) -> int:
        # z = public_inputs || [1] || witness.
        return len(self.public_inputs) + 1 + len(self.witness_values)

    def const(self, value: int) -> Lin:
        return Lin.const(int(value), one_index=self.one_index)

    def zero(self) -> Lin:
        return Lin.zero()

    def public_zero(self) -> Lin:
        """Return the explicit public-zero coordinate z[0].

        An empty linear combination and z[0] both evaluate to zero.  For rows
        that are meant to enforce ``value == 0``, using z[0] gives Zinc a
        non-empty C matrix even when the whole benchmark consists of linear
        zero checks, such as the trace-specialised Fibonacci benchmark.
        """
        return self.wire(0)

    def wire(self, z_index: int) -> Lin:
        return Lin.wire(z_index)

    def alloc_witness(self, name: str, value: int) -> int:
        if not isinstance(value, int):
            raise R1CSError(f"witness {name} is not an int: {value!r}")
        z_index = self.next_z_index
        self.witness_values.append(int(value))
        self.values_by_z_index[z_index] = int(value)
        if z_index in self.wire_names:
            raise R1CSError(f"duplicate z-index allocation {z_index}")
        self.wire_names[z_index] = name
        return z_index

    def add_constraint(self, a: Lin, b: Lin, c: Lin, label: str) -> None:
        lhs = a.eval(self.values_by_z_index) * b.eval(self.values_by_z_index)
        rhs = c.eval(self.values_by_z_index)
        if lhs != rhs:
            raise R1CSError(f"unsatisfied generated constraint {label!r}: {lhs} != {rhs}")
        self.constraints.append(Constraint(a=a, b=b, c=c, label=label))

    def assert_zero(self, value: Lin, label: str) -> None:
        self.add_constraint(value, self.const(1), self.public_zero(), label)

    def add_boolean_constraint(self, z_index: int, label: str) -> None:
        z = self.wire(z_index)
        self.add_constraint(z, z - self.const(1), self.public_zero(), label)

    def mark_bit(self, z_index: int) -> None:
        value = self.values_by_z_index[z_index]
        if value not in (0, 1):
            raise R1CSError(f"wire z[{z_index}]={value} was marked as a bit")
        self.bit_wires.add(z_index)

    def mul(self, left: Lin, right: Lin, *, label: str) -> Lin:
        left_const = left.constant_value(one_index=self.one_index)
        if left_const is not None:
            return right.scale(left_const)
        right_const = right.constant_value(one_index=self.one_index)
        if right_const is not None:
            return left.scale(right_const)
        value = left.eval(self.values_by_z_index) * right.eval(self.values_by_z_index)
        z_index = self.alloc_witness(label, value)
        out = self.wire(z_index)
        self.add_constraint(left, right, out, label)
        return out

    def ensure_b_wire(self, index: BIndex, witness: MatrixInterpretation) -> int:
        """Allocate the private bit wire for one paper ``B`` variable."""
        if index in self.b_wires:
            return self.b_wires[index]
        value = beta_symbol(index, witness)
        name = f"B(row={index.row},ptr={index.pointer},x={index.x},bit={index.bit})"
        z_index = self.alloc_witness(name, value)
        self.b_wires[index] = z_index
        self.mark_bit(z_index)
        return z_index

    def ensure_direct_b_wire(self, *, row: int, x: int, bit: int, witness: MatrixInterpretation) -> int:
        return self.ensure_b_wire(BIndex(row=row, pointer=0, x=x, bit=bit), witness)

    def b2int_lin(self, *, row: int, pointer: int, x: int, max_bits: int, witness: MatrixInterpretation) -> Lin:
        total = self.zero()
        for bit in range(1, max_bits + 1):
            z_index = self.ensure_b_wire(BIndex(row=row, pointer=pointer, x=x, bit=bit), witness)
            total += self.wire(z_index).scale(2 ** (bit - 1))
        return total

    def selector_wire(self, *, pointer_row: int, x: int, selected_column: int, witness: MatrixInterpretation) -> int:
        key = (pointer_row, x, selected_column)
        if key in self.selector_wires:
            return self.selector_wires[key]
        actual = witness.value(pointer_row, x)
        value = 1 if actual == selected_column else 0
        z_index = self.alloc_witness(f"sel(ptr_row={pointer_row},x={x},col={selected_column})", value)
        self.selector_wires[key] = z_index
        self.mark_bit(z_index)
        return z_index

    def compile_sympy_expr(self, expr: sp.Expr, witness: MatrixInterpretation, *, label: str) -> Lin:
        """Compile a SymPy mkQ expression to a linear output plus constraints."""
        expr = sp.sympify(expr)

        def rec(e: sp.Expr, path: str) -> Lin:
            e = sp.sympify(e)
            if e.is_Integer:
                return self.const(int(e))
            if e.is_Rational and e.q == 1:
                return self.const(int(e))
            if e.is_Rational:
                raise R1CSError(f"non-integral rational {e} in {label}")
            if e.is_Symbol:
                index = parse_b_symbol(e)
                return self.wire(self.ensure_b_wire(index, witness))
            if isinstance(e, sp.Add):
                total = self.zero()
                for n, arg in enumerate(e.args):
                    total += rec(arg, f"{path}.add{n}")
                return total
            if isinstance(e, sp.Mul):
                coeff, factors = e.as_coeff_mul()
                out = self.const(int(coeff)) if coeff != 1 else self.const(1)
                for n, factor in enumerate(factors):
                    factor_lin = rec(factor, f"{path}.mul{n}")
                    out = self.mul(out, factor_lin, label=f"{label}:{path}.mul{n}")
                return out
            if isinstance(e, sp.Pow):
                base, exponent = e.as_base_exp()
                if not exponent.is_Integer or int(exponent) < 0:
                    raise R1CSError(f"unsupported exponent {exponent} in {label}")
                exp = int(exponent)
                if exp == 0:
                    return self.const(1)
                base_lin = rec(base, f"{path}.pow.base")
                out = base_lin
                for n in range(1, exp):
                    out = self.mul(out, base_lin, label=f"{label}:{path}.pow{n + 1}")
                return out
            raise R1CSError(f"unsupported SymPy node {type(e).__name__}: {e!s}")

        return rec(expr, label)

    def add_all_pending_boolean_constraints(self) -> None:
        for z_index in sorted(self.bit_wires):
            self.add_boolean_constraint(z_index, f"boolean:{self.wire_names.get(z_index, z_index)}")

    def z_vector(self) -> list[int]:
        return [*self.public_inputs, 1, *self.witness_values]

    def check_all_constraints(self) -> None:
        values = {index: value for index, value in enumerate(self.z_vector())}
        for constraint in self.constraints:
            lhs = constraint.a.eval(values) * constraint.b.eval(values)
            rhs = constraint.c.eval(values)
            if lhs != rhs:
                raise R1CSError(f"constraint {constraint.label!r} failed on final z-vector: {lhs} != {rhs}")


def _lin_sum(parts: Iterable[Lin]) -> Lin:
    out = Lin.zero()
    for part in parts:
        out += part
    return out


def add_pointer_lookup_constraints(
    builder: R1CSBuilder,
    *,
    witness: MatrixInterpretation,
    max_bits: int,
    pointer_rows: Iterable[int],
) -> None:
    """Add one-hot range and lookup constraints for all used pointer rows."""
    pointer_rows = tuple(sorted(set(pointer_rows)))
    for pointer_row in pointer_rows:
        witness.validate_row(pointer_row)
        for x in range(1, witness.length + 1):
            selectors = [
                builder.selector_wire(pointer_row=pointer_row, x=x, selected_column=k, witness=witness)
                for k in range(1, witness.length + 1)
            ]
            selector_lins = [builder.wire(z) for z in selectors]
            builder.assert_zero(
                _lin_sum(selector_lins) - builder.const(1),
                f"range:ptr_row={pointer_row}:x={x}:one_hot",
            )
            pointer_value = builder.b2int_lin(row=pointer_row, pointer=0, x=x, max_bits=max_bits, witness=witness)
            selected_value = _lin_sum(
                builder.wire(selectors[k - 1]).scale(k) for k in range(1, witness.length + 1)
            )
            builder.assert_zero(
                pointer_value - selected_value,
                f"range:ptr_row={pointer_row}:x={x}:value_in_1..len",
            )

    # Link every allocated composed B bit to the selected direct B bit.  This is
    # the CCS/R1CS analogue of the verifier querying the committed row at the
    # private pointer value before evaluating mkQ.
    composed = [idx for idx in sorted(builder.b_wires) if idx.pointer != 0]
    for index in composed:
        if index.pointer not in pointer_rows:
            # Be defensive: if a predicate uses a pointer row that ExampleSpec did
            # not list, we still make it sound by adding its selector machinery.
            add_pointer_lookup_constraints(
                builder,
                witness=witness,
                max_bits=max_bits,
                pointer_rows=(index.pointer,),
            )
            continue
        terms: list[Lin] = []
        for k in range(1, witness.length + 1):
            selector_z = builder.selector_wire(pointer_row=index.pointer, x=index.x, selected_column=k, witness=witness)
            direct_z = builder.ensure_direct_b_wire(row=index.row, x=k, bit=index.bit, witness=witness)
            product = builder.mul(
                builder.wire(selector_z),
                builder.wire(direct_z),
                label=f"lookup_product:B_{index.row}_{index.pointer}_{index.x}_{index.bit}:k={k}",
            )
            terms.append(product)
        composed_z = builder.ensure_b_wire(index, witness)
        builder.assert_zero(
            builder.wire(composed_z) - _lin_sum(terms),
            f"lookup:B_{index.row}_{index.pointer}_{index.x}_{index.bit}",
        )


def final_public_bindings_for_example(example: ExampleSpec) -> tuple[list[int], dict[int, str], tuple[PublicBinding, ...]]:
    """Return public inputs and final-column bindings for comparable benchmarks.

    Public input 0 remains a conventional zero.  For arithmetic examples we add
    public claims for the final input/output cells so that a zkVM comparison can
    prove the same public statement rather than merely proving existence of a
    private valid recurrence table.
    """
    witness = example.witness
    public_inputs: list[int] = [0]
    public_names: dict[int, str] = {0: "public_zero"}
    specs: list[tuple[str, int]]
    if example.name in {"standard_power", "efficient_power"}:
        specs = [("base", 1), ("exponent", 2), ("output", 3)]
    elif example.name == "factorial":
        specs = [("n", 1), ("output", 2)]
    elif example.name == "fibonacci":
        specs = [("n", 1), ("output", 2)]
    else:
        raise R1CSError(f"--public-final is not defined for example {example.name!r}")

    bindings: list[PublicBinding] = []
    x = witness.length
    for short_name, row in specs:
        public_index = len(public_inputs)
        value = witness.value(row, x)
        name = f"claim_final_{short_name}"
        public_inputs.append(value)
        public_names[public_index] = name
        bindings.append(PublicBinding(public_index=public_index, name=name, row=row, x=x, value=value))
    return public_inputs, public_names, tuple(bindings)


def add_public_binding_constraints(
    builder: R1CSBuilder,
    *,
    witness: MatrixInterpretation,
    max_bits: int,
    bindings: Iterable[PublicBinding],
) -> None:
    for binding in bindings:
        if binding.public_index < 0 or binding.public_index >= len(builder.public_inputs):
            raise R1CSError(f"public binding {binding.name!r} points outside public inputs")
        if builder.public_inputs[binding.public_index] != binding.value:
            raise R1CSError(f"public binding {binding.name!r} value does not match public input")
        actual = witness.value(binding.row, binding.x)
        if actual != binding.value:
            raise R1CSError(f"public binding {binding.name!r} value does not match witness")
        witness_entry = builder.b2int_lin(row=binding.row, pointer=0, x=binding.x, max_bits=max_bits, witness=witness)
        public_value = builder.wire(binding.public_index)
        builder.assert_zero(
            witness_entry - public_value,
            f"public_binding:{binding.name}:row={binding.row}:x={binding.x}",
        )


def build_ccs_export(
    example: ExampleSpec,
    *,
    include_sympy_strings: bool = False,
    public_final: bool = False,
) -> dict[str, Any]:
    """Build a JSON-serialisable Zinc CCS/R1CS instance from a zkFOL example."""
    witness = example.witness
    context = CompilationContext.from_witness(witness)
    if public_final:
        public_inputs, public_input_names, public_bindings = final_public_bindings_for_example(example)
    else:
        public_inputs, public_input_names, public_bindings = [0], {0: "public_zero"}, ()
    builder = R1CSBuilder(public_inputs=public_inputs, public_input_names=public_input_names)

    # Allocate all direct matrix bits up front.  This makes the witness-vector
    # prefix stable across examples and makes pointer lookup constraints clear.
    for row in range(1, witness.arity + 1):
        for x in range(1, witness.length + 1):
            for bit in range(1, witness.max_bits + 1):
                builder.ensure_direct_b_wire(row=row, x=x, bit=bit, witness=witness)

    mkq_strings: list[str] = []
    direct_values: list[int] = []
    beta_values: list[int] = []

    for x in range(1, witness.length + 1):
        compiled = context.mkq(example.predicate, x, expand=False)
        if include_sympy_strings:
            mkq_strings.append(str(compiled.expression))
        direct = example.predicate.evaluate(witness, x)
        beta = compiled.beta(witness)
        direct_values.append(direct)
        beta_values.append(beta)
        if direct != beta:
            raise R1CSError(f"direct/beta mismatch at x={x}: {direct} != {beta}")
        value = builder.compile_sympy_expr(compiled.expression, witness, label=f"mkq_x={x}")
        builder.assert_zero(value, f"mkq_zero:x={x}")

    composed_pointer_rows = {index.pointer for index in builder.b_wires if index.pointer != 0}
    pointer_rows = set(example.pointer_rows) | composed_pointer_rows
    add_pointer_lookup_constraints(
        builder,
        witness=witness,
        max_bits=witness.max_bits,
        pointer_rows=pointer_rows,
    )
    add_public_binding_constraints(
        builder,
        witness=witness,
        max_bits=witness.max_bits,
        bindings=public_bindings,
    )
    builder.add_all_pending_boolean_constraints()
    builder.check_all_constraints()

    constraints = [constraint.to_json() for constraint in builder.constraints]
    breakdown = constraint_breakdown(constraints)
    max_abs_value = 0
    for value in [*builder.public_inputs, *builder.witness_values]:
        max_abs_value = max(max_abs_value, abs(value))
    for constraint in constraints:
        for side in ("a", "b", "c"):
            for _, coeff in constraint[side]:
                max_abs_value = max(max_abs_value, abs(int(coeff)))

    direct_rows = witness.as_lists()
    report = {
        "direct_values": direct_values,
        "beta_values": beta_values,
        "fast_beta_values": list(beta_all_fast(example.predicate, witness)),
        "semantics_agree": direct_values == beta_values,
        "all_zero": all(v == 0 for v in beta_values),
        "pointer_range_ok": example.pointer_range_ok(),
    }
    if report["fast_beta_values"] != beta_values:
        raise R1CSError("fast beta and symbolic beta disagree")

    export = {
        "schema": "zkfol-zinc-ccs-v2",
        "name": example.name,
        "description": example.description,
        "adapter_kind": "mkq_beta_bits_to_integer_r1cs_ccs",
        "adapter_version": ADAPTER_VERSION,
        "soundness_note": (
            "This CCS instance uses private bit variables for the reference implementation's B symbols, "
            "boolean constraints for those bits, one-hot selector constraints for pointer range checks, "
            "lookup constraints tying composed B_i,j,x,nu bits to selected direct B_i,0,k,nu bits, and "
            "R1CS arithmetic gates for every mkQ_x(<phi>) = 0 check."
        ),
        "zero_rhs_encoding": "explicit_public_zero",
        "dimensions": {
            "arity": witness.arity,
            "length": witness.length,
            "max_bits": witness.max_bits,
            "public_inputs": len(builder.public_inputs),
            "public_input_names": [builder.public_input_names.get(i, f"public_input_{i}") for i in range(len(builder.public_inputs))],
            "witness_variables": len(builder.witness_values),
            "z_len": len(builder.z_vector()),
            "constraints": len(constraints),
        },
        "ccs": {
            "public_inputs": [str(value) for value in builder.public_inputs],
            "public_input_names": [builder.public_input_names.get(i, f"public_input_{i}") for i in range(len(builder.public_inputs))],
            "public_bindings": [
                {
                    "public_index": binding.public_index,
                    "name": binding.name,
                    "row": binding.row,
                    "x": binding.x,
                    "value": str(binding.value),
                }
                for binding in public_bindings
            ],
            "witness": [str(value) for value in builder.witness_values],
            "constraints": constraints,
        },
        "zkfol": {
            "witness_rows": direct_rows,
            "pointer_rows": sorted(pointer_rows),
            "paper_reference": example.paper_reference,
            "mathematical_description": example.mathematical_description,
            "witness_convention": example.witness_convention,
            "reference_report": report,
        },
        "exposition": build_exposition(example=example, witness=witness, pointer_rows=pointer_rows),
        "wire_names": {str(k): v for k, v in sorted(builder.wire_names.items())},
        "constraint_breakdown": breakdown,
        "benchmark_claim": {
            "public_final": bool(public_final),
            "description": (
                "Public inputs bind the final-column input/output claim for direct zkVM comparison."
                if public_final
                else "No public final claim was bound; this proves existence of a private valid FOL witness table."
            ),
        },
        "stats": {
            "bit_wires": len(builder.bit_wires),
            "b_wires": len(builder.b_wires),
            "selector_wires": len(builder.selector_wires),
            "constraint_breakdown": breakdown,
            "max_abs_value_bit_length": int(max_abs_value).bit_length(),
            "max_abs_value_decimal": str(max_abs_value),
        },
    }
    from .view import concrete_statement_lines  # Local import avoids a presentation-only dependency at module load time.

    export["exposition"]["concrete_statement"] = concrete_statement_lines(export)
    export["benchmark_claim"]["concrete_statement"] = concrete_statement_lines(export)
    if include_sympy_strings:
        export["zkfol"]["mkq_sympy"] = mkq_strings
    attach_constraint_summary(export)
    return export


def dense_matrices_from_export(export: Mapping[str, Any]) -> tuple[list[list[int]], list[list[int]], list[list[int]]]:
    """Return dense A/B/C matrices, useful for tests and debugging."""
    z_len = int(export["dimensions"]["z_len"])
    rows = export["ccs"]["constraints"]
    matrices = []
    for side in ("a", "b", "c"):
        mat: list[list[int]] = []
        for row in rows:
            dense = [0] * z_len
            for index, coeff in row[side]:
                dense[int(index)] += int(coeff)
            mat.append(dense)
        matrices.append(mat)
    return matrices[0], matrices[1], matrices[2]


def check_export_relation(export: Mapping[str, Any]) -> None:
    """Pure-Python R1CS relation checker for exported JSON."""
    public_inputs = [int(v) for v in export["ccs"]["public_inputs"]]
    witness = [int(v) for v in export["ccs"]["witness"]]
    z = [*public_inputs, 1, *witness]
    if len(z) != int(export["dimensions"]["z_len"]):
        raise R1CSError("z length does not match dimensions.z_len")

    for i, row in enumerate(export["ccs"]["constraints"]):
        values: dict[str, int] = {}
        for side in ("a", "b", "c"):
            total = 0
            for index, coeff in row[side]:
                z_index = int(index)
                if z_index < 0 or z_index >= len(z):
                    label = row.get("label", f"row_{i}")
                    raise R1CSError(
                        f"constraint {i} ({label!r}) side {side} references z[{z_index}], "
                        f"but z has length {len(z)}"
                    )
                total += int(coeff) * z[z_index]
            values[side] = total
        if values["a"] * values["b"] != values["c"]:
            raise R1CSError(
                f"constraint {i} ({row.get('label', '<unlabelled>')}) failed: "
                f"{values['a']} * {values['b']} != {values['c']}"
            )
