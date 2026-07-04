"""Doubling-trace emission helpers shared by the Fibonacci formulations.

Circuit construction needs every quantity twice: as a linear form over the
z-vector (what the constraint rows say) and as its concrete integer value
(what the witness contains). :class:`TrackedValue` carries both so trace
code can be written once, in the shape of the mathematical identities,
instead of threading parallel (lin, value) state by hand.

:class:`DoublingChannel` names the two row idioms of a doubling step:

* ``product`` — one multiplication row. Exact mode pins the raw product to
  a fresh wire; modular mode hosts the reduction in the same row's C slot
  as ``c + m*u`` with a quotient witness (the lifted-modular shape of
  eprint 2025/316), returning the reduced value.
* ``sum_of_squares`` — x^2 + y^2. Exact mode is two product rows plus a
  free linear form. Modular mode keeps x^2 raw and reduces the sum inside
  y^2's row (``y*y = d + m*u - x_sq_raw``), saving one witness per step
  over reducing each square separately; operands may sit below 2m, so
  callers must size the integer profile for products below 8m^2
  (see ``crt_fast_doubling_fibonacci.required_int_limbs``).
"""

from __future__ import annotations

from dataclasses import dataclass

from .r1cs import Lin, R1CSBuilder


@dataclass(frozen=True)
class TrackedValue:
    """A circuit quantity: its linear form and its concrete integer value."""

    lin: Lin
    value: int

    def __add__(self, other: "TrackedValue") -> "TrackedValue":
        return TrackedValue(self.lin + other.lin, self.value + other.value)

    def __sub__(self, other: "TrackedValue") -> "TrackedValue":
        return TrackedValue(self.lin - other.lin, self.value - other.value)

    def scale(self, coeff: int) -> "TrackedValue":
        return TrackedValue(self.lin.scale(coeff), self.value * coeff)


class DoublingChannel:
    """Row emitter for one (possibly modular) doubling trace."""

    def __init__(self, builder: R1CSBuilder, tag: str, modulus: int | None = None) -> None:
        self.builder = builder
        self.tag = tag
        self.modulus = modulus

    def constant(self, value: int) -> TrackedValue:
        if self.modulus is not None:
            value %= self.modulus
        return TrackedValue(self.builder.const(value), value)

    def _fresh(self, name: str, value: int) -> TrackedValue:
        wire = self.builder.alloc_witness(f"{self.tag}.{name}", value)
        return TrackedValue(self.builder.wire(wire), value)

    def _reduce(self, raw: int) -> tuple[int, int]:
        reduced = raw % self.modulus
        return reduced, (raw - reduced) // self.modulus

    def product(self, x: TrackedValue, y: TrackedValue, name: str, label: str) -> TrackedValue:
        raw = x.value * y.value
        if self.modulus is None:
            out = self._fresh(name, raw)
            self.builder.add_constraint(x.lin, y.lin, out.lin, label)
            return out
        reduced, quotient = self._reduce(raw)
        out = self._fresh(name, reduced)
        q = self._fresh(f"{name}.q", quotient)
        self.builder.add_constraint(x.lin, y.lin, out.lin + q.lin.scale(self.modulus), label)
        return out

    def sum_of_squares(self, x: TrackedValue, y: TrackedValue, name: str, label_x: str, label_y: str, x_sq_coeff: int = 1) -> TrackedValue:
        """x_sq_coeff * x^2 + y^2; the coefficient rides the linear side for free."""
        if self.modulus is None:
            x_sq = self.product(x, x, f"{name}.x_sq", label_x)
            return x_sq.scale(x_sq_coeff) + self.product(y, y, f"{name}.y_sq", label_y)
        x_sq = self._fresh(f"{name}.x_sq", x.value * x.value)
        self.builder.add_constraint(x.lin, x.lin, x_sq.lin, label_x)
        reduced, quotient = self._reduce(x_sq_coeff * x_sq.value + y.value * y.value)
        out = self._fresh(name, reduced)
        q = self._fresh(f"{name}.q", quotient)
        self.builder.add_constraint(y.lin, y.lin, out.lin + q.lin.scale(self.modulus) - x_sq.lin.scale(x_sq_coeff), label_y)
        return out


def emit_pair_trace(
    builder: R1CSBuilder,
    schedule: list[int],
    tag: str,
    modulus: int | None = None,
    p: int = 1,
    q: int = 1,
) -> tuple[TrackedValue, TrackedValue]:
    """Walk the doubling schedule for U(k) = p*U(k-1) + q*U(k-2), U(1)=1, U(2)=p.

    Returns the pair (U(e), U(e+1)) where e is the index the schedule walks
    to. The companion-matrix power of any order-2 constant-coefficient
    recurrence reduces to this pair via the general doubling identities

        U(2e)   = U(e) * (2*U(e+1) - p*U(e))
        U(2e+1) = q*U(e)^2 + U(e+1)^2

    (p = q = 1 is Fibonacci). Coefficients enter only through free linear
    scalings; each bit costs exactly the three product rows. The next pair is
    always built from linear forms over existing wires, so no copy rows.
    """
    channel = DoublingChannel(builder, tag, modulus)
    a = channel.constant(1)
    b = channel.constant(p)
    for step, bit in enumerate(schedule, start=1):
        c = channel.product(a, b + b - a.scale(p), f"dbl[{step}].c", f"fib_step:double_c:{tag}:step={step}")
        d = channel.sum_of_squares(
            a, b, f"dbl[{step}].d",
            f"fib_step:square_a:{tag}:step={step}",
            f"fib_step:square_b:{tag}:step={step}",
            x_sq_coeff=q,
        )
        a, b = (d, d.scale(p) + c.scale(q)) if bit else (c, d)
    return a, b


def emit_doubling_trace(builder: R1CSBuilder, schedule: list[int], tag: str, modulus: int | None = None) -> TrackedValue:
    """Fibonacci special case: walk the bits of n; returns F(n) = U(n)."""
    a, _ = emit_pair_trace(builder, schedule, tag, modulus)
    return a
