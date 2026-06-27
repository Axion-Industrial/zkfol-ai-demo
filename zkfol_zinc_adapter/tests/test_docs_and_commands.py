from __future__ import annotations

import ast
from pathlib import Path

from zkfol_zinc_adapter import cli


def test_readme_documents_single_command_tests_and_progress(package_root: Path):
    text = (package_root / "README.md").read_text(encoding="utf-8")
    assert "folzinc test" in text
    assert "--cargo" in text
    assert "RSS" in text or "memory" in text.lower()
    assert "compact" in text
    assert "exact" in text and "non-modular" in text
    assert "Variables, degree, and bit bound" in text
    assert "bit_bound_delta" in text


def test_command_reference_documents_regression_suite(package_root: Path):
    text = (package_root / "docs" / "COMMAND_REFERENCE.md").read_text(encoding="utf-8")
    assert "folzinc test" in text
    assert "--zinc-smoke" in text
    assert "FOLZINC_RUN_CARGO_TESTS" in text


def test_test_command_help_mentions_cargo_and_zinc_smoke():
    parser = cli.build_parser()
    assert "test" in parser.format_help()


def test_options_reference_documents_key_public_options(package_root: Path):
    text = (package_root / "docs" / "OPTIONS_REFERENCE.md").read_text(encoding="utf-8")
    for needle in [
        "--int-limbs",
        "--strict-int-limbs",
        "--force-int-limbs",
        "--progress-interval",
        "--max-single-allocation-gib",
        "--allow-large",
        "--power-profile",
        "--fib-profile",
        "--clean-output",
        "--include-witness-rows",
        "--zinc-smoke",
        "--install-dev",
        "--include-sympy",
        "--public-final",
        "--no-public-final",
        "--matrix-head",
        "--constraint-tail",
        "--cargo-run",
        "--runner",
        "--zkvm-csv",
        "--machine-json",
        "--allow-oversized-limbs",
        "bit_bound_delta",
        "scalar z variables",
        "FOLZINC_VENV",
        "FOLZINC_REFERENCE",
        "FOLZINC_PYTHON",
    ]:
        assert needle in text


def test_options_command_is_registered():
    parser = cli.build_parser()
    assert "options" in parser.format_help()


def test_public_python_cli_options_have_help_text(package_root: Path):
    for rel in [
        "src/zkfol_zinc_adapter/cli.py",
        "src/zkfol_zinc_adapter/bench.py",
        "src/zkfol_zinc_adapter/export.py",
        "src/zkfol_zinc_adapter/explain.py",
        "src/zkfol_zinc_adapter/check.py",
        "src/zkfol_zinc_adapter/view.py",
    ]:
        path = package_root / rel
        tree = ast.parse(path.read_text(encoding="utf-8"))
        missing: list[list[str]] = []
        for node in ast.walk(tree):
            if not (isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute) and node.func.attr == "add_argument"):
                continue
            opts = [
                arg.value
                for arg in node.args
                if isinstance(arg, ast.Constant) and isinstance(arg.value, str) and arg.value.startswith("--")
            ]
            if not opts or "--version" in opts:
                continue
            has_help = any(keyword.arg == "help" for keyword in node.keywords)
            if not has_help:
                missing.append(opts)
        assert missing == [], f"{path} has public options without help: {missing}"
