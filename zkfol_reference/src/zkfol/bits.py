"""Binary decomposition helpers for zkFOL.

Paper pointer: Definition 2.2 defines ``b2int(s_1, ..., s_mu)`` as the sum
``s_nu * 2**(nu - 1)``.  The first bit is therefore the least significant bit.
This module makes that convention explicit by naming functions ``*_lsb_first``.

This matters because ``mkQ`` in Figure 4 replaces ``C_i(X)`` and
``C_i(C_j(X))`` by ``b2int`` expressions over formal ``B`` variables, and beta
in Definition 3.6 then substitutes the corresponding witness bits.
"""

from __future__ import annotations

from typing import Iterable, Sequence


def ensure_non_negative_int(value: int, *, name: str = "value") -> int:
    if not isinstance(value, int):
        raise TypeError(f"{name} must be an int")
    if value < 0:
        raise ValueError(f"{name} must be non-negative")
    return value


def bits_lsb_first(value: int, width: int | None = None) -> tuple[int, ...]:
    """Return the binary digits of value, least-significant bit first.

    If width is supplied, the result is zero-padded to exactly width bits.
    Width may not be smaller than the natural bit length of value.
    """
    ensure_non_negative_int(value)
    if width is not None:
        if width < 1:
            raise ValueError("width must be positive")
        if value.bit_length() > width:
            raise ValueError("width is too small for value")
    natural_width = max(1, value.bit_length())
    out_width = width if width is not None else natural_width
    return tuple((value >> k) & 1 for k in range(out_width))


def bit_at_lsb_first(value: int, bit: int) -> int:
    """Return 1-based bit number bit in least-significant-bit-first order."""
    ensure_non_negative_int(value)
    if bit < 1:
        raise ValueError("bit must be 1-based and positive")
    return (value >> (bit - 1)) & 1


def b2int(bits: Iterable[int]) -> int:
    """Convert least-significant-bit-first binary digits to an integer."""
    total = 0
    for offset, bit in enumerate(bits):
        if bit not in (0, 1):
            raise ValueError("bits must be 0 or 1")
        total += bit << offset
    return total


def max_bit_length(values: Iterable[int]) -> int:
    """Return max(1, max bit length) over non-negative integer values."""
    max_len = 1
    seen = False
    for value in values:
        ensure_non_negative_int(value)
        seen = True
        max_len = max(max_len, value.bit_length())
    if not seen:
        raise ValueError("max_bit_length needs at least one value")
    return max_len
