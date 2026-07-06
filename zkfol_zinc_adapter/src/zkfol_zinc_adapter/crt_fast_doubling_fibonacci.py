"""CRT residue-channel fast-doubling Fibonacci CCS exporter.

The plain fast-doubling export (:mod:`zkfol_zinc_adapter.fast_doubling_fibonacci`)
has a logarithmic trace but carries exact F_n-width integers, so proof size
and PCS column checks scale with the output's bit-length. This module runs
the same doubling trace independently in k residue channels: channel i
computes modulo a public prime p_i, every witness value stays channel-width,
and the exact integer F_n is pinned by the Chinese remainder theorem because
the product of the channel moduli exceeds the public bound on F_n.

Reduction uses the lifted-modular row shape from the Zinc paper (eprint
2025/316, relation R1CSl): a product row's C slot hosts the reduced value
plus modulus-scaled quotient witnesses, c + p*u, so modular arithmetic costs
one or two extra witness entries per row and no bit decomposition.

Per doubling step and channel (state pair a = F(k) mod p, b = F(k+1) mod p):

    row 1:  a * (2b - a) = c + p*u1          c = F(2k) mod p
    row 2:  a * a        = t2raw
    row 3:  b * b        = d + p*u2 - t2raw  d = F(2k+1) mod p

For a bit-1 step the next pair is (d, c + d) with c + d carried unreduced
(< 2p) as a linear form; operand magnitudes stay below 2p and products below
8p^2, so a channel of w-bit moduli needs Int<N> with 64N - 1 >= 2w + 4.

The in-circuit claim is the vector of residues (bound as public relation
constants per channel); the reconstruction of the exact F_n from residues,
moduli, and the public growth bound is ordinary public computation performed
outside the circuit and documented in the export.

The single-channel variant with modulus 2^64 (not prime; primality is not
required for a congruence claim) is the statement-parity row for RISC Zero's
documented mod-2^64 Fibonacci benchmark.
"""

from __future__ import annotations

from typing import Any

from sympy import nextprime

from .direct_fibonacci import FIBONACCI_REFERENCE, _short_decimal
from .doubling_trace import emit_doubling_trace
from .export_scaffold import assemble_builder_export, relation_constant_binding
from .fast_doubling_fibonacci import _doubling_schedule
from .metadata import ADAPTER_VERSION
from .r1cs import Lin, R1CSBuilder


def _exact_fibonacci_pair(n: int) -> tuple[int, int]:
    """(F(n), F(n+1)) with fib(1) = fib(2) = 1."""
    a, b = 1, 1
    for _ in range(n - 1):
        a, b = b, a + b
    return a, b


def _modular_fibonacci_pair(n: int, modulus: int) -> tuple[int, int]:
    """(F(n) mod m, F(n+1) mod m) by fast doubling: O(log n) mulmods.

    The congruence claim never needs the exact F_n; materializing it would
    cost Θ(n²) bit operations and defeat the logarithmic trace at large n.
    """
    a, b = 0, 1  # (F(0), F(1)) mod m
    for bit in bin(n)[2:]:
        c = a * (2 * b - a) % modulus
        d = (a * a + b * b) % modulus
        a, b = (d, (c + d) % modulus) if bit == "1" else (c, d)
    return a, b


def _channel_moduli(output: int, channel_bits: int) -> list[int]:
    """Deterministic primes of ~channel_bits bits whose product exceeds output."""
    moduli: list[int] = []
    product = 1
    candidate = 1 << (channel_bits - 1)
    while product <= output:
        candidate = nextprime(candidate)
        moduli.append(int(candidate))
        product *= int(candidate)
    return moduli


def required_int_limbs(channel_bits: int) -> int:
    """Smallest Int<N> limb count whose signed range holds 8 * p^2."""
    needed_bits = 2 * channel_bits + 4
    limbs = -(-needed_bits // 64)
    for profile in (2, 4, 8, 16, 32, 64, 128):
        if profile >= limbs:
            return profile
    raise ValueError(f"channel_bits={channel_bits} exceeds the widest runner profile")


def _channel_trace(builder: R1CSBuilder, n: int, modulus: int, tag: str) -> tuple[Lin, int]:
    """Emit one channel's doubling trace; return the final reduced F(n) form."""
    final = emit_doubling_trace(builder, _doubling_schedule(n), tag, modulus)
    return final.lin, final.value


def _build_export(n: int, moduli: list[int], *, name: str, profile: str, channel_bits: int, exact_claim: bool, check: bool, exact_output: int | None = None) -> dict[str, Any]:
    # The exact F_n exists only for the CRT exact-value claim (the caller
    # already computed it to pick the moduli); a congruence claim runs
    # entirely in O(log n) modular arithmetic.
    output = exact_output
    assert (output is not None) == exact_claim
    public_inputs = [0]
    public_input_names = {0: "public_zero"}
    builder = R1CSBuilder(public_inputs=public_inputs, public_input_names=public_input_names)

    channels: list[dict[str, str]] = []
    for index, modulus in enumerate(moduli, start=1):
        final_lin, final_val = _channel_trace(builder, n, modulus, f"ch{index}")
        assert final_val == _modular_fibonacci_pair(n, modulus)[0]
        builder.add_constraint(
            final_lin, builder.const(1), builder.const(final_val),
            f"public_binding:residue:ch={index}",
        )
        channels.append({"modulus": str(modulus), "residue": str(final_val)})

    steps = len(_doubling_schedule(n))
    product_bits = sum(m.bit_length() for m in moduli)
    fib_bits = output.bit_length() if exact_claim else None
    if exact_claim:
        statement_line = (
            f"Concrete computation: exact non-modular Fibonacci F_{n} = {_short_decimal(output)}, "
            f"pinned by {len(moduli)} public residues whose modulus product exceeds the output bound."
        )
        claim_value = str(output)
    else:
        statement_line = (
            f"Concrete computation: Fibonacci F_{n} mod {moduli[0]} = {channels[0]['residue']} "
            f"(statement parity with RISC Zero's documented mod-2^64 benchmark)."
        )
        claim_value = channels[0]["residue"]

    sections: dict[str, Any] = {
        "crt": {
            "channels": channels,
            "channel_bits": channel_bits,
            "product_bits": product_bits,
            "output_bound_bits": fib_bits,
            "required_int_limbs": required_int_limbs(channel_bits),
            "reconstruction": (
                "The exact integer is the unique value below the modulus product agreeing with every "
                "public residue; reconstruct by CRT from (modulus, residue) pairs and check against "
                "the claimed decimal."
                if exact_claim
                else "Single-channel congruence claim; no reconstruction step."
            ),
            "reconstructed_output_preview": _short_decimal(output) if exact_claim else None,
        },
        "zkfol": {
            "pointer_rows": [],
            "paper_reference": FIBONACCI_REFERENCE,
            "mathematical_description": (
                f"Fast-doubling Fibonacci in {len(moduli)} residue channel(s); "
                f"lifted-modular reduction per product row; public residue binding per channel."
            ),
            "witness_convention": (
                "Per channel and step: c, u1, a_sq, d, u2 (reduced values and quotients). "
                "State pair carried as linear forms; bit-1 steps carry b = c + d unreduced (< 2p)."
            ),
        },
        "exposition": {
            "adapter_version": ADAPTER_VERSION,
            "what_this_file_is": (
                "A self-contained Fibonacci benchmark input for the Rust Zinc runner using residue-channel "
                "fast doubling: logarithmic trace and channel-width witness values."
            ),
            "concrete_statement": [
                statement_line,
                f"Channel width: ~{channel_bits} bits; witness values never exceed twice a channel modulus.",
                f"Recommended runner profile: --int-limbs {required_int_limbs(channel_bits)} --field-limbs 4.",
            ],
            "what_is_being_proved": (
                "Knowledge of doubling-step residues satisfying the channel recurrences, ending at the "
                "publicly bound residues. Value claim, not a trace attestation."
            ),
            "pipeline": [
                {"stage": "Fast-doubling schedule", "meaning": f"The bits of n={n} fix {steps} doubling steps."},
                {"stage": "Residue channels", "meaning": f"{len(moduli)} channel(s); reduction via c + p*u quotient rows."},
                {"stage": "Zinc prove/verify", "meaning": "The Rust runner checks the integer relation, pads, then invokes Zinc."},
                {"stage": "CRT reconstruction", "meaning": "Public post-processing pins the exact integer from the residues."},
            ],
            "benchmarking_notes": [
                "Channel width trades padded dimension (many narrow channels) against integer width (few wide channels).",
                "Same public meaning as fibonacci_exact_n{n} once CRT reconstruction is applied.",
            ],
        },
    }
    return assemble_builder_export(
        builder,
        name=name,
        description=statement_line,
        adapter_kind="crt_fast_doubling_fibonacci_to_integer_r1cs_ccs",
        soundness_note=(
            "Fast-doubling trace run independently per residue channel with lifted-modular reduction "
            "rows (c + p*u quotient witnesses). In-circuit claims are the per-channel residues as "
            "public relation constants. For the exact-value claim, uniqueness of the reconstructed "
            "integer follows from the public bound on F_n and the modulus product; the reconstruction "
            "itself is public computation outside the circuit. Congruence soundness does not require "
            "prime moduli; primes are used for the CRT channels to make the moduli trivially coprime."
        ),
        row_orientation="products_with_lifted_modular_reduction",
        profile=profile,
        length=steps,
        max_bits=max(int(c["modulus"]).bit_length() for c in channels) * 2 + 4,
        public_claims=[
            {"name": "claim_n", "value": str(n), "encoded_as": "public_relation_structure"},
            {"name": "claim_fibonacci_n_exact" if exact_claim else "claim_fibonacci_n_mod", "value": claim_value, "encoded_as": "crt_residues" if exact_claim else "public_ccs_constant"},
        ],
        public_bindings=[
            relation_constant_binding(f"residue_ch{i}", channel["residue"])
            for i, channel in enumerate(channels, start=1)
        ],
        benchmark_claim={
            "public_final": True,
            "description": statement_line,
            "concrete_statement": [statement_line],
        },
        exact_arithmetic={
            "modulus": None if exact_claim else str(moduli[0]),
            "modulus_note": (
                "Exact value pinned by CRT over the channel moduli."
                if exact_claim
                else "Single-channel congruence claim; matches RISC Zero's documented arithmetic."
            ),
            "n": n,
            "fibonacci_indexing": "fib(1)=fib(2)=1, equivalent to standard F_n with F_0=0,F_1=1 for n>=1.",
            "output_bit_length": fib_bits if exact_claim else int(claim_value).bit_length(),
            "output_decimal_digits": len(str(output)) if exact_claim else len(claim_value),
            "output_decimal_preview": _short_decimal(output) if exact_claim else claim_value,
        },
        sections=sections,
        check=check,
    )


def build_crt_fast_doubling_fibonacci_ccs_export(n: int, *, channel_bits: int = 250, check: bool = False) -> dict[str, Any]:
    if n < 1:
        raise ValueError("n must be positive")
    if channel_bits < 8:
        raise ValueError("channel_bits must be at least 8")
    output, _ = _exact_fibonacci_pair(n)
    moduli = _channel_moduli(output, channel_bits)
    return _build_export(
        n, moduli,
        name=f"fibonacci_crtdbl_n{n}_cb{channel_bits}",
        profile="crt-fast-doubling",
        channel_bits=channel_bits,
        exact_claim=True,
        check=check,
        exact_output=output,
    )


def build_modular_fast_doubling_fibonacci_ccs_export(n: int, *, modulus: int = 2**64, check: bool = False) -> dict[str, Any]:
    if n < 1:
        raise ValueError("n must be positive")
    if modulus < 2:
        raise ValueError("modulus must be at least 2")
    return _build_export(
        n, [modulus],
        name=f"fibonacci_moddbl_n{n}",
        profile="modular-fast-doubling",
        channel_bits=modulus.bit_length(),
        exact_claim=False,
        check=check,
    )
