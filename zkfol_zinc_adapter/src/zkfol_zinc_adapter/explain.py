"""Human-readable explanations for exported zkFOL -> Zinc instances."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any, Iterable

from .constraint_summary import compute_constraint_summary, format_constraint_summary
from .metadata import (
    BENCHMARKING_NOTES,
    CONSTRAINT_BREAKDOWN_DESCRIPTIONS,
    FIELD_GLOSSARY,
    PIPELINE_STEPS,
    SECURITY_NOTES,
)
from .view import concrete_statement_lines, emphasize_concrete_line, public_input_summary


def _get(mapping: dict[str, Any], *path: str, default: Any = None) -> Any:
    cur: Any = mapping
    for key in path:
        if not isinstance(cur, dict) or key not in cur:
            return default
        cur = cur[key]
    return cur


def _yes(value: Any) -> str:
    if value is True:
        return "yes"
    if value is False:
        return "NO"
    if value is None:
        return "not recorded"
    return str(value)


def _preview_row(row: Iterable[Any], *, max_items: int = 12) -> str:
    values = list(row)
    shown = values[:max_items]
    text = ", ".join(str(v) for v in shown)
    if len(values) > max_items:
        text += f", ... ({len(values)} entries total)"
    return text


def _format_number(value: Any) -> str:
    if value is None:
        return "not recorded"
    return str(value)


def _constraint_breakdown_lines(export: dict[str, Any]) -> list[str]:
    breakdown = export.get("constraint_breakdown") or _get(export, "stats", "constraint_breakdown", default={})
    if not isinstance(breakdown, dict) or not breakdown:
        return ["not recorded"]
    lines = []
    for key, description in CONSTRAINT_BREAKDOWN_DESCRIPTIONS.items():
        value = int(breakdown.get(key, 0) or 0)
        if value:
            lines.append(f"{value:>8}  {key:<40} {description}")
    return lines or ["all recorded categories are zero"]


def format_export_summary(
    export: dict[str, Any],
    *,
    path: str | Path | None = None,
    compact: bool = False,
    include_witness_preview: bool = True,
) -> str:
    """Return a readable explanation of an exported JSON instance."""
    dims = export.get("dimensions", {})
    stats = export.get("stats", {})
    zkfol = export.get("zkfol", {})
    report = zkfol.get("reference_report", {})
    exposition = export.get("exposition", {})

    name = export.get("name", "<unknown>")
    description = export.get("description") or _get(exposition, "example_summary", "description", default="")
    math = _get(zkfol, "mathematical_description", default=None) or _get(
        exposition, "example_summary", "mathematical_description", default="not recorded"
    )
    convention = _get(zkfol, "witness_convention", default=None) or _get(
        exposition, "example_summary", "witness_convention", default="not recorded"
    )
    pointer_rows = _get(zkfol, "pointer_rows", default=_get(exposition, "example_summary", "pointer_rows", default=[]))

    if compact:
        lines = [f"Wrote {path}" if path else f"Exported {name}"]
        lines.append(f"  example: {name} - {description}")
        for statement_line in concrete_statement_lines(export):
            lines.append(f"  {emphasize_concrete_line(statement_line)}")
        lines.append(f"  public inputs: {public_input_summary(export)}")
        lines.append(
            "  FOL witness: "
            f"arity={_format_number(dims.get('arity'))}, "
            f"length={_format_number(dims.get('length'))}, "
            f"max_bits={_format_number(dims.get('max_bits'))}, "
            f"pointer_rows={pointer_rows}"
        )
        lines.append(
            "  semantic checks: "
            f"direct=beta=fast_beta? {_yes(report.get('semantics_agree'))}; "
            f"all predicate values zero? {_yes(report.get('all_zero'))}; "
            f"pointer ranges OK? {_yes(report.get('pointer_range_ok'))}"
        )
        lines.append(
            "  CCS/R1CS: "
            f"constraints={_format_number(dims.get('constraints'))}, "
            f"private_witness_variables={_format_number(dims.get('witness_variables'))}, "
            f"z_len={_format_number(dims.get('z_len'))}, "
            f"public_inputs={_format_number(dims.get('public_inputs'))}, "
            f"largest_abs_value_bits={_format_number(stats.get('max_abs_value_bit_length'))}"
        )
        lines.append("  Zinc constraint shape: " + format_constraint_summary(export))
        lines.append("  Run Zinc with: cargo run --release -- --input <that-json> --repeat 3")
        lines.append("  For a field-by-field explanation: zkfol-zinc-explain <that-json>")
        return "\n".join(lines)

    lines: list[str] = []
    lines.append("zkFOL -> Zinc exported instance")
    lines.append("=" * 36)
    if path:
        lines.append(f"File: {path}")
    lines.append(f"Example: {name}")
    if description:
        lines.append(f"Description: {description}")
    lines.append(f"Schema: {export.get('schema', 'not recorded')}")
    lines.append(f"Adapter version: {export.get('adapter_version', _get(exposition, 'adapter_version', default='not recorded'))}")
    lines.append("")

    lines.append("Concrete computation / public claim")
    lines.append("-----------------------------------")
    for statement_line in concrete_statement_lines(export):
        lines.append(emphasize_concrete_line(statement_line))
    lines.append(f"Public inputs: {public_input_summary(export)}")
    lines.append("")

    lines.append("What the FOL instance says")
    lines.append("--------------------------")
    lines.append(f"Mathematical meaning: {math}")
    lines.append(f"Witness convention: {convention}")
    lines.append(f"Pointer rows: {pointer_rows}")
    paper_ref = _get(zkfol, "paper_reference", default=None) or _get(
        exposition, "example_summary", "paper_reference", default=None
    )
    if paper_ref:
        lines.append(f"Paper reference recorded in JSON: {paper_ref}")
    lines.append("")

    lines.append("What is being proved")
    lines.append("--------------------")
    lines.append(
        _get(
            exposition,
            "what_is_being_proved",
            default=(
                "Knowledge of a witness vector satisfying the exported signed integer CCS relation. "
                "The exporter records how that CCS relation was produced from the FOL instance."
            ),
        )
    )
    lines.append(
        _get(
            exposition,
            "why_zero_matters",
            default=(
                "In the paper's integer semantics, zero represents truth. The benchmark therefore expects "
                "direct predicate values and beta_F(mkQ_x(<phi>)) values to be zero."
            ),
        )
    )
    lines.append("")

    lines.append("Local semantic checks")
    lines.append("---------------------")
    adapter_kind = str(export.get("adapter_kind", ""))
    if adapter_kind.startswith("direct_integer_fol_trace"):
        lines.append(
            "This direct benchmark profile checks the exact integer trace relation locally. "
            "It is derived from the FOL Fibonacci witness convention but does not materialise "
            "the generic B-bit beta_F(mkQ_x(<phi>)) bridge for the large benchmark indices."
        )
        lines.append(f"Direct trace relation checks pass: {_yes(report.get('all_zero'))}")
        lines.append(f"Pointer row/range convention pass: {_yes(report.get('pointer_range_ok'))}")
    else:
        lines.append(
            "The reference implementation evaluates the predicate three ways: direct FOL semantics, "
            "symbolic beta_F(mkQ_x(<phi>)), and an independent fast beta evaluator."
        )
        lines.append(f"Direct semantics agrees with beta checks: {_yes(report.get('semantics_agree'))}")
        lines.append(f"All predicate values are zero: {_yes(report.get('all_zero'))}")
        lines.append(f"Pointer range checks pass: {_yes(report.get('pointer_range_ok'))}")
    direct_values = report.get("direct_values")
    beta_values = report.get("beta_values")
    if isinstance(direct_values, list) and direct_values and len(direct_values) <= 20:
        lines.append(f"direct_values by x: {direct_values}")
    if isinstance(beta_values, list) and beta_values and len(beta_values) <= 20:
        lines.append(f"beta_values by x:   {beta_values}")
    lines.append("")

    if include_witness_preview:
        rows = _get(zkfol, "witness_rows", default=None)
        if isinstance(rows, list):
            lines.append("Witness matrix preview")
            lines.append("----------------------")
            lines.append(
                f"C has arity={_format_number(dims.get('arity'))} rows and "
                f"length={_format_number(dims.get('length'))} columns."
            )
            for idx, row in enumerate(rows[:10], start=1):
                if isinstance(row, list):
                    lines.append(f"C{idx}: [{_preview_row(row)}]")
            if len(rows) > 10:
                lines.append(f"... ({len(rows)} rows total)")
            lines.append("")

    summary = compute_constraint_summary(export)
    lines.append("Zinc constraint shape for this target")
    lines.append("-------------------------------------")
    lines.append(f"target use case:            {summary['target_use_case']}")
    lines.append(f"scalar z variables:        {summary['scalar_variables_unpadded']} before padding = {summary['public_input_variables']} public + 1 constant-one + {summary['private_witness_variables']} private")
    lines.append(f"constraints:               {summary['constraints_unpadded']} rows before padding")
    lines.append(f"padded CCS dimension:      {summary['padded_ccs_dimension_estimate']} estimated power-of-two dimension")
    lines.append(f"declared CCS degree:       {summary['ccs_declared_degree']} (<A,z>*<B,z>=<C,z>)")
    lines.append(f"simplified witness degree: at most {summary['max_simplified_degree_over_private_witness']} after fixing public inputs and the constant-one coordinate")
    lines.append(f"bit-bound delta:           {summary['bit_bound_delta']} bits")
    lines.append(f"  public input bits:       {summary['max_public_input_bit_length']}")
    lines.append(f"  witness value bits:      {summary['max_witness_value_bit_length']}")
    lines.append(f"  coefficient bits:        {summary['max_constraint_coefficient_bit_length']}")
    lines.append("Interpretation: this is the practical scalar CCS shape handed to Zinc. The paper-level AIR notation also tracks arity, hypercube dimension, and a bit-length bound delta; this adapter materialises that path as an integer R1CS/CCS bridge.")
    lines.append("")

    lines.append("Compiled CCS/R1CS size")
    lines.append("----------------------")
    lines.append(f"constraints:               {_format_number(dims.get('constraints'))}")
    lines.append(f"public inputs:             {_format_number(dims.get('public_inputs'))}")
    names = _get(export, "ccs", "public_input_names", default=None)
    values = _get(export, "ccs", "public_inputs", default=None)
    if isinstance(names, list) and isinstance(values, list):
        preview = ", ".join(f"{n}={v}" for n, v in list(zip(names, values))[:8])
        if len(names) > 8:
            preview += f", ... ({len(names)} total)"
        lines.append(f"public input values:       {preview}")
    bindings = _get(export, "ccs", "public_bindings", default=[])
    if isinstance(bindings, list) and bindings:
        lines.append("public bindings:           " + ", ".join(str(b.get("name", "<binding>")) for b in bindings))
    lines.append(f"private witness variables: {_format_number(dims.get('witness_variables'))}")
    lines.append(f"z-vector length:           {_format_number(dims.get('z_len'))}")
    lines.append(f"B-variable wires:          {_format_number(stats.get('b_wires'))}")
    lines.append(f"Boolean-constrained wires: {_format_number(stats.get('bit_wires'))}")
    lines.append(f"selector wires:            {_format_number(stats.get('selector_wires'))}")
    lines.append(f"largest abs value bits:    {_format_number(stats.get('max_abs_value_bit_length'))}")
    lines.append("")

    lines.append("Constraint breakdown")
    lines.append("--------------------")
    for line in _constraint_breakdown_lines(export):
        lines.append(line)
    lines.append("")

    lines.append("Pipeline represented by this file")
    lines.append("----------------------------------")
    for i, step in enumerate(_get(exposition, "pipeline", default=PIPELINE_STEPS), start=1):
        if isinstance(step, dict):
            lines.append(f"{i}. {step.get('stage', '<stage>')}: {step.get('meaning', '')}")
        else:
            lines.append(f"{i}. {step}")
    lines.append("")

    lines.append("How to interpret the Rust runner output")
    lines.append("---------------------------------------")
    lines.append(
        "The runner first performs a local integer relation check. This catches export/ingestion mistakes "
        "before calling the proof system. It then pads the CCS dimensions and runs Zinc prove and verify."
    )
    for key in [
        "relation_check_ms",
        "field_setup_ms",
        "field_relation_check_ms",
        "zinc_prove_call_ms",
        "zinc_verify_call_ms",
        "measured_iteration_ms",
        "prove_ms",
        "verify_ms",
        "constraints_unpadded",
        "ccs_m_padded",
        "ccs_n_padded",
        "proved",
    ]:
        lines.append(f"{key}: {FIELD_GLOSSARY.get(key, 'see JSON')}")
    lines.append("")

    lines.append("Benchmarking notes")
    lines.append("------------------")
    for note in _get(exposition, "benchmarking_notes", default=BENCHMARKING_NOTES):
        lines.append(f"- {note}")
    lines.append("")

    lines.append("Prototype/security notes")
    lines.append("------------------------")
    for note in _get(exposition, "security_notes", default=SECURITY_NOTES):
        lines.append(f"- {note}")

    return "\n".join(lines)


def load_export(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as f:
        data = json.load(f)
    if not isinstance(data, dict):
        raise ValueError(f"{path} did not contain a JSON object")
    return data


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="zkfol-zinc-explain",
        description="Explain a JSON file produced by zkfol-zinc-export.",
    )
    parser.add_argument("paths", nargs="+", type=Path, help="exported JSON file(s)")
    parser.add_argument("--compact", action="store_true", help="print a shorter summary")
    parser.add_argument("--no-witness-preview", action="store_true", help="do not show witness rows")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    for n, path in enumerate(args.paths):
        if n:
            print("\n" + "-" * 80 + "\n")
        export = load_export(path)
        print(
            format_export_summary(
                export,
                path=path,
                compact=args.compact,
                include_witness_preview=not args.no_witness_preview,
            )
        )
    return 0


if __name__ == "__main__":  # pragma: no cover
    raise SystemExit(main())
