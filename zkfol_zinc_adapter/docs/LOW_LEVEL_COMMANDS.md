# Low-level command reference

This file preserves the pre-0.5 multi-command instructions for power users. The recommended interface is now `./zkfol_zinc_adapter/folzinc`; see the root README and `docs/COMMAND_REFERENCE.md`.

For a complete practical option reference covering both high-level and lower-level CLIs, see `docs/OPTIONS_REFERENCE.md` or run `./zkfol_zinc_adapter/folzinc options`.


This package is a secondary implementation layer for the attached
`zkfol_reference` prototype. It takes the reference implementation's concrete
first-order logic examples and witness matrices, exports signed integer CCS/R1CS
JSON, and provides a Rust runner that invokes the public Zinc proof-of-concept on
that JSON.

Version **0.5.1** keeps the venv-compatible installation layout, the v0.4.2 Zinc runner fix, and exact non-modular Fibonacci benchmark inputs.  New users should prefer the root `folzinc` command; this file documents the lower-level tools for scripts and power users.

The command `zkfol-zinc-inspect` is also available for printing the concrete claim, witness matrix, and optional CCS/R1CS row previews from an exported JSON file.

## Recommended directory layout

Unzip the original reference implementation and this adapter into the same parent
directory:

```text
zkfol/
  zkfol_reference/
  zkfol_zinc_adapter/
  .venv/                    created by the commands below
```

The adapter imports `zkfol_reference`, so keeping these two trees as siblings is
the least surprising layout and matches the earlier package.

## Install using the original venv workflow

From the parent directory containing both `zkfol_reference` and
`zkfol_zinc_adapter`:

```bash
cd /path/to/zkfol
python3 -m venv .venv
. .venv/bin/activate
python -m pip install -e ./zkfol_reference
python -m pip install -e ./zkfol_zinc_adapter
```

The `pip` commands above run inside `.venv`; they are not a global installation.
This is the same editable-venv workflow as v0.1.x, so existing scripts that expect
`./zkfol_zinc_adapter` should continue to work. If your Python distribution creates
a very minimal venv and complains about missing build tools, run
`python -m pip install -U pip setuptools wheel` inside the activated venv, then rerun
the two editable installs.

A helper script is also provided:

```bash
cd /path/to/zkfol
./zkfol_zinc_adapter/scripts/setup_venv.sh
. .venv/bin/activate
```

## What is being run?

For each bundled example, the reference implementation supplies:

1. a first-order logic predicate `phi`,
2. a finite matrix interpretation/witness `C`, and
3. metadata saying which rows of `C` are private pointer rows.

The adapter checks that the reference direct FOL semantics agrees with the
paper's `beta_F(mkQ_x(<phi>))` evaluation for every finite-model index `x`. In
this semantics, **zero means true**, so a valid witness has every direct/beta
value equal to zero.

The adapter then materialises those checks as an integer R1CS/CCS instance:

- private bit variables for the paper's `B` symbols,
- booleanity constraints for those bits,
- one-hot pointer range constraints,
- lookup constraints tying composed bits `B_i,j,x,nu` to the selected direct row
  bits, and
- arithmetic gates for each `mkQ_x(<phi>) = 0` check.

The Rust runner reads that JSON, reconstructs a Zinc `CCS_Z`, performs a local
integer relation check, pads to Zinc's power-of-two dimensions, runs Zinc prove,
and runs Zinc verify.

This is a clear benchmark bridge, not the paper's expected lowest-overhead native
AIR integration.

## Check the Python side

With the venv activated:

```bash
python -m pytest zkfol_zinc_adapter/tests
zkfol-zinc-export --example power --out /tmp/power.json --pretty --check --explain
zkfol-zinc-explain /tmp/power.json
```

The `--check` flag runs the local Python R1CS checker. The `--explain` flag prints
a readable explanation immediately after export. Without `--explain`, the exporter
prints a compact summary. Use `--quiet` if a script should receive only paths.

## Build and run the Rust/Zinc runner

Install Rust with `rustup` if needed, then build from the runner folder:

```bash
cd /path/to/zkfol/zkfol_zinc_adapter/rust/zkfol-zinc-runner
cargo build --release
```

The runner depends on the public Zinc proof-of-concept through Cargo:

```toml
zinc = { git = "https://github.com/NethermindEth/zinc.git" }
```

Human-readable report, now the default:

```bash
cargo run --release -- --input /tmp/power.json --repeat 3
```

Machine-readable JSON, compatible with the old style of output:

```bash
cargo run --release -- --input /tmp/power.json --repeat 3 --json
```

Local relation check only, without proof generation:

```bash
cargo run --release -- --input /tmp/power.json --check-only
```

## How to read the Rust runner output

The human report is organised around four questions.

### 1. What is being proved?

This section links the exported CCS/R1CS relation back to the FOL example. For
example, `standard_power` proves knowledge of a finite matrix witness whose rows
encode base, exponent, output, and a recursive pointer, and whose columns satisfy
the power predicate for every `x`.

### 2. Did the FOL-to-polynomial semantics agree locally?

The exporter records three checks:

- `direct semantics == beta_F(mkQ_x(<phi>))`: the direct integer FOL semantics and
  symbolic beta evaluator agree;
- `all predicate values are zero`: every quantified `x` satisfies the predicate;
- `pointer range checks pass`: private pointers used in `C_i(C_j(x))` point into
  `1..len(C)`.

These checks are not a SNARK proof by themselves; they certify that the JSON being
handed to Zinc really corresponds to the intended FOL witness.

### 3. What was the CCS/R1CS size?

Important size fields:

| field | meaning |
| --- | --- |
| `constraints_unpadded` | Exported R1CS/CCS rows before Zinc padding. |
| `witness_variables` | Private scalar variables after expanding bits, selectors, lookup products, and arithmetic intermediates. |
| `z_len_unpadded` | Public inputs + constant-one coordinate + private witness. |
| `ccs_m_padded` | Constraint rows after power-of-two padding. |
| `ccs_n_padded` | z-vector length after power-of-two padding. |
| `scalar_variables_unpadded` | Same practical variable count as `z_len_unpadded`: public inputs + one + private witness. |
| `ccs_declared_degree` | Declared CCS/R1CS degree; this adapter emits `<A,z>*<B,z>=<C,z>`, so it is 2. |
| `max_simplified_degree_over_private_witness` | Degree after fixing public inputs and the constant-one coordinate. Compact Fibonacci rows may be effectively linear. |
| `bit_bound_delta` | Largest absolute bit length among public inputs, private witness values, and integer constraint coefficients. |

The constraint breakdown explains where rows come from:

| category | meaning |
| --- | --- |
| `mkq_arithmetic_gates` | Arithmetic gates introduced while evaluating `mkQ_x(<phi>)`. |
| `mkq_zero_checks` | Final zero checks, one per model column `x`. |
| `pointer_range_one_hot_checks` | One-hot checks for private pointers. |
| `pointer_range_value_checks` | Checks tying pointer integer values to selected columns. |
| `pointer_lookup_selector_products` | Multiplication rows for selector/direct-bit products. |
| `pointer_lookup_bit_equalities` | Equalities making composed bits equal selected direct bits. |
| `booleanity_bit_checks` | Boolean constraints for bit and selector wires. |

### 4. What do the timing fields mean?

| field | meaning |
| --- | --- |
| `relation_check_ms` | Local Rust check of the integer CCS relation before Zinc is called. |
| `field_setup_ms` | Average sampled random-field setup time per proof iteration. |
| `field_relation_check_ms` | Average adapter diagnostic check after mapping the integer relation to the sampled field. |
| `zinc_prove_call_ms` | Average time inside the `ZincProver::prove` library call. |
| `zinc_verify_call_ms` | Average time inside the `ZincVerifier::verify` library call. |
| `measured_iteration_ms` | Average of field setup + field relation check + prove call + verify call. |
| `prove_ms` | Legacy alias for `zinc_prove_call_ms`. |
| `verify_ms` | Legacy alias for `zinc_verify_call_ms`. |
| `proved` | `true` when Zinc proof generation and verification both succeeded. |

For example, output like this:

```json
{
  "name": "standard_power",
  "constraints_unpadded": 496,
  "witness_variables": 424,
  "z_len_unpadded": 426,
  "scalar_variables_unpadded": 426,
  "ccs_declared_degree": 2,
  "max_simplified_degree_over_private_witness": 2,
  "bit_bound_delta": 5,
  "ccs_m_padded": 512,
  "ccs_n_padded": 512,
  "relation_check_ms": 0.696388,
  "prove_ms": 5.410067333333333,
  "verify_ms": 75.959139,
  "repeat": 3,
  "proved": true
}
```

means: the exported power example produced 496 unpadded integer constraints, Zinc
padded the rows and z-vector to 512, the local relation check succeeded, and Zinc
generated and verified proofs three times, with the reported averages. In newer
reports, prefer `zinc_prove_call_ms`, `zinc_verify_call_ms`, and
`measured_iteration_ms` over the legacy aliases. A verifier call that is slower
than a prover call is possible in the current Zinc proof-of-concept and should be
reported as such, rather than interpreted as an optimized SNARK asymptotic claim.


## Larger power examples and benchmarking

Version 0.3.0 added a public-claim benchmark path. Use `--public-final` when you
want the statement to be comparable to a zkVM program: for the power examples it
binds the final base, exponent, and output cells to public inputs.

Export individual larger cases:

```bash
zkfol-zinc-export --example efficient --efficient-base 2 --efficient-exponent 32 \
  --public-final --out /tmp/efficient_2_32_public.json --check

zkfol-zinc-export --example efficient --efficient-base 2 --efficient-exponent 256 \
  --public-final --out /tmp/efficient_2_256_public.json --check

zkfol-zinc-export --example power --power-base 2 --power-exponent 32 \
  --public-final --out /tmp/standard_2_32_public.json --check
```

Export the standard power benchmark set and collect Zinc timings:

```bash
zkfol-zinc-bench export-power --out benchmark_inputs/power
zkfol-zinc-bench run-zinc benchmark_inputs/power/*.json --repeat 3 \
  --out benchmark_results/fol_zinc_power_runs.jsonl
zkfol-zinc-bench summarize benchmark_inputs/power/*.json \
  --runs benchmark_results/fol_zinc_power_runs.jsonl \
  --out benchmark_results/FOL_ZINC_POWER_SUMMARY.md
```

For `2^256`, the runner should auto-select a larger integer profile from the JSON
metadata. To force it explicitly:

```bash
zkfol-zinc-bench run-zinc benchmark_inputs/power/efficient_power_2_256_public.json \
  --repeat 3 --int-limbs 16 --out benchmark_results/fol_zinc_2_256.jsonl
```

See [`docs/BENCHMARKING.md`](docs/BENCHMARKING.md) for the direct-comparison
protocol against Jolt, RISC Zero, Cairo, or another zkVM.


## Exact Fibonacci benchmarks for RISC Zero comparison

RISC Zero's documented `cargo bench --bench fib` benchmark computes the 100th,
1000th, and 10000th Fibonacci numbers modulo `2^64`, ten times each, with
separate execution and proving statistics. The FOL-Zinc side in this package
intentionally does **not** match that modulo arithmetic. It exports exact integer
claims at the same indices:

```text
public_n = n
public_output = Fib(n)
Fib(1) = Fib(2) = 1
Fib(k) = Fib(k-1) + Fib(k-2) over the integers
```

The benchmarkable FOL-Zinc profile is a clearly labelled trace-specialised
integer CCS over a four-row finite FOL witness table:

```text
C1(k) = k
C2(k) = Fib(k)
C3(k) = pointer to k-1
C4(k) = pointer to k-2
```

It constrains the base cases, canonical legal pointer rows, every recurrence row,
and public bindings for `n` and the exact final output. This is not the literal
bit-level `mkQ/beta_F` bridge used by the small generic examples; the literal
bridge is still available for small Fibonacci instances, and the benchmark tool
writes a size estimate explaining why it is not the default for `n=1000` or
`n=10000`.

Export exact, non-modular Zinc inputs for the same indices:

```bash
zkfol-zinc-bench export-risc0-fib --out benchmark_inputs/risc0_fib_exact
```

`export-fibonacci` and `export-fibonacci-exact` are aliases for the same command.
The export creates:

```text
benchmark_inputs/risc0_fib_exact/fibonacci_exact_n100_public.json
benchmark_inputs/risc0_fib_exact/fibonacci_exact_n1000_public.json
benchmark_inputs/risc0_fib_exact/fibonacci_exact_n10000_public.json
benchmark_inputs/risc0_fib_exact/fol_zinc_risc0_fib_exact_size_summary.csv
benchmark_inputs/risc0_fib_exact/FOL_ZINC_RISC0_FIB_EXACT_SUMMARY.md
benchmark_inputs/risc0_fib_exact/risc0_fibonacci_reference_notes.csv
benchmark_inputs/risc0_fib_exact/GENERIC_MKQ_FIBONACCI_ESTIMATE.md
```

The package also includes pregenerated exact Fibonacci inputs under `generated/risc0_fibonacci/` so you can run the Zinc side immediately. Regenerate them with the export command above whenever you want fresh JSON from the installed code.

Run Zinc on them as usual:

```bash
zkfol-zinc-bench run-zinc benchmark_inputs/risc0_fib_exact/fibonacci_exact_n*.json \
  --repeat 3 --out benchmark_results/fol_zinc_risc0_fib_exact_runs.jsonl

zkfol-zinc-bench summarize benchmark_inputs/risc0_fib_exact/fibonacci_exact_n*.json \
  --runs benchmark_results/fol_zinc_risc0_fib_exact_runs.jsonl \
  --out benchmark_results/FOL_ZINC_RISC0_FIB_EXACT_WITH_RUNS.md
```

`fibonacci_exact_n10000_public.json` contains the exact `F_10000`, whose final
value has 6,942 bits and 2,090 decimal digits. The updated Rust runner can
auto-select integer profiles up to `--int-limbs 128`; while debugging, run the
local relation check first:

```bash
zkfol-zinc-bench run-zinc benchmark_inputs/risc0_fib_exact/fibonacci_exact_n10000_public.json \
  --check-only --int-limbs 128 \
  --out benchmark_results/fol_zinc_fib10000_check_only.jsonl
```

## Literal generic Fibonacci path

The small generic Fibonacci example remains available:

```bash
zkfol-zinc-export --example fibonacci --fibonacci-n 10 --public-final \
  --out /tmp/fibonacci_generic_10.json --check --explain
```

For `n=1000` and `n=10000`, the generic explicit bit/pointer lookup bridge is
expected to be dominated by private lookup machinery. Use:

```bash
zkfol-zinc-bench estimate-fibonacci-generic --n 100 1000 10000 \
  --out benchmark_inputs/risc0_fib_exact/GENERIC_MKQ_FIBONACCI_ESTIMATE.md
```


## Bundled examples

Regenerate all sample JSON files with the venv activated:

```bash
./zkfol_zinc_adapter/scripts/export_all.sh ./zkfol_zinc_adapter/generated
```

Current generated dimensions for the small generic mkQ/beta examples:

| example | constraints | witness variables | z length | main pointer rows |
| --- | ---: | ---: | ---: | --- |
| `standard_power` | 496 | 424 | 426 | `[4]` |
| `efficient_power` | 1230 | 1080 | 1082 | `[4]` |
| `factorial` | 352 | 300 | 302 | `[3]` |
| `fibonacci` | 600 | 515 | 517 | `[3, 4]` |
| `sk_combinator` | 4722 | 4224 | 4226 | `[6, 7]` |

## Files in the exported JSON

High-level fields:

- `schema`: JSON schema tag, currently `zkfol-zinc-ccs-v2`.
- `description`: one-line description of the example.
- `exposition`: human-readable explanation and field glossary.
- `dimensions`: arity, length, bit width, constraints, witness variables, and z
  length.
- `zkfol`: witness rows and reference semantic checks.
- `ccs`: public inputs, private witness vector, and sparse R1CS rows.
- `constraint_breakdown`: classified row counts.
- `wire_names`: debugging map from z-index to adapter wire name.

The JSON contains the private witness for benchmarking convenience. Do not treat
these JSON files as privacy-preserving artefacts.

## Notes and limitations

- This is research code for benchmarking and auditing the compilation path.
- The adapter uses a CCS/R1CS bridge because the public Zinc proof-of-concept
  exposes a CCS-style Rust API. A native AIR implementation should be smaller.
- The Rust runner automatically chooses a Zinc integer limb profile from the exported JSON. Large exact examples such as `2^256` or `Fib(10000)` require larger limbs than the default tiny examples; pass `--int-limbs 16` or `--int-limbs 128` manually if you want to force the profile.
- The proof is for the exported CCS relation. The mathematical significance comes
  from the exporter preserving the FOL semantics through the `mkQ` and `beta_F`
  checks.
- This is research code, not production cryptography.
