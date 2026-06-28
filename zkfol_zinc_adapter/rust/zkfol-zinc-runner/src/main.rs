use num_bigint::{BigInt, Sign};
use num_traits::{One, ToPrimitive};
use serde::{Deserialize, Serialize};
use std::{
    collections::BTreeMap,
    env, fs,
    io::IsTerminal,
    marker::PhantomData,
    process,
    time::Instant,
};

use zinc::{
    ccs::ccs_f::Arith as ArithF,
    define_random_field_zip_types,
    field::{ConfigRef, Int, RandomField},
    implement_random_field_zip_types,
    sparse_matrix::SparseMatrix,
    zinc::prelude::*,
};

define_random_field_zip_types!();
implement_random_field_zip_types!(2);
implement_random_field_zip_types!(4);
implement_random_field_zip_types!(8);
implement_random_field_zip_types!(16);
implement_random_field_zip_types!(32);
implement_random_field_zip_types!(64);
implement_random_field_zip_types!(128);
implement_random_field_zip_types!(256);

#[derive(Debug, Deserialize)]
struct ExportFile {
    schema: String,
    name: String,
    #[serde(default)]
    description: Option<String>,
    #[serde(default)]
    adapter_version: Option<String>,
    #[serde(default)]
    adapter_kind: Option<String>,
    dimensions: Dimensions,
    ccs: ExportCcs,
    #[serde(default)]
    zkfol: Option<ZkFolMetadata>,
    #[serde(default)]
    exposition: Option<ExpositionMetadata>,
    #[serde(default)]
    constraint_breakdown: BTreeMap<String, usize>,
    #[serde(default)]
    stats: Option<StatsMetadata>,
}

#[derive(Debug, Deserialize)]
struct Dimensions {
    constraints: usize,
    z_len: usize,
    witness_variables: usize,
    #[serde(default)]
    arity: Option<usize>,
    #[serde(default)]
    length: Option<usize>,
    #[serde(default)]
    max_bits: Option<usize>,
}

#[derive(Debug, Deserialize)]
struct ExportCcs {
    public_inputs: Vec<serde_json::Value>,
    #[serde(default)]
    public_input_names: Vec<String>,
    #[serde(default)]
    public_bindings: Vec<serde_json::Value>,
    witness: Vec<serde_json::Value>,
    constraints: Vec<ExportConstraint>,
}

type ExportTerm = (usize, serde_json::Value);

#[derive(Debug, Deserialize)]
struct ExportConstraint {
    a: Vec<ExportTerm>,
    b: Vec<ExportTerm>,
    c: Vec<ExportTerm>,
    #[serde(default)]
    label: Option<String>,
}

#[derive(Debug, Deserialize)]
struct ZkFolMetadata {
    #[serde(default)]
    pointer_rows: Vec<usize>,
    #[serde(default)]
    paper_reference: Option<String>,
    #[serde(default)]
    mathematical_description: Option<String>,
    #[serde(default)]
    witness_convention: Option<String>,
    #[serde(default)]
    reference_report: Option<ReferenceReport>,
}

#[derive(Debug, Deserialize)]
struct ReferenceReport {
    #[serde(default)]
    semantics_agree: Option<bool>,
    #[serde(default)]
    all_zero: Option<bool>,
    #[serde(default)]
    pointer_range_ok: Option<bool>,
    #[serde(default)]
    direct_values: Option<Vec<serde_json::Value>>,
    #[serde(default)]
    beta_values: Option<Vec<serde_json::Value>>,
}

#[derive(Debug, Deserialize)]
struct ExpositionMetadata {
    #[serde(default)]
    concrete_statement: Vec<String>,
    #[serde(default)]
    what_is_being_proved: Option<String>,
    #[serde(default)]
    why_zero_matters: Option<String>,
    #[serde(default)]
    what_this_file_is: Option<String>,
}

#[derive(Debug, Deserialize)]
struct StatsMetadata {
    #[serde(default)]
    bit_wires: Option<usize>,
    #[serde(default)]
    b_wires: Option<usize>,
    #[serde(default)]
    selector_wires: Option<usize>,
    #[serde(default)]
    max_abs_value_bit_length: Option<usize>,
    #[serde(default)]
    max_abs_value_decimal: Option<String>,
    #[serde(default)]
    constraint_breakdown: BTreeMap<String, usize>,
}

#[derive(Debug, Clone)]
struct ConstraintShape {
    target_use_case: String,
    scalar_variables_unpadded: usize,
    public_input_variables: usize,
    private_witness_variables: usize,
    constant_one_coordinates: usize,
    constraints_unpadded: usize,
    ccs_declared_degree: usize,
    max_simplified_degree_over_private_witness: usize,
    bit_bound_delta: usize,
    max_public_input_bit_length: usize,
    max_witness_value_bit_length: usize,
    max_constraint_coefficient_bit_length: usize,
    bilinear_rows_observed: usize,
    linear_rows_after_fixing_public: usize,
    padded_ccs_dimension_estimate: usize,
}

#[derive(Debug, Serialize)]
struct RunReport {
    name: String,
    schema: String,
    adapter_version: Option<String>,
    mode: String,
    int_limbs: usize,
    field_limbs: usize,
    constraints_unpadded: usize,
    witness_variables: usize,
    z_len_unpadded: usize,
    scalar_variables_unpadded: usize,
    public_input_variables: usize,
    private_witness_variables: usize,
    constant_one_coordinates: usize,
    ccs_declared_degree: usize,
    max_simplified_degree_over_private_witness: usize,
    bit_bound_delta: usize,
    max_public_input_bit_length: usize,
    max_witness_value_bit_length: usize,
    max_constraint_coefficient_bit_length: usize,
    bilinear_rows_observed: usize,
    linear_rows_after_fixing_public: usize,
    ccs_m_padded: usize,
    ccs_n_padded: usize,
    relation_check_ms: f64,
    prove_ms: Option<f64>,
    verify_ms: Option<f64>,
    field_setup_ms: Option<f64>,
    field_relation_check_ms: Option<f64>,
    zinc_prove_call_ms: Option<f64>,
    zinc_verify_call_ms: Option<f64>,
    measured_iteration_ms: Option<f64>,
    timing_note: Option<String>,
    repeat: usize,
    proved: bool,
    local_relation_satisfied: bool,
    constraint_breakdown: BTreeMap<String, usize>,
}

fn usage() -> ! {
    eprintln!(
        "usage: zkfol-zinc-runner --input INSTANCE.json [options]\n\n\
         Required:\n\
           --input PATH, -i PATH       exported JSON produced by zkfol-zinc-export\n\n\
         Output and mode options:\n\
           --check-only                check the integer relation and skip Zinc prove/verify\n\
           --repeat N                  prove/verify repetitions for timing averages\n\
           --json, --machine-json      print machine-readable JSON report\n\
           --explain                   print the human-readable report\n\
           --version, -V               print runner version\n\n\
         Zinc profile and safety options:\n\
           --int-limbs N, --limbs N    auto, 2, 4, 8, 16, 32, 64, or 128\n\
           --strict-int-limbs          honour an oversized --int-limbs request exactly\n\
           --force-int-limbs           alias for --strict-int-limbs\n\
           --allow-oversized-limbs     alias for --strict-int-limbs\n\
           --allow-large               bypass dense-allocation safety guard\n\
           --max-single-allocation-gib GIB\n\
                                       dense-allocation guard limit\n\n\
         Progress options:\n\
           --progress                  emit coarse phase markers on stderr\n\
           --no-progress               suppress progress markers\n\n\
         The input JSON is produced by zkfol-zinc-export. By default this prints\n\
         a human-readable explanation, checks the integer CCS relation, runs Zinc\n\
         prove, and runs Zinc verify. Use --json for the machine-readable timing\n\
         report. Use --check-only to skip proof generation. The --int-limbs\n\
         option controls the signed integer width used by Zinc; auto chooses a\n\
         width from stats.max_abs_value_bit_length in the JSON, and oversized\n\
         explicit requests are downshifted unless strict mode is used. Use --progress\n\
         to emit coarse phase progress markers on stderr for wrapper scripts.\n\
         The memory preflight refuses proof runs whose estimated largest current-Zinc\n\
         dense allocation exceeds --max-single-allocation-gib, unless --allow-large is supplied."
    );
    process::exit(2);
}

#[derive(Debug)]
struct Args {
    input: String,
    check_only: bool,
    repeat: usize,
    json: bool,
    int_limbs: Option<usize>,
    progress: bool,
    strict_int_limbs: bool,
    allow_large: bool,
    max_single_allocation_gib: f64,
}

fn parse_args() -> Args {
    let mut input: Option<String> = None;
    let mut check_only = false;
    let mut repeat = 1usize;
    let mut json = false;
    let mut int_limbs: Option<usize> = None;
    let mut progress = false;
    let mut strict_int_limbs = false;
    let mut allow_large = false;
    let mut max_single_allocation_gib = 128.0f64;
    let mut args = env::args().skip(1);
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--input" | "-i" => input = args.next(),
            "--check-only" => check_only = true,
            "--json" | "--machine-json" => json = true,
            "--explain" => json = false,
            "--progress" => progress = true,
            "--no-progress" => progress = false,
            "--strict-int-limbs" | "--force-int-limbs" | "--allow-oversized-limbs" => strict_int_limbs = true,
            "--version" | "-V" => {
                println!("zkfol-zinc-runner {}", env!("CARGO_PKG_VERSION"));
                process::exit(0);
            }
            "--allow-large" => allow_large = true,
            "--max-single-allocation-gib" => {
                let raw = args.next().unwrap_or_else(|| usage());
                max_single_allocation_gib = raw.parse().unwrap_or_else(|_| usage());
                if !(max_single_allocation_gib > 0.0) {
                    usage();
                }
            }
            "--repeat" => {
                let raw = args.next().unwrap_or_else(|| usage());
                repeat = raw.parse().unwrap_or_else(|_| usage());
                if repeat == 0 {
                    usage();
                }
            }
            "--int-limbs" | "--limbs" => {
                let raw = args.next().unwrap_or_else(|| usage());
                if raw == "auto" {
                    int_limbs = None;
                } else {
                    let parsed: usize = raw.parse().unwrap_or_else(|_| usage());
                    match parsed {
                        2 | 4 | 8 | 16 | 32 | 64 | 128 => int_limbs = Some(parsed),
                        _ => usage(),
                    }
                }
            }
            "--help" | "-h" => usage(),
            other if other.starts_with('-') => usage(),
            other => input = Some(other.to_owned()),
        }
    }
    Args {
        input: input.unwrap_or_else(|| usage()),
        check_only,
        repeat,
        json,
        int_limbs,
        progress,
        strict_int_limbs,
        allow_large,
        max_single_allocation_gib,
    }
}

fn progress_total_units(args: &Args) -> usize {
    if args.check_only {
        1
    } else {
        // local integer relation check + per-repetition random-field setup,
        // sampled-field check, prove, and verify units.
        1 + 4 * args.repeat
    }
}

fn emit_progress(
    args: &Args,
    phase: &str,
    event: &str,
    iteration: Option<usize>,
    elapsed_ms: Option<f64>,
    message: impl Into<String>,
) {
    if !args.progress {
        return;
    }
    let obj = serde_json::json!({
        "event": event,
        "phase": phase,
        "iteration": iteration,
        "repeat": args.repeat,
        "check_only": args.check_only,
        "total_units": progress_total_units(args),
        "elapsed_ms": elapsed_ms,
        "message": message.into(),
    });
    eprintln!("FOLZINC_PROGRESS {}", obj);
}

fn int_from_nonnegative_bigint<const N: usize>(value: &BigInt, label: &str) -> Int<N> {
    assert!(
        value.sign() != Sign::Minus,
        "internal error: attempted to encode a negative integer as nonnegative for {}",
        label
    );
    let (sign, mut bytes) = value.to_bytes_le();
    assert!(sign != Sign::Minus, "unexpected negative byte encoding for {}", label);
    assert!(
        bytes.len() <= 8 * N,
        "{}={} does not fit Int<{}> ({} bytes available)",
        label,
        value,
        N,
        8 * N
    );
    bytes.resize(8 * N, 0);
    let mut words = [0u64; N];
    for i in 0..N {
        let mut word_bytes = [0u8; 8];
        word_bytes.copy_from_slice(&bytes[(8 * i)..(8 * i + 8)]);
        words[i] = u64::from_le_bytes(word_bytes);
    }
    Int::<N>::from(words)
}

fn int_from_bigint<const N: usize>(value: &BigInt, label: &str) -> Int<N> {
    let bits = 64usize * N;
    let min = -(BigInt::one() << (bits - 1));
    let max = (BigInt::one() << (bits - 1)) - BigInt::one();
    assert!(
        value >= &min && value <= &max,
        "{}={} does not fit Int<{}> ({} signed bits). Re-run with a larger --int-limbs value.",
        label,
        value,
        N,
        bits
    );

    // Important: do not manually encode negative values as two's-complement
    // words.  Zinc's Int type preserves signedness when constructed through
    // its signed constructors and negation operator, and Zinc's map_to_field
    // relies on that signedness when reducing integer relations into the
    // sampled random field.  A word-level two's-complement construction can
    // satisfy the local Int relation but fail the field relation used by the
    // Spartan/Zinc verifier.
    if let Some(v) = value.to_i64() {
        return Int::<N>::from(v);
    }
    if value.sign() == Sign::Minus {
        let abs = -value.clone();
        let pos = int_from_nonnegative_bigint::<N>(&abs, label);
        return -pos;
    }
    int_from_nonnegative_bigint::<N>(value, label)
}

fn bigint_from_decimal(raw: &str, label: &str) -> BigInt {
    raw.parse::<BigInt>()
        .unwrap_or_else(|_| panic!("invalid integer literal for {}: {}", label, raw))
}

fn bigint_from_json_integer(value: &serde_json::Value, label: &str) -> BigInt {
    match value {
        serde_json::Value::Number(n) => {
            if let Some(v) = n.as_i64() {
                BigInt::from(v)
            } else if let Some(v) = n.as_u64() {
                BigInt::from(v)
            } else {
                panic!("unsupported non-integer JSON value for {}: {}", label, n)
            }
        }
        serde_json::Value::String(s) => bigint_from_decimal(s, label),
        other => panic!("unsupported integer JSON value for {}: {:?}", label, other),
    }
}

fn json_integer_to_string(value: &serde_json::Value, label: &str) -> String {
    bigint_from_json_integer(value, label).to_string()
}

fn int_from_json<const N: usize>(value: &serde_json::Value, label: &str) -> Int<N> {
    let value = bigint_from_json_integer(value, label);
    int_from_bigint::<N>(&value, label)
}

fn term_coeff_to_bigint(value: &serde_json::Value) -> BigInt {
    bigint_from_json_integer(value, "matrix coefficient")
}

fn remap_z_term_for_zinc_public_compat(
    old_idx: usize,
    coeff: BigInt,
    old_public_inputs: &[BigInt],
    new_public_inputs_len: usize,
    old_n_cols: usize,
) -> (usize, BigInt) {
    let old_public_len = old_public_inputs.len();
    assert!(old_public_len >= 1, "exports must contain at least public_zero");
    assert!(
        new_public_inputs_len == 1 || new_public_inputs_len == old_public_len,
        "internal public-input normalisation only preserves one public coordinate or all of them"
    );
    assert!(old_idx < old_n_cols, "term index {} is outside z length {}", old_idx, old_n_cols);

    if new_public_inputs_len == old_public_len {
        return (old_idx, coeff);
    }

    // Compatibility mode for the current Zinc proof-of-concept: keep only the
    // conventional public_zero coordinate as statement.public_input and embed
    // any additional public claims as public constants in the relation/index.
    // This preserves the mathematical statement because the exported JSON and
    // its constants are public verifier data, while avoiding Zinc edge cases
    // around multi-coordinate public input vectors.
    let old_one_idx = old_public_len;
    let new_one_idx = new_public_inputs_len;
    if old_idx < old_public_len {
        if old_idx == 0 {
            (0, coeff)
        } else {
            (new_one_idx, coeff * &old_public_inputs[old_idx])
        }
    } else if old_idx == old_one_idx {
        (new_one_idx, coeff)
    } else {
        let witness_offset = old_idx - old_one_idx - 1;
        (new_public_inputs_len + 1 + witness_offset, coeff)
    }
}

fn sparse_matrix_from_constraints<const N: usize>(
    rows: &[ExportConstraint],
    side: char,
    old_public_inputs: &[BigInt],
    new_public_inputs_len: usize,
    old_n_cols: usize,
) -> SparseMatrix<Int<N>> {
    let new_n_cols = new_public_inputs_len + 1 + (old_n_cols - old_public_inputs.len() - 1);
    let mut coeffs: Vec<Vec<(Int<N>, usize)>> = Vec::with_capacity(rows.len());

    for (row_idx, row) in rows.iter().enumerate() {
        let terms = match side {
            'a' => &row.a,
            'b' => &row.b,
            'c' => &row.c,
            _ => panic!("unknown side"),
        };

        // The exported JSON is sparse, but terms may repeat a column.  Accumulate
        // as BigInts so coefficients such as 2**256 and negative coefficients are
        // preserved exactly, then encode them into Zinc's fixed-width Int<N>.
        let mut acc: BTreeMap<usize, BigInt> = BTreeMap::new();
        for (old_idx, coeff_value) in terms {
            let coeff = term_coeff_to_bigint(coeff_value);
            let (idx, remapped_coeff) = remap_z_term_for_zinc_public_compat(
                *old_idx,
                coeff,
                old_public_inputs,
                new_public_inputs_len,
                old_n_cols,
            );
            assert!(idx < new_n_cols, "remapped term index {} is outside z length {}", idx, new_n_cols);
            let entry = acc.entry(idx).or_insert_with(|| BigInt::from(0));
            *entry += remapped_coeff;
        }

        let mut sparse_row = Vec::new();
        for (col, coeff) in acc {
            if coeff == BigInt::from(0) {
                continue;
            }
            sparse_row.push((int_from_bigint::<N>(&coeff, &format!("matrix coefficient row {} col {}", row_idx, col)), col));
        }
        coeffs.push(sparse_row);
    }

    SparseMatrix {
        n_rows: rows.len(),
        n_cols: new_n_cols,
        coeffs,
    }
}

fn floor_log2_power_hint(x: usize) -> usize {
    if x <= 1 {
        0
    } else {
        (usize::BITS - 1 - x.leading_zeros()) as usize
    }
}

#[allow(non_snake_case)]
fn build_ccs<const N: usize>(export: &ExportFile) -> (CCS_Z<Int<N>>, Statement_Z<Int<N>>, Witness_Z<Int<N>>) {
    assert!(
        export.schema == "zkfol-zinc-ccs-v1" || export.schema == "zkfol-zinc-ccs-v2",
        "unsupported schema {}",
        export.schema
    );
    assert_eq!(export.dimensions.constraints, export.ccs.constraints.len());
    assert_eq!(export.dimensions.witness_variables, export.ccs.witness.len());
    assert_eq!(
        export.dimensions.z_len,
        export.ccs.public_inputs.len() + 1 + export.ccs.witness.len()
    );

    let m = export.ccs.constraints.len();
    let old_n = export.dimensions.z_len;
    let old_public_inputs: Vec<BigInt> = export
        .ccs
        .public_inputs
        .iter()
        .enumerate()
        .map(|(i, v)| bigint_from_json_integer(v, &format!("public input {}", i)))
        .collect();
    assert!(!old_public_inputs.is_empty(), "exports must contain public_zero at public input 0");
    assert!(
        old_public_inputs[0] == BigInt::from(0),
        "public input 0 must be the conventional public_zero coordinate"
    );

    let zinc_public_inputs: Vec<BigInt> = if old_public_inputs.len() <= 1 {
        old_public_inputs.clone()
    } else {
        vec![old_public_inputs[0].clone()]
    };
    let n = zinc_public_inputs.len() + 1 + export.ccs.witness.len();
    let A = sparse_matrix_from_constraints::<N>(
        &export.ccs.constraints,
        'a',
        &old_public_inputs,
        zinc_public_inputs.len(),
        old_n,
    );
    let B = sparse_matrix_from_constraints::<N>(
        &export.ccs.constraints,
        'b',
        &old_public_inputs,
        zinc_public_inputs.len(),
        old_n,
    );
    let C = sparse_matrix_from_constraints::<N>(
        &export.ccs.constraints,
        'c',
        &old_public_inputs,
        zinc_public_inputs.len(),
        old_n,
    );
    let constraints = vec![A, B, C];
    let public_input = zinc_public_inputs
        .iter()
        .enumerate()
        .map(|(i, v)| int_from_bigint::<N>(v, &format!("public input {}", i)))
        .collect();
    let witness = Witness_Z::new(
        export
            .ccs
            .witness
            .iter()
            .enumerate()
            .map(|(i, v)| int_from_json::<N>(v, &format!("witness {}", i)))
            .collect(),
    );
    let mut ccs = CCS_Z {
        m,
        n,
        l: zinc_public_inputs.len(),
        t: 3,
        q: 2,
        d: 2,
        s: floor_log2_power_hint(m),
        s_prime: floor_log2_power_hint(n),
        S: vec![vec![0, 1], vec![2]],
        c: vec![1, -1],
        _phantom: PhantomData,
    };
    let mut statement = Statement_Z { constraints, public_input };

    let z = statement.get_z_vector(&witness.w_ccs);
    ccs.check_relation(&statement.constraints, &z)
        .expect("exported CCS relation is not satisfied before padding");

    let padded = usize::max(ccs.m.next_power_of_two(), ccs.n.next_power_of_two());
    ccs.pad(&mut statement, padded);
    (ccs, statement, witness)
}

fn classify_constraint(label: Option<&str>) -> &'static str {
    let label = label.unwrap_or("");
    if label.starts_with("boolean:") {
        "booleanity_bit_checks"
    } else if label.starts_with("range:") && label.ends_with(":one_hot") {
        "pointer_range_one_hot_checks"
    } else if label.starts_with("range:") && label.ends_with(":value_in_1..len") {
        "pointer_range_value_checks"
    } else if label.starts_with("lookup_product:") {
        "pointer_lookup_selector_products"
    } else if label.starts_with("lookup_value:") {
        "pointer_lookup_value_equalities"
    } else if label.starts_with("lookup:B_") {
        "pointer_lookup_bit_equalities"
    } else if label.starts_with("public_binding:") {
        "public_input_binding_checks"
    } else if label.starts_with("fib_direct_base_case:") || label.starts_with("fib_base:") {
        "direct_fibonacci_base_checks"
    } else if label.starts_with("fib_direct_recurrence:") || label.starts_with("fib_step:") {
        "direct_fibonacci_step_checks"
    } else if label.starts_with("fib_pointer:") {
        "direct_fibonacci_pointer_checks"
    } else if label.starts_with("mkq_zero:") {
        "mkq_zero_checks"
    } else if label.starts_with("mkq_x=") {
        "mkq_arithmetic_gates"
    } else {
        "other"
    }
}

fn computed_constraint_breakdown(export: &ExportFile) -> BTreeMap<String, usize> {
    let keys = [
        "mkq_arithmetic_gates",
        "mkq_zero_checks",
        "pointer_range_one_hot_checks",
        "pointer_range_value_checks",
        "pointer_lookup_selector_products",
        "pointer_lookup_value_equalities",
        "pointer_lookup_bit_equalities",
        "booleanity_bit_checks",
        "public_input_binding_checks",
        "direct_fibonacci_base_checks",
        "direct_fibonacci_step_checks",
        "direct_fibonacci_pointer_checks",
        "other",
    ];
    let mut out = BTreeMap::new();
    for key in keys {
        out.insert(key.to_owned(), 0usize);
    }
    for row in &export.ccs.constraints {
        let key = classify_constraint(row.label.as_deref()).to_owned();
        *out.entry(key).or_insert(0) += 1;
    }
    out
}

fn constraint_breakdown(export: &ExportFile) -> BTreeMap<String, usize> {
    if !export.constraint_breakdown.is_empty() {
        return export.constraint_breakdown.clone();
    }
    if let Some(stats) = &export.stats {
        if !stats.constraint_breakdown.is_empty() {
            return stats.constraint_breakdown.clone();
        }
    }
    computed_constraint_breakdown(export)
}

fn bigint_bit_length(value: &BigInt) -> usize {
    if value == &BigInt::from(0) {
        return 0;
    }
    let abs = if value.sign() == Sign::Minus { -value.clone() } else { value.clone() };
    let (_sign, bytes) = abs.to_bytes_be();
    if bytes.is_empty() {
        0
    } else {
        let leading = bytes[0].leading_zeros() as usize;
        (bytes.len() - 1) * 8 + (8 - leading)
    }
}

fn lin_degree_over_private_witness(terms: &[ExportTerm], public_inputs: usize) -> usize {
    let constant_one_index = public_inputs;
    for (idx, coeff_value) in terms {
        let coeff = term_coeff_to_bigint(coeff_value);
        if coeff != BigInt::from(0) && *idx > constant_one_index {
            return 1;
        }
    }
    0
}

fn target_use_case(export: &ExportFile) -> String {
    let kind = export.adapter_kind.as_deref().unwrap_or("");
    if export.name.starts_with("fibonacci_exact") && kind.contains("compact") {
        "compact exact-integer Fibonacci benchmark".to_owned()
    } else if export.name.starts_with("fibonacci_exact") {
        "full exact-integer Fibonacci trace benchmark".to_owned()
    } else if export.name.starts_with("efficient_power") {
        "efficient repeated-squaring power benchmark".to_owned()
    } else if export.name.starts_with("standard_power") {
        "standard recursive power benchmark".to_owned()
    } else {
        "exported FOL-Zinc instance".to_owned()
    }
}

fn constraint_shape(export: &ExportFile) -> ConstraintShape {
    let public_input_variables = export.ccs.public_inputs.len();
    let private_witness_variables = export.ccs.witness.len();
    let scalar_variables_unpadded = export.dimensions.z_len;
    let constraints_unpadded = export.dimensions.constraints;
    let padded_ccs_dimension_estimate = usize::max(
        next_power_of_two_usize(constraints_unpadded),
        next_power_of_two_usize(scalar_variables_unpadded),
    );

    let mut public_bits = 0usize;
    for (i, value) in export.ccs.public_inputs.iter().enumerate() {
        let parsed = bigint_from_json_integer(value, &format!("public input {}", i));
        public_bits = usize::max(public_bits, bigint_bit_length(&parsed));
    }
    let mut witness_bits = 0usize;
    for (i, value) in export.ccs.witness.iter().enumerate() {
        let parsed = bigint_from_json_integer(value, &format!("witness {}", i));
        witness_bits = usize::max(witness_bits, bigint_bit_length(&parsed));
    }
    let mut coeff_bits = 0usize;
    let mut max_simplified_degree = 0usize;
    let mut bilinear_rows = 0usize;
    let mut linear_rows = 0usize;

    for row in &export.ccs.constraints {
        for (_idx, coeff_value) in row.a.iter().chain(row.b.iter()).chain(row.c.iter()) {
            let coeff = term_coeff_to_bigint(coeff_value);
            coeff_bits = usize::max(coeff_bits, bigint_bit_length(&coeff));
        }
        let deg_a = lin_degree_over_private_witness(&row.a, public_input_variables);
        let deg_b = lin_degree_over_private_witness(&row.b, public_input_variables);
        let deg_c = lin_degree_over_private_witness(&row.c, public_input_variables);
        let product_degree = deg_a + deg_b;
        let row_degree = usize::max(product_degree, deg_c);
        max_simplified_degree = usize::max(max_simplified_degree, row_degree);
        if product_degree >= 2 {
            bilinear_rows += 1;
        } else if row_degree == 1 {
            linear_rows += 1;
        }
    }

    let bit_bound = usize::max(public_bits, usize::max(witness_bits, coeff_bits));
    ConstraintShape {
        target_use_case: target_use_case(export),
        scalar_variables_unpadded,
        public_input_variables,
        private_witness_variables,
        constant_one_coordinates: 1,
        constraints_unpadded,
        ccs_declared_degree: 2,
        max_simplified_degree_over_private_witness: max_simplified_degree,
        bit_bound_delta: bit_bound,
        max_public_input_bit_length: public_bits,
        max_witness_value_bit_length: witness_bits,
        max_constraint_coefficient_bit_length: coeff_bits,
        bilinear_rows_observed: bilinear_rows,
        linear_rows_after_fixing_public: linear_rows,
        padded_ccs_dimension_estimate,
    }
}

fn yes_no(value: Option<bool>) -> &'static str {
    match value {
        Some(true) => "yes",
        Some(false) => "NO",
        None => "not recorded",
    }
}

fn print_optional_line(label: &str, value: &Option<String>) {
    if let Some(v) = value {
        println!("{}: {}", label, v);
    }
}

fn should_use_ansi() -> bool {
    std::io::stdout().is_terminal() && env::var_os("NO_COLOR").is_none()
}

fn emphasize_concrete_line(line: &str) -> String {
    if should_use_ansi() && line.starts_with("Concrete computation:") {
        format!("\x1b[1m{}\x1b[0m", line)
    } else {
        line.to_string()
    }
}

fn print_human_report(export: &ExportFile, report: &RunReport, args: &Args) {
    println!("zkFOL -> Zinc benchmark");
    println!("=======================");
    println!("Input: {}", args.input);
    println!("Example: {}", export.name);
    println!("Schema: {}", export.schema);
    print_optional_line("Description", &export.description);
    print_optional_line("Adapter version", &export.adapter_version);
    print_optional_line("Adapter kind", &export.adapter_kind);
    println!("Mode: {}", report.mode);
    if report.field_limbs == 0 {
        println!("Integer limb profile: Int<{}>; RandomField not used in --check-only mode", report.int_limbs);
    } else {
        println!("Integer limb profile: Int<{}>, RandomField<{}>", report.int_limbs, report.field_limbs);
    }
    println!();

    if let Some(exposition) = &export.exposition {
        if !exposition.concrete_statement.is_empty() {
            println!("Concrete computation / public claim");
            println!("-----------------------------------");
            for line in &exposition.concrete_statement {
                println!("{}", emphasize_concrete_line(line));
            }
            if !export.ccs.public_input_names.is_empty() {
                let preview: Vec<String> = export
                    .ccs
                    .public_input_names
                    .iter()
                    .zip(export.ccs.public_inputs.iter())
                    .take(8)
                    .map(|(name, value)| format!("{}={}", name, json_integer_to_string(value, name)))
                    .collect();
                println!("Public inputs: {}", preview.join(", "));
            }
            println!();
        }
    }

    println!("What is being proved");
    println!("--------------------");
    if let Some(exposition) = &export.exposition {
        if let Some(text) = &exposition.what_is_being_proved {
            println!("{}", text);
        } else if let Some(text) = &exposition.what_this_file_is {
            println!("{}", text);
        }
        if let Some(text) = &exposition.why_zero_matters {
            println!("{}", text);
        }
    } else {
        println!(
            "Knowledge of private witness values satisfying the exported signed integer CCS relation. The exporter produced that relation from the zkFOL mkQ/beta checks."
        );
    }
    if let Some(zkfol) = &export.zkfol {
        print_optional_line("Mathematical content", &zkfol.mathematical_description);
        print_optional_line("Witness convention", &zkfol.witness_convention);
        print_optional_line("Paper reference", &zkfol.paper_reference);
        println!("Pointer rows: {:?}", zkfol.pointer_rows);
    }
    println!();

    println!("Exporter semantic checks");
    println!("------------------------");
    if let Some(zkfol) = &export.zkfol {
        if let Some(reference) = &zkfol.reference_report {
            println!(
                "direct semantics == beta_F(mkQ_x(<phi>)): {}",
                yes_no(reference.semantics_agree)
            );
            println!("all predicate values are zero: {}", yes_no(reference.all_zero));
            println!("pointer range checks pass: {}", yes_no(reference.pointer_range_ok));
            if let Some(values) = &reference.beta_values {
                if values.len() <= 16 {
                    println!("beta values by x: {:?}", values);
                } else {
                    println!("beta values by x: first 16 of {} are {:?}", values.len(), &values[..16]);
                }
            }
            if let (Some(direct), Some(beta)) = (&reference.direct_values, &reference.beta_values) {
                if direct != beta && direct.len() <= 16 {
                    println!("direct values by x: {:?}", direct);
                }
            }
        } else {
            println!("No reference_report was recorded in the JSON.");
        }
    } else {
        println!("No zkfol metadata was recorded in the JSON.");
    }
    println!();

    println!("What the Rust runner did");
    println!("------------------------");
    println!("1. Parsed signed integer R1CS/CCS JSON produced by zkfol-zinc-export.");
    println!("2. Reconstructed Zinc CCS_Z matrices A, B, C while preserving signed coefficients.");
    println!("3. Checked every integer relation row locally before padding.");
    println!("4. Padded CCS dimensions to powers of two for Zinc.");
    if args.check_only {
        println!("5. Stopped because --check-only was supplied; Zinc prove/verify was not run.");
    } else {
        println!("5. Checked that the same relation vanishes after reduction to Zinc's sampled random field.");
        println!("6. Ran Zinc prove and Zinc verify {} time(s).", args.repeat);
    }
    println!();

    println!("Size summary");
    println!("------------");
    println!("witness matrix arity:       {}", display_option(export.dimensions.arity));
    println!("witness matrix length:      {}", display_option(export.dimensions.length));
    println!("B-bit width max_bits:       {}", display_option(export.dimensions.max_bits));
    println!("public inputs:              {}", export.ccs.public_inputs.len());
    if !export.ccs.public_input_names.is_empty() {
        let preview: Vec<String> = export
            .ccs
            .public_input_names
            .iter()
            .zip(export.ccs.public_inputs.iter())
            .take(8)
            .map(|(name, value)| format!("{}={}", name, json_integer_to_string(value, name)))
            .collect();
        println!("public input values:        {}", preview.join(", "));
    }
    if !export.ccs.public_bindings.is_empty() {
        println!("public final bindings:      {}", export.ccs.public_bindings.len());
    }
    println!("constraints before padding: {}", report.constraints_unpadded);
    println!("private witness variables:  {}", report.witness_variables);
    println!("z length before padding:    {}", report.z_len_unpadded);
    println!("CCS rows after padding:     {}", report.ccs_m_padded);
    println!("CCS z length after padding: {}", report.ccs_n_padded);
    if let Some(stats) = &export.stats {
        println!("B-variable wires:           {}", display_option(stats.b_wires));
        println!("Boolean-constrained wires:  {}", display_option(stats.bit_wires));
        println!("selector wires:             {}", display_option(stats.selector_wires));
        println!("largest integer bit length: {}", display_option(stats.max_abs_value_bit_length));
        if let Some(max_value) = &stats.max_abs_value_decimal {
            println!("largest abs integer:        {}", max_value);
        }
    }
    println!();

    let shape = constraint_shape(export);
    println!("Zinc constraint shape for this target");
    println!("-------------------------------------");
    println!("target use case:             {}", shape.target_use_case);
    println!("scalar z variables:          {} before padding = {} public + 1 constant-one + {} private",
        report.scalar_variables_unpadded, report.public_input_variables, report.private_witness_variables);
    println!("constraints:                 {} rows before padding", report.constraints_unpadded);
    println!("padded CCS dimension:        {} rows / {} z entries", report.ccs_m_padded, report.ccs_n_padded);
    println!("declared CCS/R1CS degree:    {} (<A,z>*<B,z>=<C,z>)", report.ccs_declared_degree);
    println!("simplified witness degree:   at most {} after fixing public inputs and the constant-one coordinate", report.max_simplified_degree_over_private_witness);
    println!("bit-bound delta:             {} bits", report.bit_bound_delta);
    println!("  public input bits:         {}", report.max_public_input_bit_length);
    println!("  witness value bits:        {}", report.max_witness_value_bit_length);
    println!("  coefficient bits:          {}", report.max_constraint_coefficient_bit_length);
    println!("observed row types:          {} bilinear; {} linear after fixing public/one", report.bilinear_rows_observed, report.linear_rows_after_fixing_public);
    println!("estimated unrun padding:     {} (before runner public-input compatibility normalisation)", shape.padded_ccs_dimension_estimate);
    println!();

    println!("Constraint breakdown");
    println!("--------------------");
    let descriptions = BTreeMap::from([
        ("mkq_arithmetic_gates", "arithmetic gates for mkQ_x(<phi>)"),
        ("mkq_zero_checks", "one zero-check per witness column"),
        ("pointer_range_one_hot_checks", "one-hot range checks for pointer rows"),
        ("pointer_range_value_checks", "pointer value equals selected column"),
        ("pointer_lookup_selector_products", "selector * cell lookup products"),
        ("pointer_lookup_value_equalities", "composed-cell integer lookup equalities"),
        ("pointer_lookup_bit_equalities", "composed-bit lookup equalities"),
        ("booleanity_bit_checks", "bit booleanity checks"),
        ("public_input_binding_checks", "witness entries bound to public claims"),
        ("direct_fibonacci_base_checks", "direct exact-integer Fibonacci base cases"),
        ("direct_fibonacci_step_checks", "direct exact-integer Fibonacci recurrence rows"),
        ("direct_fibonacci_pointer_checks", "direct exact-integer Fibonacci pointer-row checks"),
        ("other", "other constraints"),
    ]);
    for (key, count) in &report.constraint_breakdown {
        if *count == 0 {
            continue;
        }
        let description = descriptions.get(key.as_str()).copied().unwrap_or("");
        println!("{:>8}  {:<40} {}", count, key, description);
    }
    println!();

    println!("Timings");
    println!("-------");
    println!("local integer relation check: {:.6} ms", report.relation_check_ms);
    if args.check_only {
        println!("Zinc prove:  skipped (--check-only)");
        println!("Zinc verify: skipped (--check-only)");
    } else {
        println!("sampled-field setup average:         {:.6} ms over {} run(s)", report.field_setup_ms.unwrap(), args.repeat);
        println!("sampled-field relation check avg:   {:.6} ms over {} run(s)", report.field_relation_check_ms.unwrap(), args.repeat);
        println!("ZincProver::prove call average:     {:.6} ms over {} run(s)", report.zinc_prove_call_ms.unwrap(), args.repeat);
        println!("ZincVerifier::verify call average:  {:.6} ms over {} run(s)", report.zinc_verify_call_ms.unwrap(), args.repeat);
        println!("measured iteration average:         {:.6} ms over {} run(s)", report.measured_iteration_ms.unwrap(), args.repeat);
        if report.verify_ms.unwrap() > report.prove_ms.unwrap() {
            println!();
            println!("Timing note: verifier-call time is larger than prover-call time here. This is possible in the current Zinc proof-of-concept and adapter path; it is not a claim about the asymptotic verifier of an optimized SNARK implementation.");
        }
    }
    println!();

    println!("Interpretation");
    println!("--------------");
    println!("local_relation_satisfied=true means the exported witness satisfies every integer CCS row before Zinc is called.");
    if !args.check_only {
        println!("The runner also checks the sampled random-field relation before proof generation; this catches integer-encoding and limb-width mismatches early.");
        println!("Timing names are deliberately explicit: ZincProver::prove and ZincVerifier::verify are timed as library calls, while sampled-field setup and adapter field checks are reported separately.");
    }
    if args.check_only {
        println!("proved=false because no Zinc proof was requested; this run only validated the exported relation locally.");
    } else {
        println!("proved=true means Zinc generated a proof and the Zinc verifier accepted it for this exported CCS statement.");
    }
    println!("The benchmark is for the exported CCS/R1CS relation. Generic mkQ/beta exports are deliberately clear rather than minimal; the direct Fibonacci benchmark is a specialised non-modular integer recurrence export.");
    println!("Use --json to print the machine-readable timing report.");
}

fn display_option(value: Option<usize>) -> String {
    match value {
        Some(v) => v.to_string(),
        None => "not recorded".to_owned(),
    }
}

fn minimum_int_limbs(export: &ExportFile) -> usize {
    let max_bits = export
        .stats
        .as_ref()
        .and_then(|s| s.max_abs_value_bit_length)
        .unwrap_or(120);
    // Int<N> is a signed 64*N-bit integer.  Leave one sign bit and a little
    // margin for proof-system projections.
    for limbs in [2usize, 4, 8, 16, 32, 64, 128] {
        if max_bits + 2 < 64 * limbs {
            return limbs;
        }
    }
    panic!(
        "largest integer bit length {} is too large for built-in limb profiles; add a larger match arm",
        max_bits
    );
}

fn choose_int_limbs(export: &ExportFile, args: &Args) -> usize {
    let needed = minimum_int_limbs(export);
    let Some(requested) = args.int_limbs else {
        return needed;
    };
    let max_bits = export
        .stats
        .as_ref()
        .and_then(|s| s.max_abs_value_bit_length)
        .unwrap_or(120);
    if requested < needed {
        panic!(
            "requested Int<{}> is too small for largest integer bit length {}; use Int<{}> or larger",
            requested, max_bits, needed
        );
    }
    if requested > needed && !args.strict_int_limbs {
        eprintln!(
            "Limb profile note: requested Int<{}> but this relation needs only Int<{}> (largest integer bit length {}); using Int<{}>. Use --strict-int-limbs to force the larger profile.",
            requested, needed, max_bits, needed
        );
        return needed;
    }
    if requested > needed && args.strict_int_limbs {
        eprintln!(
            "Limb profile note: using oversized Int<{}> exactly as requested although this relation needs only Int<{}> (largest integer bit length {}). Large RandomField setup may dominate runtime.",
            requested, needed, max_bits
        );
    }
    requested
}

fn next_power_of_two_usize(value: usize) -> usize {
    usize::max(1, value).next_power_of_two()
}

fn estimated_dense_allocation_bytes(export: &ExportFile, field_limbs: usize) -> Option<u128> {
    let public_inputs_runner = if export.ccs.public_inputs.len() > 1 {
        1usize
    } else {
        usize::max(1, export.ccs.public_inputs.len())
    };
    let runner_z_len = public_inputs_runner + 1 + export.dimensions.witness_variables;
    let padded = usize::max(
        next_power_of_two_usize(export.dimensions.constraints),
        next_power_of_two_usize(runner_z_len),
    ) as u128;
    let bytes_per_cell = 12u128.checked_mul(field_limbs as u128)?;
    padded.checked_mul(padded)?.checked_mul(bytes_per_cell)
}

fn format_bytes_human(bytes: u128) -> String {
    let units = ["B", "KiB", "MiB", "GiB", "TiB", "PiB"];
    let mut value = bytes as f64;
    let mut unit = units[0];
    for candidate in units {
        unit = candidate;
        if value < 1024.0 || candidate == units[units.len() - 1] {
            break;
        }
        value /= 1024.0;
    }
    if unit == "B" {
        format!("{} {}", bytes, unit)
    } else {
        format!("{:.1} {}", value, unit)
    }
}

fn dense_memory_preflight_or_exit(export: &ExportFile, args: &Args, field_limbs: usize) {
    if args.check_only || args.allow_large {
        return;
    }
    let Some(estimate) = estimated_dense_allocation_bytes(export, field_limbs) else {
        eprintln!("could not estimate Zinc dense allocation; refusing to proceed without --allow-large");
        process::exit(3);
    };
    let limit = (args.max_single_allocation_gib * 1024.0 * 1024.0 * 1024.0) as u128;
    if estimate > limit {
        let public_inputs_runner = if export.ccs.public_inputs.len() > 1 { 1usize } else { usize::max(1, export.ccs.public_inputs.len()) };
        let runner_z_len = public_inputs_runner + 1 + export.dimensions.witness_variables;
        let padded = usize::max(
            next_power_of_two_usize(export.dimensions.constraints),
            next_power_of_two_usize(runner_z_len),
        );
        eprintln!(
            "Zinc memory preflight refused this proof run. Estimated largest dense allocation is {} (padded_dim={} with RandomField<{}>), above the configured limit {:.1} GiB. This is an operational guard for the current Zinc proof-of-concept; the exported integer relation can still be checked with --check-only. Re-run with --allow-large only on a machine that can tolerate this allocation.",
            format_bytes_human(estimate),
            padded,
            field_limbs,
            args.max_single_allocation_gib,
        );
        process::exit(3);
    }
}

fn execute_check_only<const N: usize>(export: &ExportFile, args: &Args) -> RunReport {
    emit_progress(
        args,
        "relation_check",
        "start",
        None,
        None,
        format!("building CCS_Z<Int<{}>> and checking every integer relation row", N),
    );
    let start_check = Instant::now();
    let (ccs, _statement, _witness) = build_ccs::<N>(export);
    let relation_check_ms = start_check.elapsed().as_secs_f64() * 1000.0;
    emit_progress(
        args,
        "relation_check",
        "end",
        None,
        Some(relation_check_ms),
        "local integer relation check completed",
    );

    let shape = constraint_shape(export);

    RunReport {
        name: export.name.clone(),
        schema: export.schema.clone(),
        adapter_version: export.adapter_version.clone(),
        mode: "local-relation-check-only".to_owned(),
        int_limbs: N,
        field_limbs: 0,
        constraints_unpadded: export.dimensions.constraints,
        witness_variables: export.dimensions.witness_variables,
        z_len_unpadded: export.dimensions.z_len,
        scalar_variables_unpadded: shape.scalar_variables_unpadded,
        public_input_variables: shape.public_input_variables,
        private_witness_variables: shape.private_witness_variables,
        constant_one_coordinates: shape.constant_one_coordinates,
        ccs_declared_degree: shape.ccs_declared_degree,
        max_simplified_degree_over_private_witness: shape.max_simplified_degree_over_private_witness,
        bit_bound_delta: shape.bit_bound_delta,
        max_public_input_bit_length: shape.max_public_input_bit_length,
        max_witness_value_bit_length: shape.max_witness_value_bit_length,
        max_constraint_coefficient_bit_length: shape.max_constraint_coefficient_bit_length,
        bilinear_rows_observed: shape.bilinear_rows_observed,
        linear_rows_after_fixing_public: shape.linear_rows_after_fixing_public,
        ccs_m_padded: ccs.m,
        ccs_n_padded: ccs.n,
        relation_check_ms,
        prove_ms: None,
        verify_ms: None,
        field_setup_ms: None,
        field_relation_check_ms: None,
        zinc_prove_call_ms: None,
        zinc_verify_call_ms: None,
        measured_iteration_ms: None,
        timing_note: Some("check-only: no Zinc prove/verify call was made".to_owned()),
        repeat: args.repeat,
        proved: false,
        local_relation_satisfied: true,
        constraint_breakdown: constraint_breakdown(export),
    }
}

macro_rules! define_execute_zinc {
    ($fn_name:ident, $int_limbs:literal, $field_limbs:literal) => {
        fn $fn_name(export: &ExportFile, args: &Args) -> RunReport {
            dense_memory_preflight_or_exit(export, args, $field_limbs);
            emit_progress(
                args,
                "relation_check",
                "start",
                None,
                None,
                format!("building CCS_Z<Int<{}>> and checking every integer relation row", $int_limbs),
            );
            let start_check = Instant::now();
            let (ccs, statement, witness) = build_ccs::<$int_limbs>(export);
            let relation_check_ms = start_check.elapsed().as_secs_f64() * 1000.0;
            emit_progress(
                args,
                "relation_check",
                "end",
                None,
                Some(relation_check_ms),
                "local integer relation check completed",
            );

            let mut prove_total = 0.0;
            let mut verify_total = 0.0;
            let mut field_setup_total = 0.0;
            let mut field_check_total = 0.0;
            let mut iteration_total = 0.0;

            for iteration in 0..args.repeat {
                let iteration_one_based = iteration + 1;
                let prover = ZincProver::<RandomFieldZipTypes<$int_limbs>, RandomField<$field_limbs>, _>::new(DefaultLinearCodeSpec);
                let mut prover_transcript = KeccakTranscript::new();
                emit_progress(
                    args,
                    "field_setup",
                    "start",
                    Some(iteration_one_based),
                    None,
                    format!(
                        "sampling Zinc random prime for RandomField<{}> (about {} bits); this can dominate runtime if --int-limbs is oversized",
                        $field_limbs,
                        64usize * $field_limbs
                    ),
                );
                let start_field_setup = Instant::now();
                let field_config = draw_random_field::<Int<$int_limbs>, RandomField<$field_limbs>>(
                    &statement.public_input,
                    &mut prover_transcript,
                );
                let field_setup_ms = start_field_setup.elapsed().as_secs_f64() * 1000.0;
                field_setup_total += field_setup_ms;
                emit_progress(
                    args,
                    "field_setup",
                    "end",
                    Some(iteration_one_based),
                    Some(field_setup_ms),
                    "Zinc random prime sampled and field configuration created",
                );
                let config_ref = ConfigRef::from(&field_config);

                emit_progress(
                    args,
                    "field_relation_check",
                    "start",
                    Some(iteration_one_based),
                    None,
                    "checking that the integer CCS also vanishes after reduction to Zinc's sampled random field",
                );
                let start_field_check = Instant::now();
                let (z_ccs_field, _z_mle_field, ccs_field, statement_field) =
                    ZincProver::<RandomFieldZipTypes<$int_limbs>, RandomField<$field_limbs>, DefaultLinearCodeSpec>::prepare_for_random_field_piop(
                        &statement,
                        &witness,
                        &ccs,
                        config_ref,
                    )
                    .expect("failed to prepare Zinc random-field relation");
                ccs_field
                    .check_relation(&statement_field.constraints, &z_ccs_field)
                    .expect("exported CCS relation is not satisfied after mapping to Zinc's sampled random field; this usually indicates an integer encoding or limb-width problem before proving");
                let field_check_ms = start_field_check.elapsed().as_secs_f64() * 1000.0;
                field_check_total += field_check_ms;
                emit_progress(
                    args,
                    "field_relation_check",
                    "end",
                    Some(iteration_one_based),
                    Some(field_check_ms),
                    "sampled-field relation check completed",
                );

                emit_progress(
                    args,
                    "prove",
                    "start",
                    Some(iteration_one_based),
                    None,
                    "Zinc prover is running; exact sub-progress is not exposed by Zinc",
                );
                let start = Instant::now();
                let proof = prover
                    .prove(
                        &statement,
                        &witness,
                        &mut prover_transcript,
                        &ccs,
                        ConfigRef::from(&field_config),
                    )
                    .expect("Zinc proof generation failed");
                let prove_ms = start.elapsed().as_secs_f64() * 1000.0;
                prove_total += prove_ms;
                emit_progress(
                    args,
                    "prove",
                    "end",
                    Some(iteration_one_based),
                    Some(prove_ms),
                    "Zinc proof generation completed",
                );

                let verifier = ZincVerifier::<RandomFieldZipTypes<$int_limbs>, RandomField<$field_limbs>, _>::new(DefaultLinearCodeSpec);
                let mut verifier_transcript = KeccakTranscript::new();
                emit_progress(
                    args,
                    "verify",
                    "start",
                    Some(iteration_one_based),
                    None,
                    "Zinc verifier is checking the proof",
                );
                let start = Instant::now();
                verifier
                    .verify(&statement, proof, &mut verifier_transcript, &ccs, config_ref)
                    .expect("Zinc proof verification failed");
                let verify_ms = start.elapsed().as_secs_f64() * 1000.0;
                verify_total += verify_ms;
                iteration_total += field_setup_ms + field_check_ms + prove_ms + verify_ms;
                emit_progress(
                    args,
                    "verify",
                    "end",
                    Some(iteration_one_based),
                    Some(verify_ms),
                    "Zinc proof verification completed",
                );
            }

            let shape = constraint_shape(export);

            RunReport {
                name: export.name.clone(),
                schema: export.schema.clone(),
                adapter_version: export.adapter_version.clone(),
                mode: "prove-and-verify".to_owned(),
                int_limbs: $int_limbs,
                field_limbs: $field_limbs,
                constraints_unpadded: export.dimensions.constraints,
                witness_variables: export.dimensions.witness_variables,
                z_len_unpadded: export.dimensions.z_len,
                scalar_variables_unpadded: shape.scalar_variables_unpadded,
                public_input_variables: shape.public_input_variables,
                private_witness_variables: shape.private_witness_variables,
                constant_one_coordinates: shape.constant_one_coordinates,
                ccs_declared_degree: shape.ccs_declared_degree,
                max_simplified_degree_over_private_witness: shape.max_simplified_degree_over_private_witness,
                bit_bound_delta: shape.bit_bound_delta,
                max_public_input_bit_length: shape.max_public_input_bit_length,
                max_witness_value_bit_length: shape.max_witness_value_bit_length,
                max_constraint_coefficient_bit_length: shape.max_constraint_coefficient_bit_length,
                bilinear_rows_observed: shape.bilinear_rows_observed,
                linear_rows_after_fixing_public: shape.linear_rows_after_fixing_public,
                ccs_m_padded: ccs.m,
                ccs_n_padded: ccs.n,
                relation_check_ms,
                prove_ms: Some(prove_total / args.repeat as f64),
                verify_ms: Some(verify_total / args.repeat as f64),
                field_setup_ms: Some(field_setup_total / args.repeat as f64),
                field_relation_check_ms: Some(field_check_total / args.repeat as f64),
                zinc_prove_call_ms: Some(prove_total / args.repeat as f64),
                zinc_verify_call_ms: Some(verify_total / args.repeat as f64),
                measured_iteration_ms: Some(iteration_total / args.repeat as f64),
                timing_note: Some("prove_ms is the timed ZincProver::prove call, not total prover-side work; verify_ms is the timed ZincVerifier::verify call. Current Zinc proof-of-concept verification can be slower than proving for these sparse adapter inputs because verifier-side mapping/PCS checks materialize relatively large field objects.".to_owned()),
                repeat: args.repeat,
                proved: true,
                local_relation_satisfied: true,
                constraint_breakdown: constraint_breakdown(export),
            }
        }
    };
}

define_execute_zinc!(execute_zinc_2, 2, 4);
define_execute_zinc!(execute_zinc_4, 4, 8);
define_execute_zinc!(execute_zinc_8, 8, 16);
define_execute_zinc!(execute_zinc_16, 16, 32);
define_execute_zinc!(execute_zinc_32, 32, 64);
define_execute_zinc!(execute_zinc_64, 64, 128);
define_execute_zinc!(execute_zinc_128, 128, 256);

fn main() {
    let args = parse_args();
    emit_progress(&args, "load", "start", None, None, "reading exported JSON input");
    let input = fs::read_to_string(&args.input).expect("failed to read input JSON");
    let export: ExportFile = serde_json::from_str(&input).expect("failed to parse input JSON");
    let limbs = choose_int_limbs(&export, &args);
    emit_progress(
        &args,
        "load",
        "end",
        None,
        None,
        format!("parsed input {}; selected Int<{}> profile", export.name, limbs),
    );

    // Keep the proof path monomorphised over concrete Zinc profiles.  Zinc's
    // Prover/Verifier implementations have several associated-type bounds
    // linking RandomFieldZipTypes<N> to RandomField<F>; using a generic
    // execute<N, F> function makes Rust try to prove those bounds for arbitrary
    // const values.  Concrete dispatch mirrors the original small runner that
    // successfully used Int<2>/RandomField<4>, while still allowing wider
    // integer profiles for larger exact-integer examples.
    let report = if args.check_only {
        match limbs {
            2 => execute_check_only::<2>(&export, &args),
            4 => execute_check_only::<4>(&export, &args),
            8 => execute_check_only::<8>(&export, &args),
            16 => execute_check_only::<16>(&export, &args),
            32 => execute_check_only::<32>(&export, &args),
            64 => execute_check_only::<64>(&export, &args),
            128 => execute_check_only::<128>(&export, &args),
            _ => unreachable!("unsupported limb profile"),
        }
    } else {
        match limbs {
            2 => execute_zinc_2(&export, &args),
            4 => execute_zinc_4(&export, &args),
            8 => execute_zinc_8(&export, &args),
            16 => execute_zinc_16(&export, &args),
            32 => execute_zinc_32(&export, &args),
            64 => execute_zinc_64(&export, &args),
            128 => execute_zinc_128(&export, &args),
            _ => unreachable!("unsupported limb profile"),
        }
    };

    emit_progress(&args, "finish", "finish", None, None, "runner finished");

    if args.json {
        println!("{}", serde_json::to_string_pretty(&report).unwrap());
    } else {
        print_human_report(&export, &report, &args);
    }
}
