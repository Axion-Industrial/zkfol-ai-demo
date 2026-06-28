"""Readable inspection helpers for exported zkFOL -> Zinc JSON files."""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path
from typing import Any, Iterable, Mapping, Sequence

from .constraint_summary import compute_constraint_summary, format_constraint_summary



def should_use_ansi() -> bool:
    """Return true when human console output may use ANSI emphasis."""
    return sys.stdout.isatty() and os.environ.get("NO_COLOR") is None


def emphasize_concrete_line(line: str, *, enabled: bool | None = None) -> str:
    """Bold the main concrete-computation line in terminal output."""
    if enabled is None:
        enabled = should_use_ansi()
    if enabled and line.startswith("Concrete computation:"):
        return f"\033[1m{line}\033[0m"
    return line

def load_export(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as f:
        data = json.load(f)
    if not isinstance(data, dict):
        raise ValueError(f"{path} did not contain a JSON object")
    return data


def _get(mapping: Mapping[str, Any], *path: str, default: Any = None) -> Any:
    cur: Any = mapping
    for key in path:
        if not isinstance(cur, Mapping) or key not in cur:
            return default
        cur = cur[key]
    return cur


def _short_text(value: Any, *, max_chars: int = 32) -> str:
    text = str(value)
    if max_chars <= 0 or len(text) <= max_chars:
        return text
    if max_chars < 12:
        return text[:max_chars]
    keep = max(4, (max_chars - 5) // 2)
    return f"{text[:keep]}...{text[-keep:]}"


def _short_decimal(value: Any, *, max_chars: int = 80) -> str:
    return _short_text(value, max_chars=max_chars)


def _public_inputs(export: Mapping[str, Any]) -> tuple[list[str], list[str]]:
    values = list(_get(export, "ccs", "public_inputs", default=[]) or [])
    names = list(_get(export, "ccs", "public_input_names", default=[]) or [])
    if len(names) < len(values):
        names.extend(f"public_input_{i}" for i in range(len(names), len(values)))
    return [str(v) for v in values], [str(n) for n in names]


def public_input_summary(export: Mapping[str, Any], *, max_items: int = 8) -> str:
    values, names = _public_inputs(export)
    pairs = [f"{name}={_short_decimal(value, max_chars=50)}" for name, value in zip(names, values)]
    bindings = _get(export, "ccs", "public_bindings", default=[]) or []
    constant_pairs: list[str] = []
    if isinstance(bindings, list):
        for binding in bindings:
            if not isinstance(binding, Mapping):
                continue
            if binding.get("binding_kind") == "relation_constant":
                name = str(binding.get("name", "claim"))
                value = binding.get("value", "?")
                constant_pairs.append(f"{name}={_short_decimal(value, max_chars=50)}")
    if len(pairs) > max_items:
        pairs = pairs[:max_items] + [f"... ({len(values)} public inputs total)"]
    summary_parts = []
    if pairs:
        summary_parts.append(", ".join(pairs))
    if constant_pairs:
        shown = constant_pairs[:max_items]
        if len(constant_pairs) > max_items:
            shown.append(f"... ({len(constant_pairs)} relation constants total)")
        summary_parts.append("relation constants: " + ", ".join(shown))
    return "; ".join(summary_parts) if summary_parts else "none recorded"


def _witness_rows(export: Mapping[str, Any]) -> list[list[Any]] | None:
    rows = _get(export, "zkfol", "witness_rows", default=None)
    if isinstance(rows, list) and all(isinstance(row, list) for row in rows):
        return rows
    return None


def _preview_rows(export: Mapping[str, Any]) -> tuple[list[list[Any]], list[list[Any]]] | None:
    preview = _get(export, "zkfol", "witness_rows_preview", default=None)
    if not isinstance(preview, Mapping):
        return None
    first = preview.get("first_columns")
    last = preview.get("last_columns")
    if isinstance(first, list) and isinstance(last, list):
        if all(isinstance(row, list) for row in first) and all(isinstance(row, list) for row in last):
            return first, last
    return None


def row_labels(export: Mapping[str, Any]) -> list[str]:
    name = str(export.get("name", ""))
    if name.startswith("standard_power"):
        return ["C1 base", "C2 exponent", "C3 output", "C4 previous-column pointer"]
    if name.startswith("efficient_power"):
        return ["C1 base", "C2 exponent", "C3 output", "C4 floor-half pointer"]
    if name.startswith("factorial"):
        return ["C1 n", "C2 n!", "C3 previous-column pointer"]
    if name.startswith("fibonacci_exact") or name.startswith("fibonacci"):
        return ["C1 n", "C2 fib(n)", "C3 pointer to n-1", "C4 pointer to n-2"]
    if name.startswith("sk"):
        return [
            "C1 input term",
            "C2 output term",
            "C3 S/K aux 1",
            "C4 S/K aux 2",
            "C5 S/K aux 3",
            "C6 subreduction pointer 1",
            "C7 subreduction pointer 2",
            "C8 derivation height",
        ]
    arity = int(_get(export, "dimensions", "arity", default=0) or 0)
    return [f"C{i}" for i in range(1, arity + 1)]


def _selected_columns(n: int, *, head: int, tail: int, full: bool) -> list[int | None]:
    if n <= 0:
        return []
    if full or n <= max(0, head) + max(0, tail) + 1:
        return list(range(n))
    first = list(range(min(max(0, head), n)))
    start_tail = max(len(first), n - max(0, tail))
    last = list(range(start_tail, n))
    return [*first, None, *last]


def _format_table(headers: Sequence[str], rows: Sequence[Sequence[str]]) -> list[str]:
    widths = [len(h) for h in headers]
    for row in rows:
        for i, cell in enumerate(row):
            widths[i] = max(widths[i], len(cell))
    fmt = "  ".join("{:<" + str(w) + "}" for w in widths)
    out = [fmt.format(*headers)]
    out.append(fmt.format(*(('-' * w) for w in widths)))
    out.extend(fmt.format(*row) for row in rows)
    return out


def format_witness_matrix(
    export: Mapping[str, Any],
    *,
    head: int = 8,
    tail: int = 4,
    full: bool = False,
    max_cell_chars: int = 36,
) -> str:
    """Return an abbreviated display of the finite FOL witness matrix C."""
    dims = export.get("dimensions", {}) if isinstance(export.get("dimensions"), Mapping) else {}
    arity = int(dims.get("arity", 0) or 0)
    length = int(dims.get("length", 0) or 0)
    labels = row_labels(export)
    rows = _witness_rows(export)

    lines: list[str] = []
    lines.append("FOL witness matrix C")
    lines.append("--------------------")
    lines.append(
        f"C is the finite matrix interpretation used by the FOL predicate: "
        f"arity={arity or 'unknown'}, length={length or 'unknown'}."
    )
    convention = _get(export, "zkfol", "witness_convention", default=None)
    if convention:
        lines.append(f"Row convention: {convention}")

    if rows is None:
        preview = _preview_rows(export)
        if preview is None:
            lines.append("No witness rows are embedded in this JSON. Re-export with a witness-row option if available.")
            return "\n".join(lines)
        first, last = preview
        lines.append("Only a first/last preview is embedded in this JSON.")
        if first:
            first_count = len(first[0]) if first and first[0] else 0
            show_first = first_count if full else min(max(0, head), first_count)
            first_display = [row[:show_first] for row in first]
            lines.append("")
            lines.append(f"First {show_first} columns" + (f" (of embedded first {first_count})" if show_first != first_count else "") + ":")
            headers = ["row", *[str(i) for i in range(1, show_first + 1)]]
            table_rows = []
            for i, row in enumerate(first_display):
                label = labels[i] if i < len(labels) else f"C{i+1}"
                table_rows.append([label, *[_short_text(v, max_chars=max_cell_chars) for v in row]])
            lines.extend(_format_table(headers, table_rows))
        if last:
            last_count = len(last[0]) if last and last[0] else 0
            show_last = last_count if full else min(max(0, tail), last_count)
            last_display = [row[-show_last:] if show_last else [] for row in last]
            start = max(1, length - show_last + 1) if length else 1
            lines.append("")
            lines.append(f"Last {show_last} columns" + (f" (of embedded last {last_count})" if show_last != last_count else "") + ":")
            headers = ["row", *[str(i) for i in range(start, start + show_last)]]
            table_rows = []
            for i, row in enumerate(last_display):
                label = labels[i] if i < len(labels) else f"C{i+1}"
                table_rows.append([label, *[_short_text(v, max_chars=max_cell_chars) for v in row]])
            lines.extend(_format_table(headers, table_rows))
        return "\n".join(lines)

    if not rows:
        lines.append("The embedded witness matrix has no rows.")
        return "\n".join(lines)

    n = len(rows[0]) if rows and isinstance(rows[0], list) else 0
    selected = _selected_columns(n, head=head, tail=tail, full=full)
    headers = ["row"]
    for idx in selected:
        headers.append("..." if idx is None else str(idx + 1))
    table_rows: list[list[str]] = []
    for i, row in enumerate(rows):
        label = labels[i] if i < len(labels) else f"C{i+1}"
        cells: list[str] = [label]
        for idx in selected:
            cells.append("..." if idx is None else _short_text(row[idx], max_chars=max_cell_chars))
        table_rows.append(cells)
    lines.append("")
    lines.extend(_format_table(headers, table_rows))
    if None in selected:
        lines.append(f"Shown: first {head} and last {tail} of {n} columns. Use --full-matrix to print all columns.")
    return "\n".join(lines)


def _lincomb_preview(terms: Iterable[Any], *, head: int = 5, tail: int = 2, max_coeff_chars: int = 28) -> str:
    parsed: list[tuple[int, str]] = []
    for term in terms or []:
        if isinstance(term, (list, tuple)) and len(term) == 2:
            parsed.append((int(term[0]), str(term[1])))
    if not parsed:
        return "0"
    if len(parsed) <= head + tail + 1:
        shown: list[tuple[int, str] | None] = parsed
    else:
        shown = [*parsed[:head], None, *parsed[-tail:]]
    parts = []
    for item in shown:
        if item is None:
            parts.append(f"... ({len(parsed)} terms)")
            continue
        index, coeff = item
        parts.append(f"{_short_text(coeff, max_chars=max_coeff_chars)}*z[{index}]")
    return " + ".join(parts)


def _selected_constraints(n: int, *, head: int, tail: int, full: bool) -> list[int | None]:
    return _selected_columns(n, head=head, tail=tail, full=full)


def format_constraint_preview(
    export: Mapping[str, Any],
    *,
    head: int = 4,
    tail: int = 4,
    full: bool = False,
) -> str:
    """Return an abbreviated display of the exported R1CS/CCS rows."""
    constraints = list(_get(export, "ccs", "constraints", default=[]) or [])
    dims = export.get("dimensions", {}) if isinstance(export.get("dimensions"), Mapping) else {}
    lines: list[str] = []
    lines.append("CCS/R1CS constraint preview")
    lines.append("---------------------------")
    lines.append(
        "Each row is <A,z> * <B,z> = <C,z>. "
        f"Unpadded rows={len(constraints)}, z_len={dims.get('z_len', 'unknown')}."
    )
    if not constraints:
        lines.append("No constraints are embedded in this JSON.")
        return "\n".join(lines)
    selected = _selected_constraints(len(constraints), head=head, tail=tail, full=full)
    for idx in selected:
        if idx is None:
            omitted = max(0, len(constraints) - head - tail)
            lines.append(f"... omitted {omitted} middle constraints ...")
            continue
        row = constraints[idx]
        if not isinstance(row, Mapping):
            lines.append(f"#{idx}: <malformed row>")
            continue
        label = row.get("label", "<unlabelled>")
        lines.append(f"#{idx:04d}  {label}")
        lines.append(f"  A: {_lincomb_preview(row.get('a', []))}")
        lines.append(f"  B: {_lincomb_preview(row.get('b', []))}")
        lines.append(f"  C: {_lincomb_preview(row.get('c', []))}")
    if None in selected:
        lines.append(f"Shown: first {head} and last {tail} of {len(constraints)} constraints. Use --full-constraints to print all rows.")
    return "\n".join(lines)


def _has_public_final(export: Mapping[str, Any]) -> bool:
    if bool(_get(export, "benchmark_claim", "public_final", default=False)):
        return True
    bindings = _get(export, "ccs", "public_bindings", default=[])
    return isinstance(bindings, list) and len(bindings) > 0


def _final_from_rows(rows: list[list[Any]] | None, row: int) -> Any | None:
    if rows is None or len(rows) < row or not rows[row - 1]:
        return None
    return rows[row - 1][-1]


def concrete_statement_lines(export: Mapping[str, Any]) -> list[str]:
    """Explain the concrete computation/claim represented by an export."""
    name = str(export.get("name", "<unknown>"))
    rows = _witness_rows(export)
    dims = export.get("dimensions", {}) if isinstance(export.get("dimensions"), Mapping) else {}
    length = dims.get("length", "unknown")
    public_final = _has_public_final(export)
    lines: list[str] = []

    if name.startswith("standard_power") or name.startswith("efficient_power"):
        base = _final_from_rows(rows, 1)
        exponent = _final_from_rows(rows, 2)
        output = _final_from_rows(rows, 3)
        flavour = "standard recursive power" if name.startswith("standard_power") else "repeated-squaring power"
        if base is not None and exponent is not None and output is not None:
            lines.append(f"Concrete computation: exact integer {base}^{exponent} = {output}.")
        else:
            lines.append(f"Concrete computation: {flavour} witness table with {length} columns.")
        lines.append(f"FOL meaning: a {flavour} recurrence is valid for every column x=1..{length}.")
        if public_final:
            lines.append("Public claim: the final base/exponent/output cells are bound as public inputs.")
        else:
            lines.append("Public claim: not bound; this proves existence of a private valid power table. Use --public-final to expose the final claim.")
        return lines

    if name.startswith("factorial"):
        n = _final_from_rows(rows, 1)
        output = _final_from_rows(rows, 2)
        if n is not None and output is not None:
            lines.append(f"Concrete computation: exact integer {n}! = {output}.")
        else:
            lines.append(f"Concrete computation: factorial witness table with {length} columns.")
        lines.append(f"FOL meaning: the factorial recurrence is valid for every column x=1..{length}.")
        lines.append("Public claim: final n/output cells are public only when exported with --public-final.")
        return lines

    if name.startswith("fibonacci_exact"):
        exact = _get(export, "exact_arithmetic", default={})
        n = exact.get("n") if isinstance(exact, Mapping) else None
        preview = exact.get("output_decimal_preview") if isinstance(exact, Mapping) else None
        bits = exact.get("output_bit_length") if isinstance(exact, Mapping) else None
        if n is not None and preview is not None:
            lines.append(f"Concrete computation: exact non-modular Fibonacci F_{n} = {preview}.")
        else:
            lines.append("Concrete computation: exact non-modular Fibonacci trace.")
        if bits is not None:
            lines.append(f"Output size: {bits} bits; no modulo 2^64 reduction is used.")
        lines.append("Public claim: n and the exact Fibonacci output are public relation constants in the JSON relation.")
        return lines

    if name.startswith("fibonacci"):
        n = _final_from_rows(rows, 1)
        output = _final_from_rows(rows, 2)
        if n is not None and output is not None:
            lines.append(f"Concrete computation: exact integer Fibonacci F_{n} = {output}, with F_1=F_2=1.")
        else:
            lines.append(f"Concrete computation: Fibonacci witness table with {length} columns.")
        lines.append(f"FOL meaning: the Fibonacci recurrence and pointer rows are valid for every column x=1..{length}.")
        if public_final:
            lines.append("Public claim: the final n/output cells are bound as public inputs.")
        else:
            lines.append("Public claim: not bound; this proves existence of a private valid Fibonacci table. Use --public-final to expose the final claim.")
        return lines

    if name.startswith("sk"):
        inp = _final_from_rows(rows, 1)
        out = _final_from_rows(rows, 2)
        if inp is not None and out is not None:
            lines.append(f"Concrete computation: a valid SK-combinator reduction row ending with encoded input {inp} and output {out}.")
        else:
            lines.append("Concrete computation: valid SK-combinator reduction witness table.")
        lines.append(f"FOL meaning: every row satisfies one of the SK reduction/identity/parallel/transitive cases over x=1..{length}.")
        return lines

    lines.append(f"Concrete computation: {export.get('description', name)}")
    lines.append(f"FOL meaning: the exported finite witness matrix is checked for every column x=1..{length}.")
    return lines


def format_concrete_statement(export: Mapping[str, Any], *, emphasize: bool | None = None) -> str:
    lines = ["Concrete computation / public claim", "-----------------------------------"]
    lines.extend(emphasize_concrete_line(line, enabled=emphasize) for line in concrete_statement_lines(export))
    public = public_input_summary(export)
    if public:
        lines.append(f"Public inputs: {public}")
    return "\n".join(lines)



def format_zinc_constraint_shape(export: Mapping[str, Any]) -> str:
    """Return the practical variables/degree/bit-bound summary."""
    summary = compute_constraint_summary(export)
    representation = export.get("representation") or export.get("zkfol", {}).get("representation")
    lines = [
        "Zinc constraint shape",
        "---------------------",
        f"Target use case:             {summary['target_use_case']}",
        "Headline:                   " + format_constraint_summary(export),
    ]
    if representation:
        stats = export.get("stats", {}) if isinstance(export.get("stats"), Mapping) else {}
        row_types = export.get("zkfol", {}).get("row_types") if isinstance(export.get("zkfol"), Mapping) else None
        detail = f"Cell representation:         {representation}"
        if representation == "typed":
            ptr = sorted(int(r) for r, t in (row_types or {}).items() if t == "ptr")
            detail += (
                f" (num cells = integers, ptr rows {ptr} use one-hot range selectors; "
                f"{stats.get('value_wires', 0)} value wires, {stats.get('composed_value_wires', 0)} composed-value wires, "
                f"{stats.get('selector_wires', 0)} selector wires, {stats.get('b_wires', 0)} bit wires)"
            )
        elif representation == "bitwise":
            detail += f" (uniform b2int over {stats.get('b_wires', 0)} B-bit wires plus {stats.get('selector_wires', 0)} selector wires)"
        lines.append(detail)
    lines += [
        f"Scalar variables before padding: {summary['scalar_variables_unpadded']} = {summary['public_input_variables']} public + 1 constant-one + {summary['private_witness_variables']} private",
        f"Constraints before padding:  {summary['constraints_unpadded']}",
        f"Declared CCS/R1CS degree:    {summary['ccs_declared_degree']} (<A,z>*<B,z>=<C,z>)",
        f"Simplified witness degree:   at most {summary['max_simplified_degree_over_private_witness']} after fixing public inputs/one",
        f"Bit-bound delta:             {summary['bit_bound_delta']} bits",
        f"  witness value bits:        {summary['max_witness_value_bit_length']}",
        f"  coefficient bits:          {summary['max_constraint_coefficient_bit_length']}",
        f"  public input bits:         {summary['max_public_input_bit_length']}",
    ]
    return "\n".join(lines)


def format_inspection(
    export: Mapping[str, Any],
    *,
    path: Path | str | None = None,
    matrix: bool = True,
    constraints: bool = False,
    matrix_head: int = 8,
    matrix_tail: int = 4,
    constraint_head: int = 4,
    constraint_tail: int = 4,
    full_matrix: bool = False,
    full_constraints: bool = False,
) -> str:
    lines: list[str] = []
    title = "FOL-Zinc inspection"
    lines.append(title)
    lines.append("=" * len(title))
    if path is not None:
        lines.append(f"File: {path}")
    lines.append(f"Example: {export.get('name', '<unknown>')}")
    lines.append("")
    lines.append(format_concrete_statement(export))
    lines.append("")
    lines.append(format_zinc_constraint_shape(export))
    if matrix:
        lines.append("")
        lines.append(format_witness_matrix(export, head=matrix_head, tail=matrix_tail, full=full_matrix))
    if constraints:
        lines.append("")
        lines.append(format_constraint_preview(export, head=constraint_head, tail=constraint_tail, full=full_constraints))
    return "\n".join(lines)


def format_next_steps(json_path: Path | str, *, include_zinc_hint: bool = True) -> str:
    path = str(json_path)
    lines = ["What to try next", "----------------"]
    if include_zinc_hint:
        lines.append(f"Run or re-run Zinc on this same file: ./zkfol_zinc_adapter/folzinc run --input {path} --repeat 3")
    lines.append(f"Show the witness matrix again:       ./zkfol_zinc_adapter/folzinc inspect {path} --matrix")
    lines.append(f"Show CCS constraint rows too:        ./zkfol_zinc_adapter/folzinc inspect {path} --constraints")
    lines.append("Try a public 2^32 benchmark:         ./zkfol_zinc_adapter/folzinc bench power --skip-256 --run --repeat 3")
    lines.append("Try exact Fibonacci F_100:           ./zkfol_zinc_adapter/folzinc bench fib --n 100 --run --repeat 3")
    lines.append("Long run with slower heartbeat:      ./zkfol_zinc_adapter/folzinc bench fib --n 10000 --run --repeat 3 --int-limbs 128 --progress-interval 30")
    lines.append("List commands and options:           ./zkfol_zinc_adapter/folzinc help")
    lines.append("Read the short command guide:         zkfol_zinc_adapter/docs/COMMAND_REFERENCE.md")
    return "\n".join(lines)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="zkfol-zinc-inspect",
        description="Inspect exported zkFOL -> Zinc JSON: concrete claim, witness matrix, and optional CCS rows.",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument("paths", nargs="+", type=Path, help="exported JSON file(s)")
    parser.add_argument("--matrix", action=argparse.BooleanOptionalAction, default=True, help="show the finite FOL witness matrix C")
    parser.add_argument("--constraints", action="store_true", help="also show an abbreviated preview of CCS/R1CS rows")
    parser.add_argument("--matrix-head", type=int, default=8, help="number of first matrix columns to show")
    parser.add_argument("--matrix-tail", type=int, default=4, help="number of last matrix columns to show")
    parser.add_argument("--constraint-head", type=int, default=4, help="number of first constraints to show")
    parser.add_argument("--constraint-tail", type=int, default=4, help="number of last constraints to show")
    parser.add_argument("--full-matrix", action="store_true", help="print every witness-matrix column")
    parser.add_argument("--full-constraints", action="store_true", help="print every CCS/R1CS row; can be very large")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    for i, path in enumerate(args.paths):
        if i:
            print("\n" + "-" * 80 + "\n")
        export = load_export(path)
        print(
            format_inspection(
                export,
                path=path,
                matrix=args.matrix,
                constraints=args.constraints,
                matrix_head=args.matrix_head,
                matrix_tail=args.matrix_tail,
                constraint_head=args.constraint_head,
                constraint_tail=args.constraint_tail,
                full_matrix=args.full_matrix,
                full_constraints=args.full_constraints,
            )
        )
    return 0


if __name__ == "__main__":  # pragma: no cover
    raise SystemExit(main())
