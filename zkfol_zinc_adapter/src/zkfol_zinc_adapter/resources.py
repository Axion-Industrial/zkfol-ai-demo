"""Operational Zinc size, memory, and limb-profile preflight helpers.

The current public Zinc proof-of-concept can materialise dense verifier-side
objects after power-of-two padding.  It also samples a random prime field whose
size is determined by the chosen integer limb profile.  These helpers estimate
large allocations and keep high-level commands from accidentally requesting an
enormous random field for a tiny benchmark.
"""

from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any

DEFAULT_MAX_SINGLE_ALLOCATION_GIB = 128.0
INT_LIMB_CHOICES: tuple[int, ...] = (2, 4, 8, 16, 32, 64, 128)
FIELD_LIMBS_BY_INT: dict[int, int] = {2: 4, 4: 8, 8: 16, 16: 32, 32: 64, 64: 128, 128: 256}


@dataclass(frozen=True)
class ZincResourceEstimate:
    path: Path
    name: str
    case: str
    constraints: int
    witness_variables: int
    original_z_len: int
    runner_z_len: int
    estimated_padded_dim: int
    int_limbs: int
    field_limbs: int
    field_element_bytes_estimate: int
    random_field_bits: int
    largest_dense_allocation_bytes: int
    rough_peak_bytes: int
    public_inputs_original: int
    public_inputs_runner: int

    @property
    def largest_dense_allocation_gib(self) -> float:
        return self.largest_dense_allocation_bytes / float(1 << 30)

    @property
    def rough_peak_gib(self) -> float:
        return self.rough_peak_bytes / float(1 << 30)


def _load_json(path: Path) -> dict[str, Any]:
    with Path(path).open("r", encoding="utf-8") as f:
        return json.load(f)


def _next_power_of_two(value: int) -> int:
    value = max(1, int(value))
    return 1 << (value - 1).bit_length()


def max_abs_value_bit_length(export: dict[str, Any]) -> int:
    """Return the largest recorded integer bit length for an export.

    Older JSON files may omit the stats block.  In that case keep the original
    conservative fallback used by the runner, which selects Int<2>.
    """
    return int(export.get("stats", {}).get("max_abs_value_bit_length") or 120)


def minimum_int_limbs_for_bits(max_bits: int) -> int:
    """Smallest supported Zinc Int<N> profile with a little signed margin."""
    max_bits = int(max_bits)
    for limbs in INT_LIMB_CHOICES:
        if max_bits + 2 < 64 * limbs:
            return limbs
    raise ValueError(
        f"largest integer bit length {max_bits} is too large for built-in limb profiles; "
        "use a smaller example or extend the Rust runner"
    )


def minimum_int_limbs_for_export(export: dict[str, Any]) -> int:
    """Smallest supported Int<N> profile that fits an already-loaded export."""
    return minimum_int_limbs_for_bits(max_abs_value_bit_length(export))


def minimum_int_limbs_for_path(path: Path | str) -> int:
    """Smallest supported Int<N> profile that fits the export at ``path``."""
    return minimum_int_limbs_for_export(_load_json(Path(path)))


def _parse_requested_int_limbs(requested: str | int | None) -> int | None:
    if requested in (None, "", "auto"):
        return None
    limbs = int(requested)
    if limbs not in INT_LIMB_CHOICES:
        raise ValueError(f"unsupported limb profile {requested}; expected auto or one of {INT_LIMB_CHOICES}")
    return limbs


def _choose_int_limbs(export: dict[str, Any], requested: str | int | None = None) -> int:
    parsed = _parse_requested_int_limbs(requested)
    if parsed is not None:
        return parsed
    return minimum_int_limbs_for_export(export)


def _field_limbs_for_int_limbs(int_limbs: int) -> int:
    return FIELD_LIMBS_BY_INT[int(int_limbs)]


def normalize_int_limb_request(
    path: Path | str,
    requested: str | int | None,
    *,
    strict: bool = False,
) -> tuple[int | None, str | None]:
    """Return the limb argument that should be passed to the runner.

    High-level commands treat an oversized ``--int-limbs`` as a maximum rather
    than as an exact request.  This prevents tiny instances such as ``F_3`` from
    accidentally asking Zinc to sample a very large random field.  Power users
    can recover exact old behaviour with ``--strict-int-limbs`` or the public
    ``folzinc`` alias ``--force-int-limbs``.

    The returned integer is suitable for ``--int-limbs``.  ``None`` means leave
    the runner in auto mode.
    """
    parsed = _parse_requested_int_limbs(requested)
    if parsed is None:
        return None, None
    export = _load_json(Path(path))
    needed = minimum_int_limbs_for_export(export)
    max_bits = max_abs_value_bit_length(export)
    if parsed < needed:
        raise ValueError(
            f"requested Int<{parsed}> is too small for {Path(path).name}: largest integer bit length is {max_bits}, "
            f"so the smallest supported profile is Int<{needed}>"
        )
    if parsed > needed and not strict:
        requested_field = _field_limbs_for_int_limbs(parsed)
        needed_field = _field_limbs_for_int_limbs(needed)
        return needed, (
            f"requested Int<{parsed}>/RandomField<{requested_field}> but this relation needs only "
            f"Int<{needed}>/RandomField<{needed_field}> (largest integer bit length {max_bits}); "
            f"using Int<{needed}> to avoid unnecessary large-prime sampling. "
            "Use --force-int-limbs/--strict-int-limbs to force the larger profile."
        )
    if parsed > needed and strict:
        requested_field = _field_limbs_for_int_limbs(parsed)
        return parsed, (
            f"using oversized Int<{parsed}>/RandomField<{requested_field}> exactly as requested although "
            f"this relation needs only Int<{needed}> (largest integer bit length {max_bits}). "
            "Large random-field prime sampling may dominate runtime."
        )
    return parsed, None


def normalise_int_limb_request(
    path: Path | str,
    requested: str | int | None,
    *,
    force: bool = False,
) -> tuple[int | None, list[str]]:
    """British-spelling compatibility wrapper for :func:`normalize_int_limb_request`."""
    effective, note = normalize_int_limb_request(path, requested, strict=force)
    return effective, ([note] if note else [])


def _field_element_bytes_estimate(field_limbs: int) -> int:
    # In the observed standard-power failure, RandomField<4> asked the allocator
    # for exactly padded_dim^2 * 48 bytes. Use that as the calibrated base and
    # scale by limb count for wider random-field profiles.
    return 12 * int(field_limbs)


def estimate_zinc_resources(
    path: Path | str,
    *,
    int_limbs: str | int | None = None,
    field_limbs: str | int | None = None,
) -> ZincResourceEstimate:
    """field_limbs None/"auto" keeps the legacy F = 2N pairing; 4 matches the
    runner's --field-limbs 4 decoupled profile."""
    path = Path(path)
    export = _load_json(path)
    dims = export.get("dimensions", {})
    ccs = export.get("ccs", {})
    constraints = int(dims.get("constraints") or len(ccs.get("constraints", [])) or 0)
    witness_variables = int(dims.get("witness_variables") or len(ccs.get("witness", [])) or 0)
    public_inputs_original = len(ccs.get("public_inputs", []))
    original_z_len = int(dims.get("z_len") or (public_inputs_original + 1 + witness_variables))

    # The runner normalises multi-public-input files by keeping public_zero and
    # embedding remaining public claims as public relation constants. Match that
    # for the preflight size.
    public_inputs_runner = 1 if public_inputs_original > 1 else public_inputs_original
    runner_z_len = public_inputs_runner + 1 + witness_variables
    padded_dim = _next_power_of_two(max(constraints, runner_z_len))
    selected_int_limbs = _choose_int_limbs(export, int_limbs)
    if field_limbs in (None, "auto"):
        selected_field_limbs = _field_limbs_for_int_limbs(selected_int_limbs)
    else:
        selected_field_limbs = int(field_limbs)
    random_field_bits = 64 * selected_field_limbs
    field_element_bytes = _field_element_bytes_estimate(selected_field_limbs)
    largest_dense = padded_dim * padded_dim * field_element_bytes
    rough_peak = 2 * largest_dense
    name = str(export.get("name") or path.stem)
    case = str(export.get("benchmark_case", {}).get("stem") or name)
    return ZincResourceEstimate(
        path=path,
        name=name,
        case=case,
        constraints=constraints,
        witness_variables=witness_variables,
        original_z_len=original_z_len,
        runner_z_len=runner_z_len,
        estimated_padded_dim=padded_dim,
        int_limbs=selected_int_limbs,
        field_limbs=selected_field_limbs,
        field_element_bytes_estimate=field_element_bytes,
        random_field_bits=random_field_bits,
        largest_dense_allocation_bytes=largest_dense,
        rough_peak_bytes=rough_peak,
        public_inputs_original=public_inputs_original,
        public_inputs_runner=public_inputs_runner,
    )


def would_skip_for_resources(
    estimate: ZincResourceEstimate,
    *,
    allow_large: bool,
    check_only: bool,
    max_single_allocation_gib: float = DEFAULT_MAX_SINGLE_ALLOCATION_GIB,
) -> tuple[bool, str | None]:
    if allow_large or check_only:
        return False, None
    if estimate.largest_dense_allocation_gib > float(max_single_allocation_gib):
        return True, (
            f"estimated largest dense Zinc allocation is {estimate.largest_dense_allocation_gib:.1f} GiB, "
            f"above the configured {float(max_single_allocation_gib):.1f} GiB cap"
        )
    return False, None


def format_bytes(num_bytes: int | float | None) -> str:
    if num_bytes is None:
        return "n/a"
    value = float(max(0.0, num_bytes))
    units = ["B", "KiB", "MiB", "GiB", "TiB"]
    unit = units[0]
    for unit in units:
        if value < 1024.0 or unit == units[-1]:
            break
        value /= 1024.0
    if unit == "B":
        return f"{int(value)} {unit}"
    return f"{value:.1f} {unit}"


def format_resource_estimate(estimate: ZincResourceEstimate) -> str:
    return (
        f"case={estimate.case} constraints={estimate.constraints:,} z={estimate.runner_z_len:,} "
        f"pad={estimate.estimated_padded_dim:,} Int<{estimate.int_limbs}>/RandomField<{estimate.field_limbs}> "
        f"field_bits={estimate.random_field_bits:,} "
        f"largest_dense={format_bytes(estimate.largest_dense_allocation_bytes)} "
        f"rough_peak={format_bytes(estimate.rough_peak_bytes)}"
    )


def skip_record(estimate: ZincResourceEstimate, reason: str | None) -> dict[str, Any]:
    return {
        "case": estimate.case,
        "name": estimate.name,
        "input_path": str(estimate.path),
        "mode": "skipped-by-resource-preflight" if reason else "resource-preflight",
        "skipped": bool(reason),
        "skip_reason": reason or "",
        "int_limbs": estimate.int_limbs,
        "field_limbs": estimate.field_limbs,
        "constraints_unpadded": estimate.constraints,
        "witness_variables": estimate.witness_variables,
        "z_len_unpadded": estimate.original_z_len,
        "runner_z_len_unpadded": estimate.runner_z_len,
        "ccs_m_padded": estimate.estimated_padded_dim,
        "ccs_n_padded": estimate.estimated_padded_dim,
        "estimated_padded_dim": estimate.estimated_padded_dim,
        "estimated_field_element_bytes": estimate.field_element_bytes_estimate,
        "estimated_random_field_bits": estimate.random_field_bits,
        "estimated_largest_dense_allocation_bytes": estimate.largest_dense_allocation_bytes,
        "estimated_largest_dense_allocation": format_bytes(estimate.largest_dense_allocation_bytes),
        "estimated_largest_dense_allocation_gib": estimate.largest_dense_allocation_gib,
        "estimated_rough_peak_bytes": estimate.rough_peak_bytes,
        "estimated_rough_peak": format_bytes(estimate.rough_peak_bytes),
        "estimated_rough_peak_gib": estimate.rough_peak_gib,
        "relation_check_ms": None,
        "prove_ms": None,
        "verify_ms": None,
        "field_setup_ms": None,
        "field_relation_check_ms": None,
        "zinc_prove_call_ms": None,
        "zinc_verify_call_ms": None,
        "measured_iteration_ms": None,
        "timing_note": "resource-preflight skip: no Zinc timing was measured",
        "proved": False,
    }
