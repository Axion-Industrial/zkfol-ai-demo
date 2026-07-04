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

    def sum_of_squares(self, x: TrackedValue, y: TrackedValue, name: str, label_x: str, label_y: str) -> TrackedValue:
        if self.modulus is None:
            return self.product(x, x, f"{name}.x_sq", label_x) + self.product(y, y, f"{name}.y_sq", label_y)
        x_sq = self._fresh(f"{name}.x_sq", x.value * x.value)
        self.builder.add_constraint(x.lin, x.lin, x_sq.lin, label_x)
        reduced, quotient = self._reduce(x_sq.value + y.value * y.value)
        out = self._fresh(name, reduced)
        q = self._fresh(f"{name}.q", quotient)
        self.builder.add_constraint(y.lin, y.lin, out.lin + q.lin.scale(self.modulus) - x_sq.lin, label_y)
        return out


def emit_doubling_trace(builder: R1CSBuilder, schedule: list[int], tag: str, modulus: int | None = None) -> TrackedValue:
    """Walk the doubling schedule; return F(n) as a tracked value.

    State pair (a, b) = (F(k), F(k+1)) starting at k = 1, advanced per bit by
    F(2k) = a*(2b - a) and F(2k+1) = a^2 + b^2. The next pair is built from
    linear forms over existing wires, so steps cost only their product rows.
    """
    channel = DoublingChannel(builder, tag, modulus)
    a = channel.constant(1)
    b = channel.constant(1)
    for step, bit in enumerate(schedule, start=1):
        c = channel.product(a, b + b - a, f"dbl[{step}].c", f"fib_step:double_c:{tag}:step={step}")
        d = channel.sum_of_squares(
            a, b, f"dbl[{step}].d",
            f"fib_step:square_a:{tag}:step={step}",
            f"fib_step:square_b:{tag}:step={step}",
        )
        a, b = (d, c + d) if bit else (c, d)
    return a
