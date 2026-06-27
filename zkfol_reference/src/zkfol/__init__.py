"""zkFOL reference implementation.

This package implements a typed subset of the arithmetisation pipeline from the
zkFOL paper:

    FOL formula -> enriched polynomial semantics -> mkQ polynomials -> beta

Public symbols are loaded lazily. This preserves convenient imports such as
``from zkfol import cell, mkq`` while keeping command-line help and source-tree
runners lightweight.

For a reader-facing map from paper definitions to modules, see the root-level
``PAPER_GUIDE.md`` in the source distribution.
"""

from __future__ import annotations

from importlib import import_module
from typing import Any

__version__ = "0.1.3"

_EXPORT_MODULES = {
    # ast
    "Add": "zkfol.ast",
    "And": "zkfol.ast",
    "Const": "zkfol.ast",
    "Eq": "zkfol.ast",
    "Formula": "zkfol.ast",
    "Index": "zkfol.ast",
    "Len": "zkfol.ast",
    "MatrixCell": "zkfol.ast",
    "Mul": "zkfol.ast",
    "Or": "zkfol.ast",
    "Term": "zkfol.ast",
    "X": "zkfol.ast",
    "cell": "zkfol.ast",
    "conj": "zkfol.ast",
    "const": "zkfol.ast",
    "disj": "zkfol.ast",
    "falsehood": "zkfol.ast",
    "truth": "zkfol.ast",
    # bits
    "b2int": "zkfol.bits",
    "bits_lsb_first": "zkfol.bits",
    "max_bit_length": "zkfol.bits",
    # compiler
    "BIndex": "zkfol.compiler",
    "CompilationContext": "zkfol.compiler",
    "CompiledPolynomial": "zkfol.compiler",
    "beta": "zkfol.compiler",
    "mkq": "zkfol.compiler",
    "to_enriched_polynomial": "zkfol.compiler",
    # fast beta
    "beta_all_fast": "zkfol.fast_beta",
    "beta_formula_fast": "zkfol.fast_beta",
    "beta_term_fast": "zkfol.fast_beta",
    # examples
    "ExampleSpec": "zkfol.examples",
    "efficient_power_example": "zkfol.examples",
    "efficient_power_predicate": "zkfol.examples",
    "factorial_example": "zkfol.examples",
    "factorial_predicate": "zkfol.examples",
    "fibonacci_example": "zkfol.examples",
    "fibonacci_predicate": "zkfol.examples",
    "power_example": "zkfol.examples",
    "power_predicate": "zkfol.examples",
    # SK combinator example
    "K_COMBINATOR": "zkfol.sk",
    "S_COMBINATOR": "zkfol.sk",
    "sk_demo_columns": "zkfol.sk",
    "sk_example": "zkfol.sk",
    "sk_pair_int": "zkfol.sk",
    "sk_pair_term": "zkfol.sk",
    "sk_sred_source_int": "zkfol.sk",
    "sk_sred_target_int": "zkfol.sk",
    "sk_sred_incorrect_target_int": "zkfol.sk",
    "sk_sred_source_term": "zkfol.sk",
    "sk_sred_target_term": "zkfol.sk",
    "format_sk_witness_rows": "zkfol.sk",
    "pretty_sk_term": "zkfol.sk",
    "sk_unpair_int": "zkfol.sk",
    "sk_predicate": "zkfol.sk",
    "sk_witness": "zkfol.sk",

    # paper cross-references
    "GENERAL_PIPELINE_REFERENCE": "zkfol.paper",
    "POWER_REFERENCE": "zkfol.paper",
    "EFFICIENT_POWER_REFERENCE": "zkfol.paper",
    "FACTORIAL_REFERENCE": "zkfol.paper",
    "FIBONACCI_REFERENCE": "zkfol.paper",
    "SK_REFERENCE": "zkfol.paper",
    # witness
    "MatrixInterpretation": "zkfol.witness",
    "PointerRangeCheck": "zkfol.witness",
    # witnesses
    "efficient_power_witness": "zkfol.witnesses",
    "factorial_witness": "zkfol.witnesses",
    "fibonacci_witness": "zkfol.witnesses",
    "power_witness": "zkfol.witnesses",
}

__all__ = ["__version__", *sorted(_EXPORT_MODULES)]


def __getattr__(name: str) -> Any:
    try:
        module_name = _EXPORT_MODULES[name]
    except KeyError as exc:
        raise AttributeError(f"module 'zkfol' has no attribute {name!r}") from exc
    module = import_module(module_name)
    value = getattr(module, name)
    globals()[name] = value
    return value


def __dir__() -> list[str]:
    return sorted([*globals(), *__all__])
