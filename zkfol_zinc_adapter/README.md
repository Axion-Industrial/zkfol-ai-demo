# zkFOL -> Zinc adapter

This package turns the attached `zkfol_reference` examples into signed integer CCS/R1CS JSON and invokes the public Rust Zinc proof-of-concept on those exported relations.

The user-facing interface is one script:

```bash
./zkfol_zinc_adapter/folzinc <command> [options]
```

Every public option is documented in one place:

```bash
./zkfol_zinc_adapter/folzinc options
# or read: docs/OPTIONS_REFERENCE.md
```

For command-specific help, use `./zkfol_zinc_adapter/folzinc <command> --help`.

The default demo now uses a deliberately concrete claim and prints the main claim in bold in a real terminal:

```text
Concrete computation: exact integer 2^4 = 16.
```

It exports the FOL witness matrix, checks the reference semantics, shows the concrete witness table, and can then run Zinc.

## One-time setup

Use the same sibling layout as before:

```text
zkfol/
  zkfol_reference/
  zkfol_zinc_adapter/
  .venv/                    created by setup
```

From the parent directory:

```bash
cd /path/to/zkfol
./zkfol_zinc_adapter/folzinc setup
./zkfol_zinc_adapter/folzinc doctor
```

The setup command creates `.venv`, installs `zkfol_reference` and this adapter in editable mode, and leaves global Python untouched.

## Regression tests

The package includes a regression suite for the bugs fixed during development: signed CCS coefficients, Rust/Zinc dispatch, sampled-field relation checks, exact non-modular Fibonacci, stale benchmark files, progress heartbeats, memory preflight, and JSON result collection.

Run the Python regression suite:

```bash
./zkfol_zinc_adapter/folzinc test
```

The default suite does not require Cargo.  To include the Rust runner build regression, use:

```bash
./zkfol_zinc_adapter/folzinc test --cargo
```

To also run a tiny real Zinc prove/verify smoke test, use:

```bash
./zkfol_zinc_adapter/folzinc test --zinc-smoke
```

If pytest is not installed in the venv, either run setup with development requirements or let the test command install them once:

```bash
./zkfol_zinc_adapter/folzinc setup --dev
./zkfol_zinc_adapter/folzinc test
# or
./zkfol_zinc_adapter/folzinc test --install-dev
```

The equivalent environment flags are `FOLZINC_RUN_CARGO_TESTS=1` and `FOLZINC_RUN_ZINC_SMOKE=1`, which are useful for CI.

The old manual venv method still works:

```bash
python3 -m venv .venv
. .venv/bin/activate
python -m pip install -e ./zkfol_reference
python -m pip install -e ./zkfol_zinc_adapter
```

## First run

Run the guided demo:

```bash
./zkfol_zinc_adapter/folzinc demo
```

That does not require Cargo. It exports and checks a small public `2^4 = 16` instance and shows the FOL witness matrix `C`.

Run the same demo through Zinc:

```bash
./zkfol_zinc_adapter/folzinc demo --zinc
```

Show the first and last CCS/R1CS rows too:

```bash
./zkfol_zinc_adapter/folzinc demo --constraints
```

The demo ends with suggested next commands.

## Inspect an exported file

The demo writes a JSON file such as:

```text
out/demo_power_2_4_public.json
```

Inspect it again:

```bash
./zkfol_zinc_adapter/folzinc inspect out/demo_power_2_4_public.json
```

Show both the FOL witness matrix and an abbreviated CCS/R1CS row preview:

```bash
./zkfol_zinc_adapter/folzinc inspect out/demo_power_2_4_public.json --constraints
```

For large matrices, only the beginning and end are printed by default. You can control this:

```bash
./zkfol_zinc_adapter/folzinc inspect out/demo_power_2_4_public.json --matrix-head 3 --matrix-tail 3
./zkfol_zinc_adapter/folzinc inspect out/demo_power_2_4_public.json --full-matrix
```

`--full-constraints` also exists, but it can print a very large amount of text.

## Variables, degree, and bit bound

Normal runs now print a dedicated **Zinc constraint shape** line/section.  This is the short answer to questions such as "for this target use case, how many variables, what degree, and what bit bound does Zinc see?"

The reported values mean:

```text
scalar z variables     public inputs + the constant-one coordinate + private witness entries
constraints            exported R1CS/CCS rows before Zinc power-of-two padding
degree                 declared CCS/R1CS degree; this adapter emits <A,z>*<B,z>=<C,z>, so degree 2
simplified degree      degree after fixing public inputs and the constant-one coordinate; compact Fibonacci rows often simplify to degree 1
bit_bound_delta        largest absolute bit length among public inputs, private witness values, and integer CCS coefficients
```

For example, exact compact `F_1000` reports roughly:

```text
variables=1,002 scalar z entries (1,000 private + 1 public + 1 one);
constraints=1,001; degree=2 CCS/simplified≤1; bit_bound_delta=694 bits; padded_dim≈1,024
```

This is the concrete scalar CCS bridge used by this package.  The paper-level AIR notation separately tracks the number of witness polynomials, public auxiliary rank, index polynomials, hypercube dimension, and a bit-length bound delta.

## Run your own examples

Export and run the standard recursive power example:

```bash
./zkfol_zinc_adapter/folzinc run --example power --power-base 2 --power-exponent 8 --public-final --repeat 3
```

Export and run repeated-squaring power:

```bash
./zkfol_zinc_adapter/folzinc run --example efficient --efficient-base 2 --efficient-exponent 32 --public-final --repeat 3
```

Run an already exported file:

```bash
./zkfol_zinc_adapter/folzinc run --input out/demo_power_2_4_public.json --repeat 3
```

Build the Rust runner explicitly. Rust/Cargo >= 1.85 is required because the runner uses Rust edition 2024:

```bash
./zkfol_zinc_adapter/folzinc build
```

The wrapper checks the release binary version before using it.  If you upgrade the Python package but forget to rebuild the Rust runner, `folzinc` treats the old binary as stale and falls back to `cargo run` with the matching source, printing a note.  Run `folzinc build` after upgrades to restore the faster direct-binary path.


## Long-running Zinc jobs and progress

Long Cargo/Zinc runs now print a heartbeat by default.  This is especially useful for large exact-integer cases such as `F_10000`:

```bash
./zkfol_zinc_adapter/folzinc bench fib --n 10000 --run --repeat 3 --int-limbs 128
```

The heartbeat reports elapsed time, the current coarse phase, completed top-level units, an approximate ETA once enough units have completed, approximate CPU usage, and approximate resident memory for the Cargo/Zinc process tree.  It also shows the separate random-prime setup phase used by Zinc before proving:

```text
[folzinc progress] case=fibonacci_exact_n10000_public | elapsed 12:05 | Zinc prove 1/3 | ... | 3/13 units (23.1%) | ETA estimating | CPU 742.1% | RSS 8.9 GiB | peak RSS 9.4 GiB | procs 7
```

The percentage is deliberately coarse.  The public Zinc proof-of-concept does not expose callbacks from inside one `prove` call, so the wrapper can show that a proof is still running, how much CPU it is using, and how much resident memory its process tree currently holds, but not the exact percentage inside that single proof.  The counted units are the local integer relation check plus, for each repeat, random-field setup, sampled-field relation check, prove, and verify.  Memory is sampled from Linux `/proc`; on non-Linux systems it prints `RSS n/a`.  Use these controls when needed:

```bash
--progress / --no-progress       enable or suppress the heartbeat
--progress-interval 10           print one heartbeat every 10 seconds
```

See `docs/OPTIONS_REFERENCE.md` for all progress-related options and their practical meaning.

The Rust runner also accepts `--progress` directly if you run `cargo run` by hand.  Progress cannot be attached to a process that is already running under an older package; stop that run and restart it with this version to get heartbeat lines.


## Timing fields and verifier-heavy runs

Machine JSON and benchmark summaries now distinguish the main timing phases:

```text
field_setup_ms             sampled random-field setup
field_relation_check_ms    adapter diagnostic field-side relation check
zinc_prove_call_ms         time inside ZincProver::prove
zinc_verify_call_ms        time inside ZincVerifier::verify
measured_iteration_ms      setup + field check + prove call + verify call
prove_ms / verify_ms       legacy aliases for the two Zinc call timings
```

It is possible for `zinc_verify_call_ms` to exceed `zinc_prove_call_ms` in the current public Zinc proof-of-concept. That is not the usual production-SNARK intuition, and it is not an asymptotic claim. It reflects the current implementation path, including verifier-side field mapping, sumcheck verification, Zip/PCS verification, and final constraint-evaluation work. Treat these numbers as research/prototype implementation measurements. See `docs/OUTPUT_GUIDE.md` for details.

## Integer limb profiles

The runner has fixed implementation profiles: `Int<2>`, `Int<4>`, ..., `Int<128>`.  In this package, `--int-limbs` controls the fixed-width Rust/Zinc representation profile used by the current proof-of-concept runner; it is not a clean abstract "choose a prime larger than every integer" security parameter.  High-level `folzinc` commands treat `--int-limbs N` as a maximum by default, not as an unconditional exact width.  If a tiny case such as `F_3` is run with `--int-limbs 128`, the wrapper prints a note and uses the smallest safe profile instead, usually `Int<2>`.  This avoids spending a long time sampling a huge random field before any useful proof work begins.

To force the exact old behaviour, add either alias:

```bash
--strict-int-limbs
# or
--force-int-limbs
```

For `F_10000`, auto-selection still chooses `Int<128>` in the current adapter because the exported exact integer constants/witness values have about 6942 bits and are materialised before field reduction.  This is an implementation limitation of the current runner path, not a mathematical requirement that Zinc's sampled prime exceed the Fibonacci value.  In that case the heartbeat has a separate `Zinc random-prime setup` phase before sampled-field checking/proving.

The full option reference gives a practical explanation of `--int-limbs`, `--strict-int-limbs`, `--force-int-limbs`, and the related resource-preflight flags: `docs/OPTIONS_REFERENCE.md`.

## Resource preflight for large Zinc runs

The current public Zinc proof-of-concept pads CCS dimensions to powers of two and can materialise large dense structures.  This is why the naive `standard_power_2_32_public` benchmark is not a routine "small" proof: it has about 120k constraints and pads to `131072 x 131072`.  In the default `Int<2>/RandomField<4>` profile, the adapter estimates a largest dense allocation of about `768 GiB`, which matches the style of allocator failure reported by Linux as a request for hundreds of GiB.

Since v0.5.7, `folzinc run`, `folzinc demo --zinc`, and `folzinc bench ... --run` print a resource preflight estimate before launching Zinc and refuse runs above the safety limit by default.  The JSON is still exported, and `--check-only` still validates the integer relation without running the Zinc prover/verifier.

Useful commands:

```bash
./zkfol_zinc_adapter/folzinc estimate benchmark_inputs/power/*.json
./zkfol_zinc_adapter/folzinc bench power --skip-256 --run --repeat 3
./zkfol_zinc_adapter/folzinc bench power --skip-256 --power-profile efficient --run --repeat 3
./zkfol_zinc_adapter/folzinc bench power --skip-256 --power-profile standard --run --check-only
```

To override the guard deliberately on a very large-memory machine, add `--allow-large` or its aliases `--allow-large-zinc` / `--run-large`.  You can also change the cap with `--max-single-allocation-gib N`.


## Benchmarks

Power benchmark inputs:

```bash
./zkfol_zinc_adapter/folzinc bench power
./zkfol_zinc_adapter/folzinc bench power --run --repeat 3
```

By default this exports both the naive standard `2^32` case and the efficient repeated-squaring `2^32` case when `--skip-256` is used, but the resource guard will skip the naive standard proof run unless you opt in.  For routine timing, prefer:

```bash
./zkfol_zinc_adapter/folzinc bench power --skip-256 --power-profile efficient --run --repeat 3
```

Exact, non-modular Fibonacci benchmark inputs at the RISC Zero benchmark indices:

```bash
./zkfol_zinc_adapter/folzinc bench fib
./zkfol_zinc_adapter/folzinc bench fib --n 100 --run --repeat 3
```

`folzinc bench` now runs only the cases requested by the current command.  Old JSON files left in `benchmark_inputs/...` are ignored, and the CLI prints a note if it sees them.  To start a suite directory from scratch, add `--clean`:

```bash
./zkfol_zinc_adapter/folzinc bench fib --n 1000 --clean --run --repeat 3 --int-limbs 128
```

For `F_10000`, use a wider integer profile:

```bash
./zkfol_zinc_adapter/folzinc bench fib --n 10000 --run --repeat 3 --int-limbs 128
```

The Fibonacci benchmark here is exact integer arithmetic. It intentionally does not reduce modulo `2^64`. The CLI prints the concrete statement before proving, for example:

```text
Concrete computation: exact non-modular Fibonacci F_10000 = 336447648764317832666216120051075433...794976171121233066073310059947366875 (2090 decimal digits).
```

Since v0.5.5, exact Fibonacci defaults to the faster compact profile.  The public claim is unchanged, but the canonical FOL index and pointer rows are treated as public relation structure instead of private witness variables.  This reduces the direct exact-Fibonacci input from about `5n` constraints and `4n` witness variables to about `n` constraints and `n` witness variables.  To reproduce the older explicit four-row direct trace, pass:

```bash
./zkfol_zinc_adapter/folzinc bench fib --n 10000 --fib-profile full --run --repeat 3 --int-limbs 128
```

The direct exact-Fibonacci claim is encoded as public relation constants in the JSON relation, not as extra Zinc public-input coordinates; this keeps the benchmark claim public while following the current Zinc proof-of-concept's most reliable single-public-input shape.

## What the output means

The important pipeline is:

```text
FOL witness matrix C
  -> direct FOL semantics
  -> beta_F(mkQ_x(<phi>)) checks
  -> signed integer CCS/R1CS rows
  -> Zinc prove/verify
```

The paper describes the same mathematical bridge: FOL syntax is compiled through enriched polynomials and `mkQ`, then evaluated via `beta_F`; well-formed instances become algebraic indexed relations suitable for Zinc. The package keeps the intermediate JSON explicit so the matrices and constraints can be inspected.

A successful Zinc run means:

```text
The exported CCS/R1CS relation was locally checked over the integers,
then checked after reduction to Zinc's sampled random field,
then Zinc produced and verified a proof for that relation.
```

The package is research/prototype benchmarking code. The JSON files include private witnesses for convenience and are not privacy-preserving artefacts by themselves.

## Command map

```bash
./zkfol_zinc_adapter/folzinc setup      # create/update .venv
./zkfol_zinc_adapter/folzinc doctor     # check imports, Cargo, runner location
./zkfol_zinc_adapter/folzinc demo       # guided 2^4=16 demo
./zkfol_zinc_adapter/folzinc options    # complete practical option reference
./zkfol_zinc_adapter/folzinc inspect    # show claim, witness matrix, optional constraints
./zkfol_zinc_adapter/folzinc export     # export JSON only
./zkfol_zinc_adapter/folzinc run        # export if needed, then invoke Zinc
./zkfol_zinc_adapter/folzinc bench      # benchmark input suites
./zkfol_zinc_adapter/folzinc estimate   # predict padded dimensions and large Zinc allocations
./zkfol_zinc_adapter/folzinc check      # pure-Python relation check
./zkfol_zinc_adapter/folzinc explain    # full field-by-field explanation
./zkfol_zinc_adapter/folzinc raw        # pass through to lower-level tools
```

More detail is in:

```text
docs/OPTIONS_REFERENCE.md
docs/COMMAND_REFERENCE.md
docs/PIPELINE.md
docs/OUTPUT_GUIDE.md
docs/BENCHMARKING.md
```
