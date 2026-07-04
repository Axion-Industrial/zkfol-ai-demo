"""CRT residue-channel fast-doubling Fibonacci export.

Runs the fast-doubling trace independently modulo k channel moduli whose
product exceeds the known bound on F_n, so every witness value stays
channel-width instead of F_n-width. Reduction rides in each product row's
C slot as c + p*u with a quotient witness (the paper's lifted-modular
shape). The exact integer F_n is recovered outside the circuit by CRT from
the publicly bound residues; the single-channel variant with modulus 2^64
is the RISC Zero statement-parity row.
"""

import pytest

from zkfol_zinc_adapter.crt_fast_doubling_fibonacci import (
    build_crt_fast_doubling_fibonacci_ccs_export,
    build_modular_fast_doubling_fibonacci_ccs_export,
)
from zkfol_zinc_adapter.r1cs import R1CSError, check_export_relation


def _reference_fib(n: int) -> int:
    a, b = 1, 1
    for _ in range(n - 1):
        a, b = b, a + b
    return a


def test_channel_residues_match_reference_fibonacci() -> None:
    export = build_crt_fast_doubling_fibonacci_ccs_export(100, channel_bits=64, check=True)
    fib = _reference_fib(100)
    channels = export["crt"]["channels"]
    assert len(channels) >= 2
    for channel in channels:
        assert int(channel["residue"]) == fib % int(channel["modulus"])


def test_modulus_product_exceeds_output_bound() -> None:
    export = build_crt_fast_doubling_fibonacci_ccs_export(1000, channel_bits=250, check=True)
    product = 1
    for channel in export["crt"]["channels"]:
        product *= int(channel["modulus"])
    assert product > _reference_fib(1000)
    assert export["crt"]["product_bits"] > export["crt"]["output_bound_bits"]


def test_crt_reconstruction_recovers_exact_value() -> None:
    export = build_crt_fast_doubling_fibonacci_ccs_export(50, channel_bits=32, check=True)
    fib = _reference_fib(50)
    residue = 0
    product = 1
    for channel in export["crt"]["channels"]:
        p, r = int(channel["modulus"]), int(channel["residue"])
        # incremental CRT
        if product == 1:
            residue, product = r, p
        else:
            inv = pow(product, -1, p)
            residue += product * ((r - residue) * inv % p)
            product *= p
    assert residue % product == fib % product
    assert residue == fib


def test_tampered_residue_fails_relation_check() -> None:
    export = build_crt_fast_doubling_fibonacci_ccs_export(100, channel_bits=64)
    bindings = [c for c in export["ccs"]["constraints"] if "public_binding:residue" in c["label"]]
    assert bindings
    target = bindings[0]
    target["c"] = [[idx, str(int(coeff) + 1)] for idx, coeff in target["c"]]
    with pytest.raises(R1CSError):
        check_export_relation(export)


def test_channel_width_trades_rows_for_width() -> None:
    wide = build_crt_fast_doubling_fibonacci_ccs_export(10000, channel_bits=500)
    narrow = build_crt_fast_doubling_fibonacci_ccs_export(10000, channel_bits=250)
    assert len(narrow["crt"]["channels"]) > 1.7 * len(wide["crt"]["channels"])
    assert narrow["dimensions"]["constraints"] > 1.7 * wide["dimensions"]["constraints"]
    # the pad-1024 design point: 500-bit channels keep both dims under 1024
    assert wide["dimensions"]["constraints"] < 1024
    assert wide["dimensions"]["z_len"] < 1024


def test_modular_variant_matches_risc0_statement() -> None:
    export = build_modular_fast_doubling_fibonacci_ccs_export(10000, modulus=2**64, check=True)
    assert int(export["crt"]["channels"][0]["residue"]) == _reference_fib(10000) % 2**64
    assert export["dimensions"]["constraints"] < 60


def test_modular_variant_never_materialises_the_exact_fibonacci(monkeypatch) -> None:
    """The congruence claim needs F_n mod m only (O(log n) doubling mod m);
    computing exact F_n would make the exporter Θ(n²) and defeat the log-n
    trace at large n."""
    import sympy

    from zkfol_zinc_adapter import crt_fast_doubling_fibonacci as module

    def _forbidden(n: int) -> tuple[int, int]:
        raise AssertionError("parity export must not compute the exact F_n")

    monkeypatch.setattr(module, "_exact_fibonacci_pair", _forbidden)
    export = build_modular_fast_doubling_fibonacci_ccs_export(10**6, modulus=2**64, check=True)
    expected = int(sympy.fibonacci(10**6)) % 2**64
    assert int(export["crt"]["channels"][0]["residue"]) == expected
