# Benchmarking larger FOL+Zinc examples and zkVM comparisons

This adapter makes the FOL -> `mkQ`/`beta_F` -> integer CCS -> Zinc path measurable.  It also includes a clearly labelled exact-integer Fibonacci benchmark profile for comparison with zkVM Fibonacci loops.

For the full practical explanation of benchmark options such as `--int-limbs`, `--fib-profile`, `--power-profile`, `--allow-large`, and `--max-single-allocation-gib`, see `docs/OPTIONS_REFERENCE.md` or run:

```bash
./zkfol_zinc_adapter/folzinc options
```

There are two benchmark families:

1. **Power examples** use the generic exporter and the explicit bit-level bridge.  With `--public-final`, the statement publicly binds base, exponent, and output.
2. **Exact Fibonacci examples** use a trace-specialised integer CCS for the same Fibonacci witness convention as the FOL reference example.  These are ordinary integer benchmarks, not modulo-`2^64` benchmarks.  The default `compact` profile keeps the Fibonacci value row private and treats canonical index/pointer rows as public relation structure; `--fib-profile full` keeps the older explicit four-row direct trace.

The Fibonacci profile exists because the literal generic `mkQ`/`beta_F` bridge is very large at `n=1000` and `n=10000` when Fibonacci values are kept exact.  The package therefore reports both a runnable exact trace-specialised CCS and a size estimate for the literal bit bridge.

Every run and benchmark summary now reports the practical Zinc constraint shape: scalar variables, declared/simplified degree, and bit-bound delta.  These fields are usually the best one-line answer to questions about the resulting Zinc constraint.

## Power benchmark export

The repeated-squaring example is the most useful direct comparison target for proving `2^n`.

```bash
zkfol-zinc-bench export-power --out benchmark_inputs/power
```

This writes:

```text
benchmark_inputs/power/standard_power_2_32_public.json
benchmark_inputs/power/efficient_power_2_32_public.json
benchmark_inputs/power/efficient_power_2_256_public.json
benchmark_inputs/power/fol_zinc_size_summary.csv
benchmark_inputs/power/FOL_ZINC_SIZE_SUMMARY.md
```

Use `--skip-256` while debugging if you only want the two smaller `2^32` inputs.

For proof timings, the repeated-squaring case is the routine one to run.  The naive standard recursive `2^32` input is intentionally still exported because it is useful as a size/comparison point, but it is a stress test for the current Zinc proof-of-concept.  It pads to `131072 x 131072` and is expected to require hundreds of GiB in dense verifier/prover paths.  Since v0.5.7, benchmark runs skip that proof by default unless you explicitly override the resource guard.

```bash
./zkfol_zinc_adapter/folzinc bench power --skip-256 --power-profile efficient --run --repeat 3
./zkfol_zinc_adapter/folzinc bench power --skip-256 --power-profile standard --run --check-only
./zkfol_zinc_adapter/folzinc estimate benchmark_inputs/power/*.json
```

## Exact Fibonacci benchmark export

RISC Zero documents a simple Fibonacci benchmark at the indices 100, 1000, and 10000.  That RISC Zero benchmark computes the results modulo `2^64`; this package deliberately does **not** match that arithmetic.  It exports exact, non-modular integer Fibonacci claims.  Since v0.5.5 those direct Fibonacci claims are public relation constants inside the JSON relation, while Zinc's public-input vector remains the conservative single `public_zero` coordinate.

```bash
zkfol-zinc-bench export-risc0-fib --out benchmark_inputs/risc0_fib_exact
```

This writes:

```text
benchmark_inputs/risc0_fib_exact/fibonacci_exact_n100_public.json
benchmark_inputs/risc0_fib_exact/fibonacci_exact_n1000_public.json
benchmark_inputs/risc0_fib_exact/fibonacci_exact_n10000_public.json
benchmark_inputs/risc0_fib_exact/fol_zinc_risc0_fib_exact_size_summary.csv
benchmark_inputs/risc0_fib_exact/FOL_ZINC_RISC0_FIB_EXACT_SUMMARY.md
benchmark_inputs/risc0_fib_exact/risc0_fibonacci_reference_notes.csv
benchmark_inputs/risc0_fib_exact/GENERIC_MKQ_FIBONACCI_ESTIMATE.md
```

The public relation-constant statement of `fibonacci_exact_n10000_public.json` is:

```text
claim_n = 10000
claim_fibonacci_n_exact = F_10000
arithmetic = ordinary integers, no modulo reduction
```

The default compact exact profile constrains the private Fibonacci value row:

```text
C2(k) = fib(k)
```

with base cases `fib(1)=fib(2)=1` and recurrence `fib(k)=fib(k-1)+fib(k-2)` for every `k >= 3`.  The structural FOL rows are fixed as public relation structure:

```text
C1(k) = k
C3(k) = pointer to k-1
C4(k) = pointer to k-2
```

This compact profile reduces the direct exact-Fibonacci relation from about `5n` constraints and `4n` witness variables to about `n` constraints and `n` witness variables.  Use `--fib-profile full` to keep the older explicit four-row direct trace with private C1/C2/C3/C4 rows and explicit pointer/index checks.

A smaller run while debugging:

```bash
zkfol-zinc-bench export-risc0-fib --skip-10000 --out benchmark_inputs/risc0_fib_exact_small
```

Or export a single index:

```bash
zkfol-zinc-bench export-risc0-fib --n 1000 --out benchmark_inputs/risc0_fib_exact_1000
```

The high-level `folzinc bench` wrapper tracks the selected inputs and will not run stale JSON files from a previous command.  If the output directory contains older JSONs, it prints a note that they are being ignored.  For a clean benchmark directory, use:

```bash
./zkfol_zinc_adapter/folzinc bench fib --n 1000 --clean --run --repeat 3 --int-limbs 128
```

Low-level commands such as `zkfol-zinc-bench run-zinc benchmark_inputs/risc0_fib_exact/*.json` still do exactly what the shell glob says; narrow the glob or use a fresh directory when you want a single case.

To reproduce the older explicit four-row direct trace:

```bash
zkfol-zinc-bench export-risc0-fib --n 1000 --fib-profile full --out benchmark_inputs/risc0_fib_exact_1000_full
```


### Small runtime optimisation: build once, run the binary

After you have a working Rust toolchain, run:

```bash
./zkfol_zinc_adapter/folzinc build
```

Subsequent `folzinc run` and `folzinc bench ... --run` commands will use the built `target/release/zkfol-zinc-runner` binary directly when it exists and reports the same version as the Python package, instead of going through `cargo run --release` each time.  This does not change proof complexity, but it removes Cargo startup/check overhead and makes repeated benchmark runs cleaner.  If the package has been upgraded and the binary is stale, the wrapper prints a note and falls back to Cargo.  Pass `--cargo-run` to force Cargo explicitly.


### Progress and memory during long runs

`folzinc bench ... --run` prints a heartbeat by default.  The heartbeat is intentionally coarse: Zinc does not expose sub-progress inside a single `prove` call.  It does report elapsed time, the current top-level phase, completed units, a rough ETA after at least one unit completes, CPU usage, and RSS memory for the Cargo/Zinc process tree.

Example:

```text
[folzinc progress] case=fibonacci_exact_n10000_public | elapsed 12:05 | Zinc prove 1/3 | ... | 3/13 units (23.1%) | ETA estimating | CPU 742.1% | RSS 8.9 GiB | peak RSS 9.4 GiB | procs 7
```

The counted units are: local integer relation check, then for each repeat random-field setup, sampled-field relation check, prove, and verify.  `RSS` is current resident memory.  `peak RSS` is the largest value observed by the heartbeat, not a kernel-enforced exact maximum.  On non-Linux systems, or if `/proc` is unavailable, memory may print as `RSS n/a`.

Integer limb note: high-level commands treat `--int-limbs N` as a maximum unless `--strict-int-limbs / --force-int-limbs` is supplied.  This prevents tiny cases from accidentally spending a long time in huge random-field setup.  For example, `--int-limbs 128` on `F_3` is downshifted to `Int<2>` by default; `F_10000` still needs `Int<128>` automatically.

## Resource preflight before proving

Before a proof run, `folzinc` estimates the current Zinc proof-of-concept's padded dimension and largest dense allocation.  This is an operational run-safety estimate, not a cryptographic lower bound.  It exists because the public proof-of-concept can materialise dense structures after power-of-two padding.

```bash
./zkfol_zinc_adapter/folzinc estimate benchmark_inputs/power/*.json
./zkfol_zinc_adapter/folzinc estimate benchmark_inputs/risc0_fib_exact/fibonacci_exact_n10000_public.json --int-limbs 128
```

The same preflight runs automatically for `folzinc run`, `folzinc demo --zinc`, and `folzinc bench ... --run`.  To bypass the guard deliberately, use `--allow-large`, `--allow-large-zinc`, or `--run-large`; to change the limit, use `--max-single-allocation-gib N`.  To force an oversized integer profile exactly, use `--strict-int-limbs / --force-int-limbs`.

## Run Zinc and collect timings

From the adapter root, with Rust/Cargo >= 1.85 available:

```bash
zkfol-zinc-bench run-zinc benchmark_inputs/risc0_fib_exact/*.json \
  --repeat 3 \
  --out benchmark_results/fol_zinc_risc0_fib_exact_runs.jsonl
```

For `F_10000`, the exact output has roughly 6,942 bits.  The runner should auto-select a large integer limb profile from the JSON metadata, but while debugging it is safer to run the relation check first:

```bash
zkfol-zinc-bench run-zinc benchmark_inputs/risc0_fib_exact/fibonacci_exact_n10000_public.json \
  --check-only \
  --int-limbs 128 \
  --out benchmark_results/fol_zinc_fib10000_check_only.jsonl
```

Then run proving:

```bash
zkfol-zinc-bench run-zinc benchmark_inputs/risc0_fib_exact/fibonacci_exact_n10000_public.json \
  --repeat 3 \
  --int-limbs 128 \
  --out benchmark_results/fol_zinc_fib10000_runs.jsonl
```

## Summarise results

```bash
zkfol-zinc-bench summarize benchmark_inputs/risc0_fib_exact/*.json \
  --runs benchmark_results/fol_zinc_risc0_fib_exact_runs.jsonl \
  --out benchmark_results/FOL_ZINC_RISC0_FIB_EXACT_WITH_RUNS.md \
  --csv benchmark_results/fol_zinc_risc0_fib_exact_sizes.csv
```

To include zkVM measurements, fill in `docs/zkvm_result_template.csv` or a copy of it, then pass it to `summarize`:

```bash
zkfol-zinc-bench summarize benchmark_inputs/risc0_fib_exact/*.json \
  --runs benchmark_results/fol_zinc_risc0_fib_exact_runs.jsonl \
  --zkvm-csv docs/zkvm_result_template.csv \
  --out benchmark_results/FOL_ZINC_WITH_ZKVM_COMPARISON.md
```

## Direct comparison protocol

For a fair comparison, record the public arithmetic model next to every result.

Timing caveat: for the current public Zinc proof-of-concept, verifier-call time may exceed prover-call time on these adapter-generated CCS instances. The verifier call performs field-side relation mapping/checking and Zip/PCS verification work that is not yet optimized for the succinct-verifier profile one would expect from a production zk-SNARK. Treat these numbers as implementation measurements.


| Metric | FOL+Zinc field | zkVM field |
| --- | --- | --- |
| relation size | `constraints_unpadded`, `scalar_variables_unpadded`, `ccs_m_padded`, `ccs_n_padded` | cycles, trace rows, segments, or steps |
| degree | `ccs_declared_degree` and `max_simplified_degree_over_private_witness` | machine instruction degree / arithmetisation degree if available |
| bit bound | `bit_bound_delta`, with coefficient/witness/public-input sub-bounds | word size, field size, limb size, or trace value bound |
| prover call time | `zinc_prove_call_ms` (`prove_ms` legacy alias) | proof/prove time |
| verifier call time | `zinc_verify_call_ms` (`verify_ms` legacy alias) | verification time |
| per-iteration measured time | `measured_iteration_ms` | end-to-end per-proof loop if available |
| proof size | not currently emitted by the Zinc runner | proof bytes |
| setup/preprocess | Cargo build excluded; `field_setup_ms` and `field_relation_check_ms` reported separately | report separately if reusable |
| public statement | `benchmark_claim.public_final=true` | same public input/output |
| arithmetic | `exact_arithmetic.modulus = null` for these Fibonacci cases | document `u64`, field, limb, or exact integer model |

Do not place a modulo-`2^64` RISC Zero result and the exact-integer FOL+Zinc result in the same row as though they prove the identical relation.  Use adjacent rows and label them clearly.

## Interpretation caveats

The generic bridge is deliberately clear rather than minimal.  Its largest current cost for pointer-heavy examples is explicit private lookup machinery, which can grow like `length^2 * max_bits` for each pointer row.  The exact Fibonacci benchmark profile is a trace-specialised exact integer CCS intended to make the 100/1000/10000 comparison runnable and informative; it is not a claim that a future native AIR implementation could not be smaller.

## Resource preflight and the standard-power size wall

`folzinc bench power --skip-256 --run` exports both:

```text
efficient_power_2_32_public
standard_power_2_32_public
```

The efficient case is the proof-timing baseline.  The standard recursive case is intentionally much larger because it follows the literal generic bridge more directly.  On the current public Zinc proof-of-concept, large padded CCS dimensions can trigger dense random-field allocations.  The package therefore estimates the padded dimension and largest dense allocation before launching Zinc.

Run the preflight explicitly:

```bash
./zkfol_zinc_adapter/folzinc estimate benchmark_inputs/power/*.json
```

If a case is skipped, the benchmark JSONL records a `skipped-by-resource-preflight` row instead of launching a process that is likely to fail with an allocator error.  Use `--check-only` to validate the exported integer relation, or `--allow-large` to force Zinc on a machine with enough memory.

The default safety cap is controlled by:

```bash
--max-single-allocation-gib 128
```


## Regression checks before benchmarking

Before collecting benchmark numbers on a new checkout, run:

```bash
./zkfol_zinc_adapter/folzinc test
./zkfol_zinc_adapter/folzinc test --cargo
```

For a tiny end-to-end proof smoke test, run:

```bash
./zkfol_zinc_adapter/folzinc test --zinc-smoke
```

These commands catch the regressions seen during development: stale benchmark selection, JSON parser breakage on nested runner output, resource-preflight mistakes, progress heartbeat/RSS reporting, signed integer CCS handling, and Rust/Zinc API dispatch changes.
