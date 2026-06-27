from __future__ import annotations

import json
from pathlib import Path
from typing import Any

import pytest


@pytest.fixture
def package_root() -> Path:
    return Path(__file__).resolve().parents[1]


def write_export_json(path: Path, data: dict[str, Any]) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    return path


@pytest.fixture
def synthetic_export(tmp_path: Path):
    def _make(
        *,
        name: str = "synthetic",
        constraints: int = 8,
        witness_variables: int = 4,
        public_inputs: list[str] | None = None,
        max_bits: int = 64,
    ) -> Path:
        public_inputs = public_inputs if public_inputs is not None else ["0"]
        data = {
            "schema": "zkfol-zinc-ccs-v2",
            "name": name,
            "adapter_version": "test",
            "dimensions": {
                "constraints": constraints,
                "witness_variables": witness_variables,
                "z_len": len(public_inputs) + 1 + witness_variables,
                "public_inputs": len(public_inputs),
                "length": 1,
                "arity": 1,
                "max_bits": max_bits,
            },
            "stats": {"max_abs_value_bit_length": max_bits},
            "ccs": {
                "public_inputs": public_inputs,
                "public_input_names": ["public_zero"] + [f"public_{i}" for i in range(1, len(public_inputs))],
                "witness": ["0" for _ in range(witness_variables)],
                "constraints": [
                    {"a": [[1, "0"]], "b": [[1, "1"]], "c": [[0, "0"]], "label": f"row:{i}"}
                    for i in range(constraints)
                ],
            },
        }
        return write_export_json(tmp_path / f"{name}.json", data)

    return _make
