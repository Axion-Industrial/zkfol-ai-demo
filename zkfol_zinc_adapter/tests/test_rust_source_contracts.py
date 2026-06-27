from __future__ import annotations

import os
import shutil
import subprocess
from pathlib import Path

import pytest


def _main_rs(package_root: Path) -> str:
    return (package_root / "rust" / "zkfol-zinc-runner" / "src" / "main.rs").read_text(encoding="utf-8")


def test_rust_runner_preserves_signed_sparse_matrix_path(package_root):
    text = _main_rs(package_root)
    assert "sparse_matrix::SparseMatrix" in text
    assert "sparse_matrix_from_constraints" in text
    assert "to_Z_matrix" not in text
    assert "BigInt" in text


def test_rust_runner_uses_concrete_zinc_dispatch_not_generic_const_proof_path(package_root):
    text = _main_rs(package_root)
    assert "define_execute_zinc!(execute_zinc_2, 2, 4);" in text
    assert "define_execute_zinc!(execute_zinc_128, 128, 256);" in text
    assert "fn execute<const N" not in text
    assert "ZincProver::<RandomFieldZipTypes<N>" not in text
    assert "ZincVerifier::<RandomFieldZipTypes<N>" not in text


def test_rust_runner_checks_sampled_field_relation_before_proving(package_root):
    text = _main_rs(package_root)
    field_idx = text.index("field_relation_check")
    prove_idx = text.index('"prove"')
    assert field_idx < prove_idx
    assert "prepare_for_random_field_piop" in text
    assert "check_relation(&statement_field.constraints" in text


def test_rust_runner_exposes_progress_and_resource_preflight_flags(package_root):
    text = _main_rs(package_root)
    for needle in (
        "--progress",
        "--no-progress",
        "--allow-large",
        "--max-single-allocation-gib",
        "FOLZINC_PROGRESS",
        "estimated_dense_allocation_bytes",
    ):
        assert needle in text


def test_rust_manifest_pins_runner_version_to_package(package_root):
    import re
    pyproject = (package_root / "pyproject.toml").read_text(encoding="utf-8")
    cargo = (package_root / "rust" / "zkfol-zinc-runner" / "Cargo.toml").read_text(encoding="utf-8")
    expected = re.search(r'^version = "([^"]+)"', pyproject, re.MULTILINE).group(1)
    assert f'version = "{expected}"' in cargo
    assert 'rust-version = "1.85"' in cargo
    assert 'rev = "0c9ed214"' in cargo


def test_rust_runner_reports_constraint_shape(package_root):
    text = _main_rs(package_root)
    for needle in (
        "ConstraintShape",
        "scalar_variables_unpadded",
        "ccs_declared_degree",
        "max_simplified_degree_over_private_witness",
        "bit_bound_delta",
        "Zinc constraint shape for this target",
    ):
        assert needle in text


@pytest.mark.skipif(os.environ.get("FOLZINC_RUN_CARGO_TESTS") != "1", reason="set FOLZINC_RUN_CARGO_TESTS=1 to run Cargo build regression")
def test_cargo_builds_runner_when_requested(package_root):
    cargo = shutil.which("cargo")
    assert cargo is not None, "cargo is required when FOLZINC_RUN_CARGO_TESTS=1"
    manifest = package_root / "rust" / "zkfol-zinc-runner" / "Cargo.toml"
    subprocess.run([cargo, "build", "--release", "--manifest-path", str(manifest)], check=True, timeout=600)


@pytest.mark.skipif(os.environ.get("FOLZINC_RUN_ZINC_SMOKE") != "1", reason="set FOLZINC_RUN_ZINC_SMOKE=1 to run a real Zinc proof smoke test")
def test_real_zinc_power_smoke_when_requested(package_root, tmp_path):
    cargo = shutil.which("cargo")
    assert cargo is not None, "cargo is required when FOLZINC_RUN_ZINC_SMOKE=1"
    from zkfol.cli import ExampleInputs, select_examples
    from zkfol_zinc_adapter.r1cs import build_ccs_export
    import json

    manifest = package_root / "rust" / "zkfol-zinc-runner" / "Cargo.toml"
    subprocess.run([cargo, "build", "--release", "--manifest-path", str(manifest)], check=True, timeout=600)
    export = build_ccs_export(select_examples("power", ExampleInputs(power_base=2, power_exponent=4))[0], public_final=True)
    input_path = tmp_path / "power_2_4.json"
    input_path.write_text(json.dumps(export), encoding="utf-8")
    binary = manifest.parent / "target" / "release" / "zkfol-zinc-runner"
    subprocess.run([str(binary), "--input", str(input_path), "--repeat", "1", "--json"], check=True, timeout=300)
