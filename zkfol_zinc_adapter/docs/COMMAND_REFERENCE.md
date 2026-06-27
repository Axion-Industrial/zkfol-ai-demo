# `folzinc` command reference

Use one front-door script from the project parent directory:

```bash
./zkfol_zinc_adapter/folzinc <command> [options]
```

This file gives common command patterns.  For the complete practical explanation of every public option, use:

```bash
./zkfol_zinc_adapter/folzinc options
# or read docs/OPTIONS_REFERENCE.md
```

## Naive-user path

```bash
./zkfol_zinc_adapter/folzinc setup
./zkfol_zinc_adapter/folzinc doctor
./zkfol_zinc_adapter/folzinc options
./zkfol_zinc_adapter/folzinc demo
./zkfol_zinc_adapter/folzinc demo --zinc
```

The default demo proves the concrete public claim `2^4 = 16` using the standard recursive power FOL witness. It prints the concrete claim, semantic checks, the finite FOL witness matrix `C`, and next commands.

## Inspection commands

```bash
./zkfol_zinc_adapter/folzinc inspect out/demo_power_2_4_public.json
./zkfol_zinc_adapter/folzinc inspect out/demo_power_2_4_public.json --constraints
```

Useful options:

```bash
--matrix / --no-matrix       show or suppress the FOL witness matrix
--constraints                also show first/last CCS/R1CS rows
--matrix-head N              first N witness columns to print
--matrix-tail N              last N witness columns to print
--constraint-head N          first N CCS rows to print
--constraint-tail N          last N CCS rows to print
--full-matrix                print all witness columns
--full-constraints           print all CCS rows; can be huge
```

Aliases:

```bash
folzinc show ...
folzinc matrix ...
```

These aliases call the same `inspect` command.

## Export JSON without running Zinc

```bash
./zkfol_zinc_adapter/folzinc export power --power-base 2 --power-exponent 8 --public-final --out out/power_2_8.json
./zkfol_zinc_adapter/folzinc export efficient --efficient-base 2 --efficient-exponent 256 --public-final --out out/efficient_2_256.json
./zkfol_zinc_adapter/folzinc export factorial --factorial-n 6 --public-final --out out/factorial_6.json
./zkfol_zinc_adapter/folzinc export fibonacci --fibonacci-n 8 --public-final --out out/fibonacci_8.json
./zkfol_zinc_adapter/folzinc export sk --out out/sk.json
```

The example may be supplied either positionally (`folzinc export power`) or as `--example power`. Add `--explain` for a long field-by-field explanation during export. Add `--include-sympy` to embed the textual SymPy `mkQ` expressions for auditing small cases.

## Run Zinc

Run an existing export:

```bash
./zkfol_zinc_adapter/folzinc run --input out/power_2_8.json --repeat 3
```

Export first, then run Zinc:

```bash
./zkfol_zinc_adapter/folzinc run --example power --power-base 2 --power-exponent 8 --public-final --repeat 3
```

Useful options:

```bash
--repeat N          average prove/verify over N runs
--check-only        do only the Rust local integer relation check
--int-limbs N       request a maximum Zinc integer limb profile; oversized requests are downshifted
--strict-int-limbs / --force-int-limbs   force the exact --int-limbs value, even when a smaller profile is sufficient
--json              emit machine-readable JSON from the Rust runner
--runner DIR        use a non-default Rust runner directory
--cargo-run         force cargo run even if a current built target/release binary exists
--progress          show elapsed time, coarse percentage, ETA estimate, CPU usage, and RSS memory
--no-progress       suppress the progress heartbeat
--progress-interval N  seconds between heartbeat lines
```


## Variables, degree, and bit bound

To answer "what does Zinc see for this case?", use any of:

```bash
./zkfol_zinc_adapter/folzinc inspect out/demo_power_2_4_public.json
./zkfol_zinc_adapter/folzinc explain out/demo_power_2_4_public.json
./zkfol_zinc_adapter/folzinc estimate out/demo_power_2_4_public.json
```

The reported `scalar z variables` are public inputs plus the constant-one coordinate plus private witness entries.  The declared CCS degree is 2 because rows have the R1CS form `<A,z>*<B,z>=<C,z>`.  The simplified degree is the degree after fixing public inputs and the constant-one coordinate.  `bit_bound_delta` is the largest absolute bit length among materialised public input values, private witness values, and integer constraint coefficients.

## Resource estimates

```bash
./zkfol_zinc_adapter/folzinc estimate benchmark_inputs/power/*.json
./zkfol_zinc_adapter/folzinc preflight benchmark_inputs/power/*.json --strict
```

This reports the practical constraint shape (scalar variables, declared/simplified degree, and bit-bound delta) as well as the predicted padded Zinc dimension, selected integer/random-field profile, random-field bit length, largest dense allocation, and rough peak estimate.  If `--int-limbs` is larger than the relation needs, the estimate uses the smaller safe profile unless `--strict-int-limbs / --force-int-limbs` is supplied. The same preflight is run automatically by `folzinc run`, `folzinc demo --zinc`, and `folzinc bench ... --run`.

```bash
--check-only                    skip proving and verify only the exported relation
--allow-large / --allow-large-zinc / --run-large
                                 override the safety gate
--max-single-allocation-gib N   change the default large-allocation limit
```

## Benchmarks

Power inputs:

```bash
./zkfol_zinc_adapter/folzinc bench power
./zkfol_zinc_adapter/folzinc bench power --run --repeat 3
./zkfol_zinc_adapter/folzinc bench power --skip-256 --run --repeat 3
./zkfol_zinc_adapter/folzinc bench power --skip-256 --power-profile efficient --run --repeat 3
./zkfol_zinc_adapter/folzinc estimate benchmark_inputs/power/*.json
```

`standard_power_2_32_public` is exported for comparison and local checking, but it is a resource stress test for the current Zinc proof-of-concept.  It pads to `131072 x 131072`, so the default run guard skips it rather than allowing an opaque allocator failure.  Use `--check-only` for semantics validation or `--allow-large` only on a machine where a hundreds-of-GiB allocation is intentional.

Exact, non-modular Fibonacci inputs:

```bash
./zkfol_zinc_adapter/folzinc bench fib
./zkfol_zinc_adapter/folzinc bench fib --n 100 --run --repeat 3
./zkfol_zinc_adapter/folzinc bench fib --n 10000 --run --repeat 3 --int-limbs 128
```

The bundled Fibonacci benchmark uses ordinary exact integers, not RISC Zero's documented modulo-`2^64` Fibonacci arithmetic.  The main concrete claim is printed before proving and is bolded in a real terminal.  Long benchmark runs show a progress heartbeat by default, including sampled random-field setup, CPU, and RSS memory when available.  For a quieter run, add `--no-progress`; for fewer status lines, add `--progress-interval 30`.

When you select a subset, for example `--n 1000` or `--power-profile efficient`, the wrapper explains and runs only the files selected by that command.  Older JSON files left in the output directory are ignored.  Add `--clean` or `--clean-output` to remove old generated JSON/CSV/Markdown files before exporting.

Exact Fibonacci defaults to `--fib-profile compact`, which keeps only the Fibonacci value row private and treats canonical index/pointer rows as public relation structure.  This is much faster for `F_10000`.  To use the older explicit four-row direct trace, add `--fib-profile full`.


## Regression tests

```bash
./zkfol_zinc_adapter/folzinc test
./zkfol_zinc_adapter/folzinc test --cargo
./zkfol_zinc_adapter/folzinc test --zinc-smoke
./zkfol_zinc_adapter/folzinc test -k stale -x -v
```

Default `folzinc test` runs the Python regression suite only.  It covers exporter semantics, exact non-modular Fibonacci, stale benchmark-file filtering, resource preflight, oversized limb downshifting, stale Rust binary detection, progress heartbeat formatting including RSS memory, JSONL result collection, and Rust-source contracts.

`--cargo` sets `FOLZINC_RUN_CARGO_TESTS=1` and adds a real `cargo build --release` check for the Rust runner.  `--zinc-smoke` sets both `FOLZINC_RUN_CARGO_TESTS=1` and `FOLZINC_RUN_ZINC_SMOKE=1`, builds the runner, exports a tiny `2^4 = 16` input, and asks Zinc to prove and verify it once.

Useful options:

```bash
--install-dev        install requirements-dev.txt if pytest is missing
--cargo              include the Cargo build regression
--zinc-smoke         include a tiny real Zinc prove/verify smoke test
--full               same as --cargo --zinc-smoke
-k EXPR              pass a pytest -k expression
-x                   stop on first failure
-v                   verbose pytest output
-s                   show test stdout/stderr
```

## Checking and explaining

Pure-Python relation check:

```bash
./zkfol_zinc_adapter/folzinc check out/power_2_8.json
```

Long explanation:

```bash
./zkfol_zinc_adapter/folzinc explain out/power_2_8.json
./zkfol_zinc_adapter/folzinc explain --compact out/power_2_8.json
```

## Power-user pass-through

The older lower-level CLIs remain available:

```bash
zkfol-zinc-export
zkfol-zinc-explain
zkfol-zinc-check
zkfol-zinc-inspect
zkfol-zinc-bench
```

The wrapper can pass through to them:

```bash
./zkfol_zinc_adapter/folzinc raw export --example power --out out/raw.json --check
./zkfol_zinc_adapter/folzinc raw inspect out/raw.json --constraints
```
