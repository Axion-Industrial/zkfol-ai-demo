"""The generated benchmark summary must lead with a plain-English headline.

A reader who knows nothing about CCS internals should learn, from the top of
the file: what was proved, how long it took end to end, where the time went,
how big the proof is, and how that compares to the published RISC Zero
Fibonacci numbers.
"""

from pathlib import Path

from zkfol_zinc_adapter.bench import (
    _fmt_bytes,
    _fmt_duration_ms,
    _size_summary_from_export,
    write_markdown_summary,
)


def test_claim_column_takes_a_plain_string_statement_whole() -> None:
    """concrete_statement is a list in all in-repo exports, but a hand-authored
    or foreign export may carry a plain string; iterating it must not reduce
    the claim column to its first character."""
    statement = "Concrete computation: exact non-modular Fibonacci F_10."
    export = {
        "dimensions": {"length": 10},
        "ccs": {"public_inputs": ["0"], "witness": [], "constraints": []},
        "benchmark_claim": {"concrete_statement": statement},
    }
    row = _size_summary_from_export("case", Path("x.json"), export)
    assert row["claim"] == statement


def test_durations_render_in_humane_units() -> None:
    assert _fmt_duration_ms(3716.5698) == "3.72 s"
    assert _fmt_duration_ms(2402.25) == "2.40 s"
    assert _fmt_duration_ms(160.0) == "160 ms"
    assert _fmt_duration_ms(44.5008) == "44.5 ms"
    assert _fmt_duration_ms(0.6) == "0.60 ms"


def test_byte_sizes_render_in_humane_units() -> None:
    assert _fmt_bytes(512) == "512 B"
    assert _fmt_bytes(700_288) == "684 KiB"
    assert _fmt_bytes(8_867_840) == "8.46 MiB"
    assert _fmt_bytes(635_000_000) == "606 MiB"


def _fib_size_row() -> dict:
    return {
        "case": "fibonacci_exact_n1000_public",
        "profile": "compact",
        "length": 1000,
        "constraints": 1001,
        "witness_variables": 1000,
        "claim": "Concrete computation: exact non-modular Fibonacci F_1000 (209 decimal digits).",
    }


def _fib_run_row() -> dict:
    return {
        "case": "fibonacci_exact_n1000_public",
        "int_limbs": 16,
        "constraints_unpadded": 1001,
        "ccs_m_padded": 1024,
        "ccs_n_padded": 1024,
        "relation_check_ms": 5.6,
        "prove_ms": 160.0,
        "verify_ms": 3716.5698,
        "field_setup_ms": 2300.0,
        "field_relation_check_ms": 68.0,
        "zinc_prove_call_ms": 160.0,
        "zinc_verify_call_ms": 3716.5698,
        "measured_iteration_ms": 6180.0,
        "proof_size_bytes_estimate": 1_237_000,
        "peak_rss_bytes": 635_000_000,
        "repeat": 3,
        "proved": True,
    }


def test_summary_leads_with_plain_english_headline(tmp_path: Path) -> None:
    out = tmp_path / "SUMMARY.md"
    write_markdown_summary(out, [_fib_size_row()], [_fib_run_row()])
    text = out.read_text(encoding="utf-8")

    assert "## Headline results" in text
    assert text.index("## Headline results") < text.index("## FOL+Zinc input sizes")

    # What was proved, in words, not a case stem.
    assert "exact non-modular Fibonacci F_1000" in text
    # Wall-clock total and the dominant costs, with shares of the total.
    assert "6.18 s" in text
    assert "3.72 s (60%)" in text
    assert "2.30 s (37%)" in text
    # Proof size and peak memory in humane units.
    assert "1.18 MiB" in text
    assert "606 MiB" in text
    # The external comparison the project measures itself against.
    assert "RTX A6000" in text


def test_headline_survives_missing_proof_metrics(tmp_path: Path) -> None:
    run = _fib_run_row()
    del run["proof_size_bytes_estimate"]
    del run["peak_rss_bytes"]
    out = tmp_path / "SUMMARY.md"
    write_markdown_summary(out, [_fib_size_row()], [run])
    text = out.read_text(encoding="utf-8")
    assert "## Headline results" in text
    assert "n/a" in text
