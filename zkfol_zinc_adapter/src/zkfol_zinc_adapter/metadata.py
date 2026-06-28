"""Explanatory metadata shared by the exporter, explanation CLI, and docs."""

from __future__ import annotations

from collections import Counter
from typing import Any, Iterable, Mapping

ADAPTER_VERSION = "0.6.0"

PIPELINE_STEPS = [
    {
        "stage": "FOL witness",
        "meaning": (
            "The reference implementation provides a finite matrix interpretation C. "
            "Rows encode the data of the example and columns are the quantified positions x."
        ),
    },
    {
        "stage": "Direct FOL semantics",
        "meaning": (
            "The predicate is evaluated directly over the witness matrix. In the paper's integer "
            "semantics, zero means true and a non-zero natural number means false."
        ),
    },
    {
        "stage": "<phi> and mkQ_x(<phi>)",
        "meaning": (
            "The FOL predicate phi is translated to an enriched polynomial <phi>, then each column x "
            "is translated to an integer multivariate polynomial mkQ_x(<phi>)."
        ),
    },
    {
        "stage": "beta_F evaluation",
        "meaning": (
            "The mkQ variables are instantiated from the witness. In the typed (num/ptr) representation a "
            "value symbol C_i(x) takes the integer entry directly, and a composed value C_i(C_j(x)) takes "
            "the entry pointed at after a range check; in the paper-faithful bitwise representation the "
            "same values are reconstructed from per-bit B variables."
        ),
    },
    {
        "stage": "Integer R1CS/CCS bridge",
        "meaning": (
            "This adapter materialises the mkQ/beta checks as signed integer R1CS rows. The typed route "
            "uses one integer wire per num cell, one-hot selectors that range-check each pointer cell, "
            "integer composed-cell lookups, and arithmetic gates; the bitwise route additionally expands "
            "every cell into boolean B bits. Both feed identical mkQ_x(<phi>) = 0 checks to Zinc."
        ),
    },
    {
        "stage": "Zinc prove/verify",
        "meaning": (
            "The Rust runner converts the exported R1CS rows to Zinc CCS_Z, checks the integer relation, "
            "then invokes Zinc's prover and verifier."
        ),
    },
]

FIELD_GLOSSARY = {
    "name": "The bundled FOL example that produced the exported instance.",
    "schema": "JSON schema tag. Version zkfol-zinc-ccs-v2 means signed integer R1CS/CCS rows with decimal-string coefficients for arbitrary-size integer benchmarks.",
    "description": "Short human description of the FOL example.",
    "dimensions.arity": "Number of rows in the FOL matrix variable C, also written ar(C).",
    "dimensions.length": "Number of columns in the finite witness matrix C, also written len(C). The FOL predicate is checked for every x in 1..len(C).",
    "dimensions.max_bits": "Bit width used for each matrix entry when creating the paper's B variables.",
    "dimensions.constraints": "Number of generated R1CS rows before Zinc pads to powers of two. This is a bridge-size benchmark, not the original FOL formula size.",
    "dimensions.witness_variables": "Number of private z-vector entries after expanding matrix bits, selectors, lookup products, and arithmetic intermediates.",
    "dimensions.public_inputs": "Number of public input coordinates before the constant-one coordinate. A default export has one public zero. Some benchmark claims are instead encoded as public relation constants in ccs.public_bindings for compatibility with the current Zinc proof-of-concept.",
    "dimensions.z_len": "Unpadded z length: public inputs || constant-one coordinate || private witness variables.",
    "stats.b_wires": "Number of private wires representing paper B variables. Zero in the typed (num/ptr) representation, which uses no bit decomposition.",
    "stats.bit_wires": "Number of wires constrained to be Boolean. In the bitwise representation this includes B wires and selector wires; in the typed representation it is just the one-hot selector wires.",
    "stats.selector_wires": "Number of one-hot selector wires used to prove private pointer values are in range.",
    "stats.value_wires": "Typed representation only: number of single-integer wires holding direct num cells C_i(x).",
    "stats.composed_value_wires": "Typed representation only: number of single-integer wires holding composed cells C_i(C_j(x)).",
    "representation": "Which cell encoding was used: 'typed' (num cells are integers, only pointers carry range machinery) or 'bitwise' (uniform b2int over B bits, the paper-faithful encoding).",
    "zkfol.representation": "Which cell encoding was used: 'typed' or 'bitwise'.",
    "zkfol.row_types": "Typed representation only: map from matrix row to its inferred type, 'num' (used only in arithmetic) or 'ptr' (used as a column pointer C_j and therefore range-checked).",
    "stats.max_abs_value_bit_length": "Largest absolute integer bit length appearing in the witness vector or constraint coefficients.",

    "zinc_constraint_summary.target_use_case": "Practical benchmark family for this export, such as compact exact-integer Fibonacci or efficient repeated-squaring power.",
    "zinc_constraint_summary.scalar_variables_unpadded": "Number of scalar z entries handed to CCS before padding: public inputs, the constant-one coordinate, and private witness variables.",
    "zinc_constraint_summary.private_witness_variables": "Number of private scalar witness entries in z.",
    "zinc_constraint_summary.public_input_variables": "Number of public input coordinates in z before the constant-one coordinate.",
    "zinc_constraint_summary.constraints_unpadded": "Number of R1CS/CCS rows before Zinc power-of-two padding.",
    "zinc_constraint_summary.ccs_declared_degree": "Declared CCS/R1CS degree. This adapter emits rows <A,z>*<B,z>=<C,z>, so this is 2.",
    "zinc_constraint_summary.max_simplified_degree_over_private_witness": "Maximum degree after fixing public inputs and the constant-one coordinate. Compact trace rows may simplify to degree 1 even though the CCS model is degree 2.",
    "zinc_constraint_summary.bit_bound_delta": "Largest absolute bit length among public inputs, private witness values, and integer constraint coefficients materialised by the adapter.",
    "zinc_constraint_summary.max_constraint_coefficient_bit_length": "Largest absolute bit length of any integer coefficient in the sparse A/B/C matrices.",
    "zinc_constraint_summary.max_witness_value_bit_length": "Largest absolute bit length of any private witness value.",
    "reference_report.direct_values": "Direct evaluation of the FOL predicate on each column x. All entries should be zero for a valid witness.",
    "reference_report.beta_values": "Evaluation of beta_F(mkQ_x(<phi>)) on each column x. It should match direct_values.",
    "reference_report.fast_beta_values": "Independent fast evaluator used as an implementation cross-check.",
    "reference_report.semantics_agree": "True means direct semantics, symbolic beta, and fast beta agree.",
    "reference_report.all_zero": "True means the compiled predicate is satisfied for every quantified x.",
    "reference_report.pointer_range_ok": "True means every pointer row used by the predicate points into 1..len(C).",
    "constraint_breakdown.mkq_arithmetic_gates": "R1CS multiplication rows introduced while evaluating mkQ_x(<phi>).",
    "constraint_breakdown.mkq_zero_checks": "Final zero checks for mkQ_x(<phi>) = 0, one per witness column x.",
    "constraint_breakdown.pointer_range_one_hot_checks": "One-hot checks showing a private pointer selects exactly one legal column.",
    "constraint_breakdown.pointer_range_value_checks": "Checks tying a pointer's integer value to the selected one-hot column.",
    "constraint_breakdown.pointer_lookup_selector_products": "Intermediate products selector * cell used to realise private lookups (selector * direct_bit in the bitwise route, selector * num value in the typed route).",
    "constraint_breakdown.pointer_lookup_bit_equalities": "Bitwise route: checks equating composed B bits with the selected direct B bits.",
    "constraint_breakdown.pointer_lookup_value_equalities": "Typed route: checks pinning each composed cell C_i(C_j(x)) to its selected integer value sum_k sel_k * C_i(k).",
    "constraint_breakdown.booleanity_bit_checks": "Boolean constraints v*(v-1)=0 for bit and selector wires.",
    "constraint_breakdown.public_input_binding_checks": "Checks binding selected witness entries to public benchmark claims, either through public input coordinates or through public relation constants.",
    "constraints_unpadded": "Number of exported R1CS/CCS rows before Zinc padding; this equals dimensions.constraints.",
    "witness_variables": "Number of private scalar entries in the exported R1CS witness vector.",
    "z_len_unpadded": "Unpadded z-vector length handed to Zinc before power-of-two padding.",
    "relation_check_ms": "Time spent by the Rust runner checking every integer R1CS/CCS row before calling Zinc.",
    "prove_ms": "Backward-compatible alias for zinc_prove_call_ms: average time spent inside the ZincProver::prove library call. It is not total prover-side elapsed time.",
    "verify_ms": "Backward-compatible alias for zinc_verify_call_ms: average time spent inside the ZincVerifier::verify library call. In the current Zinc proof-of-concept this can exceed the prover call.",
    "field_setup_ms": "Average time spent sampling/configuring Zinc's random field for each proof iteration.",
    "field_relation_check_ms": "Average time spent in the adapter's diagnostic check that the integer CCS also vanishes after mapping to the sampled field.",
    "zinc_prove_call_ms": "Average time spent inside ZincProver::prove. This excludes field setup, the local integer relation check, and the adapter's sampled-field relation precheck.",
    "zinc_verify_call_ms": "Average time spent inside ZincVerifier::verify. Current Zinc proof-of-concept verification materialises/checks some comparatively large field/PCS objects, so this can be larger than the prover call.",
    "measured_iteration_ms": "Average measured per-iteration total for sampled-field setup + sampled-field relation check + ZincProver::prove + ZincVerifier::verify.",
    "timing_note": "Human-readable caveat explaining how to interpret the timing fields.",
    "ccs_m_padded": "Constraint-row count after Zinc power-of-two padding.",
    "ccs_n_padded": "z-vector length after Zinc power-of-two padding.",
    "proved": "True means a Zinc proof was generated and verified for the exported CCS instance in this run.",
}

CONSTRAINT_BREAKDOWN_DESCRIPTIONS = {
    "mkq_arithmetic_gates": "arithmetic gates for mkQ_x(<phi>)",
    "mkq_zero_checks": "one zero-check per witness column",
    "pointer_range_one_hot_checks": "one-hot range checks for pointer rows",
    "pointer_range_value_checks": "pointer value equals selected column",
    "pointer_lookup_selector_products": "selector * cell lookup products",
    "pointer_lookup_bit_equalities": "composed-bit lookup equalities",
    "pointer_lookup_value_equalities": "composed-cell integer lookup equalities",
    "booleanity_bit_checks": "bit booleanity checks",
    "public_input_binding_checks": "witness entries bound to public claims",
    "direct_fibonacci_base_checks": "direct exact-integer Fibonacci base cases",
    "direct_fibonacci_step_checks": "direct exact-integer Fibonacci recurrence rows",
    "direct_fibonacci_pointer_checks": "direct exact-integer Fibonacci pointer-row checks",
    "other": "other constraints",
}

BENCHMARKING_NOTES = [
    "Compare runs using the same machine, Rust toolchain, Zinc commit, release/debug mode, and --repeat value.",
    "constraints_unpadded is usually the best size metric for this adapter; ccs_m_padded and ccs_n_padded explain the size actually handed to Zinc after padding.",

    "A run now reports the practical Zinc constraint shape: scalar variables, declared/simplified degree, and bit-bound delta. These are the headline values to quote for a target use case.",
    "zinc_prove_call_ms and zinc_verify_call_ms are timed library calls, not asymptotic estimates and not production cryptographic benchmarks. The legacy prove_ms/verify_ms fields are aliases for those calls.",
    "Verifier-call time can exceed prover-call time in the current Zinc proof-of-concept. Treat that as an implementation/measurement fact, not as a claim about optimized SNARK verifier complexity.",
    "This bridge is deliberately clear rather than minimal. A native AIR implementation should use fewer rows for pointer/range machinery.",
    "For comparisons with zkVMs, prefer public-final or benchmark exports so both systems prove the same public input/output claim rather than just existence of a private valid table. Some FOL-Zinc benchmark claims are public relation constants rather than Zinc public-input coordinates.",
    "For Fibonacci comparisons, note whether arithmetic is modulo 2^64 or ordinary non-modular integer arithmetic; the bundled FOL-Zinc Fibonacci benchmark uses ordinary integers.",
]

SECURITY_NOTES = [
    "This is research/prototype code. Treat the output as an experimental benchmark, not as production cryptography.",
    "The bundled runner proves the exported CCS relation. The mathematical significance comes from the exporter preserving the zkFOL direct semantics via mkQ and beta checks.",
    "The generated JSON includes the private witness so that the public Zinc proof-of-concept can be benchmarked conveniently. Do not use these files as privacy-preserving artefacts by themselves.",
    "A real deployment would need parameter review, proof serialisation, transcript/domain-separation review, and independent cryptographic audit.",
]


def constraint_category(label: str | None) -> str:
    """Classify a generated R1CS row by its stable label prefix."""
    label = label or ""
    if label.startswith("boolean:"):
        return "booleanity_bit_checks"
    if label.startswith("range:") and label.endswith(":one_hot"):
        return "pointer_range_one_hot_checks"
    if label.startswith("range:") and label.endswith(":value_in_1..len"):
        return "pointer_range_value_checks"
    if label.startswith("lookup_product:"):
        return "pointer_lookup_selector_products"
    if label.startswith("lookup_value:"):
        return "pointer_lookup_value_equalities"
    if label.startswith("lookup:B_"):
        return "pointer_lookup_bit_equalities"
    if label.startswith("public_binding:"):
        return "public_input_binding_checks"
    if label.startswith("fib_direct_base_case:") or label.startswith("fib_base:"):
        return "direct_fibonacci_base_checks"
    if label.startswith("fib_direct_recurrence:") or label.startswith("fib_step:"):
        return "direct_fibonacci_step_checks"
    if label.startswith("fib_pointer:"):
        return "direct_fibonacci_pointer_checks"
    if label.startswith("mkq_zero:"):
        return "mkq_zero_checks"
    if label.startswith("mkq_x="):
        return "mkq_arithmetic_gates"
    return "other"


def constraint_breakdown(constraints: Iterable[Mapping[str, Any]]) -> dict[str, int]:
    """Count generated constraints by purpose, preserving a useful order."""
    counts = Counter(constraint_category(row.get("label")) for row in constraints)
    return {key: int(counts.get(key, 0)) for key in CONSTRAINT_BREAKDOWN_DESCRIPTIONS}


def build_exposition(
    *,
    example: Any,
    witness: Any,
    pointer_rows: list[int] | set[int] | tuple[int, ...],
    representation: str = "typed",
) -> dict[str, Any]:
    """Return a JSON-serialisable explanation block for one exported example."""
    return {
        "adapter_version": ADAPTER_VERSION,
        "representation": representation,
        "what_this_file_is": (
            "A self-contained benchmark input produced from a concrete zkFOL reference example. "
            "It contains the finite FOL witness matrix, the local semantic cross-checks, and a signed "
            "integer R1CS/CCS instance for the Rust Zinc runner."
        ),
        "what_is_being_proved": (
            f"Knowledge of the private witness values encoded in the exported CCS instance, such that "
            f"the FOL judgement for example '{example.name}' is valid on every column x of a "
            f"{witness.arity} by {witness.length} finite matrix interpretation."
        ),
        "why_zero_matters": (
            "The paper's integer semantics represents truth by 0. Therefore every direct predicate "
            "value and every beta_F(mkQ_x(<phi>)) value should be 0 for a valid witness."
        ),
        "pipeline": PIPELINE_STEPS,
        "field_glossary": FIELD_GLOSSARY,
        "constraint_breakdown_descriptions": CONSTRAINT_BREAKDOWN_DESCRIPTIONS,
        "benchmarking_notes": BENCHMARKING_NOTES,
        "security_notes": SECURITY_NOTES,
        "example_summary": {
            "name": example.name,
            "description": example.description,
            "mathematical_description": example.mathematical_description,
            "witness_convention": example.witness_convention,
            "paper_reference": example.paper_reference,
            "arity": witness.arity,
            "length": witness.length,
            "max_bits": witness.max_bits,
            "pointer_rows": sorted(int(p) for p in pointer_rows),
        },
    }
