# Practical option reference

This file is the complete practical reference for public command-line options in the package.  Start with the high-level `folzinc` command unless you are scripting the lower-level tools directly.

The basic pattern is:

```bash
./zkfol_zinc_adapter/folzinc <command> [options]
```

For one-command help in a terminal, run:

```bash
./zkfol_zinc_adapter/folzinc <command> --help
./zkfol_zinc_adapter/folzinc options
```

## Option conventions used throughout

| Option | Practical meaning |
| --- | --- |
| `--check` / `--no-check` | Run or skip the pure-Python exported-relation checker after JSON export. Leave this enabled while developing. |
| `--check-only` | Do not produce a Zinc proof. Check the exported integer relation using the Rust runner and stop. Useful for large examples or debugging. |
| `--pretty` | Write indented JSON. Use for small files you want to read. Avoid for very large benchmark files unless readability matters. |
| `--quiet` | Reduce status output. Use in scripts when you only need paths or final results. |
| `--repeat N` | Run Zinc prove/verify `N` times and average timings. Use `1` while debugging, `3` or more for rough benchmarks. |
| `--progress` / `--no-progress` | Enable or suppress the heartbeat for long Cargo/Zinc runs. Progress is on by default in high-level run commands. |
| `--progress-interval SEC` | Seconds between heartbeat lines. Increase to reduce log volume; decrease to watch long jobs closely. |
| `--int-limbs N` | Request a maximum Zinc signed-integer profile `Int<N>`, where `N` is one of `auto`, `2`, `4`, `8`, `16`, `32`, `64`, `128`. High-level commands downshift oversized requests to the smallest safe profile unless strict mode is used. |
| `--strict-int-limbs`, `--force-int-limbs` | Force the exact `--int-limbs` value. Use only when you deliberately want to benchmark a larger profile; it can make tiny cases spend a long time in random-field setup. |
| `--max-single-allocation-gib N` | Safety cap for the largest dense Zinc allocation predicted by resource preflight. Default is 128 GiB. |
| `--allow-large`, `--allow-large-zinc`, `--run-large` | Override the resource-preflight safety gate. Use only on a machine where the estimated memory use is intentional. |
| `--runner PATH` | Use a non-default Rust runner directory or Cargo.toml. Usually unnecessary. |
| `--cargo-run` | Force `cargo run --release` even if a current built release binary exists. Useful after editing Rust or while diagnosing build/link problems. |

### Variables, degree, and bit-bound outputs

Commands that inspect or run an export report:

| Field | Practical meaning |
| --- | --- |
| `scalar z variables` / `variables` | Public input coordinates + the constant-one coordinate + private witness variables. |
| `constraints` | Exported R1CS/CCS rows before Zinc padding. |
| `degree` | Declared CCS/R1CS degree. This adapter emits `<A,z>*<B,z>=<C,z>`, so the declared degree is 2. |
| `simplified degree` / `simp≤` | Degree after fixing public inputs and the constant-one coordinate. Compact Fibonacci rows may simplify to degree 1. |
| `bit_bound_delta` / `bit_bound` | Largest absolute bit length among public inputs, private witness values, and integer CCS coefficients materialised by the adapter. |

This is the most compact answer to “what Zinc constraint is produced for this target use case?”

### `--int-limbs` in plain language

Zinc's current Rust proof path is compiled for fixed implementation profiles: `Int<2>`, `Int<4>`, ..., `Int<128>`.  In this adapter, `--int-limbs` controls the fixed-width representation profile used by the proof-of-concept runner; it is not an abstract security request to choose a prime larger than every integer.  Larger profiles support larger materialised exact integers, but also make Zinc's sampled random field larger.  That setup cost can dominate small examples.

High-level `folzinc` commands therefore interpret `--int-limbs N` as a **maximum** by default:

```bash
./zkfol_zinc_adapter/folzinc bench fib --n 3 --run --int-limbs 128
```

The command above proves exact `F_3 = 2`, so the wrapper should downshift to `Int<2>` and print a limb-profile note.  To force the oversized profile exactly, add `--strict-int-limbs`.

For large exact integers such as `F_10000`, the wrapper still selects `Int<128>` in the current adapter when the exported exact constants/witness values need that representation.  This is an implementation-profile choice, not a mathematical requirement that the sampled prime exceed the value.

## Top-level `folzinc` options

| Option | Practical meaning |
| --- | --- |
| `--version` | Print the Python adapter version and exit. |

## `folzinc setup`

Creates or updates the virtual environment and installs both `zkfol_reference` and `zkfol_zinc_adapter` in editable mode.

| Option | Practical meaning |
| --- | --- |
| `--reference DIR` | Path to the sibling `zkfol_reference` checkout. Default is `../zkfol_reference` relative to the adapter. |
| `--venv DIR` | Virtual environment directory. Default is `.venv` in the project parent, or `$FOLZINC_VENV` if set. |
| `--no-upgrade-pip` | Skip the `pip setuptools wheel` upgrade step. Useful in locked-down Python environments. |
| `--dev` | Also install development requirements, currently pytest. Use before running `folzinc test`. |
| `--system-site-packages` | Create the venv with access to system Python packages. Useful on managed systems with preinstalled dependencies. |
| `--no-build-isolation` | Pass `--no-build-isolation` to editable installs. Useful when build isolation is unavailable or undesirable. |
| `-h`, `--help` | Show setup-specific help. |

Environment overrides recognised by the wrapper:

| Variable | Practical meaning |
| --- | --- |
| `FOLZINC_VENV` | Default venv path used by the shell wrapper. |
| `FOLZINC_REFERENCE` | Default `zkfol_reference` path used by setup. |
| `FOLZINC_PYTHON` | Python executable used to create the venv, for example `python3.12`. |

## `folzinc doctor`

Checks the project layout, Python imports, Cargo availability, and runner paths.

| Option | Practical meaning |
| --- | --- |
| `--runner PATH` | Check a non-default runner directory or Cargo.toml. |
| `--build` | Also run `cargo build --release` for the runner. |
| `--strict` | Return nonzero if optional pieces such as Cargo are missing. Without this, missing Cargo is reported but export/check-only workflows can still be usable. |
| `--quiet` | Do not echo the cargo command during `--build`. |

## `folzinc examples`

Lists the bundled examples and benchmark suites. It has no options.

## `folzinc options` / `folzinc option-reference`

Prints this file. It has no options.

## `folzinc export`

Exports one example to Zinc-compatible signed integer CCS/R1CS JSON without running Zinc.

```bash
./zkfol_zinc_adapter/folzinc export power --power-base 2 --power-exponent 8 --public-final --out out/power_2_8.json
```

| Argument or option | Practical meaning |
| --- | --- |
| `example` / `--example NAME` | Optional positional example name; `--example` is an equivalent alias for users copying commands from `run`. Choices: `power`, `standard-power`, `standard`, `efficient`, `efficient-power`, `factorial`, `fibonacci`, `fib`, `sk`, `sk-combinator`, `all`. Default is `power`. |
| `--out PATH` | JSON output path, or output directory when exporting `all`. |
| `--check` / `--no-check` | Run or skip the pure-Python relation checker after export. Default: check. |
| `--pretty` | Write indented JSON. Useful for small files. |
| `--explain` | Print a detailed explanation of the exported relation. |
| `--public-final` | Add constraints binding final input/output cells as public inputs where supported. Use this for benchmarkable public claims such as `2^32 = 4294967296`. |
| `--include-sympy` | Include textual SymPy `mkQ` expressions in the JSON. Useful for auditing small examples; can make files large. |
| `--quiet` | Reduce exporter output. |
| `--power-base N` | Base for the standard recursive power example. |
| `--power-exponent N` | Exponent for the standard recursive power example. |
| `--efficient-base N` | Base for the repeated-squaring power example. |
| `--efficient-exponent N` | Exponent for the repeated-squaring power example. |
| `--factorial-n N` | `n` for the factorial example. |
| `--fibonacci-n N` | `n` for the small generic Fibonacci example. This is not the large exact benchmark suite. |

## `folzinc explain`

Explains one or more exported JSON files.

| Argument or option | Practical meaning |
| --- | --- |
| `paths` | Exported JSON file(s) to explain. |
| `--compact` | Print a shorter summary. |
| `--no-witness-preview` | Suppress witness row previews. Useful for large files. |

## `folzinc check`

Runs the pure-Python relation checker on exported JSON files. This does not invoke Rust or Zinc.

| Argument or option | Practical meaning |
| --- | --- |
| `paths` | Exported JSON file(s) to check. |
| `--quiet` | Print only failures. |

## `folzinc estimate` / `folzinc preflight` / `folzinc resources`

Estimates the practical constraint shape — scalar variables, declared/simplified degree, and bit-bound delta — plus padded Zinc dimensions, selected limb profile, and large dense allocations before running Zinc.

| Argument or option | Practical meaning |
| --- | --- |
| `paths` | Exported JSON file(s) to estimate. |
| `--int-limbs N` | Maximum integer profile to consider. Oversized requests are downshifted unless strict mode is supplied. |
| `--strict-int-limbs`, `--force-int-limbs` | Estimate exactly the requested `--int-limbs` profile. |
| `--max-single-allocation-gib N` | Safety cap used to decide whether the run would be refused. |
| `--allow-large`, `--allow-large-zinc`, `--run-large` | Report estimates without marking large cases as skipped. |
| `--strict` | Return nonzero if any input would be skipped by the safety gate. Useful in CI. |

## `folzinc inspect` / `folzinc show` / `folzinc matrix`

Shows the concrete claim, Zinc constraint shape, witness matrix preview, and optional CCS/R1CS row preview for exported JSON.

| Argument or option | Practical meaning |
| --- | --- |
| `paths` | Exported JSON file(s) to inspect. |
| `--matrix` / `--no-matrix` | Show or suppress the finite FOL witness matrix. Default: show it. |
| `--constraints` | Also show an abbreviated preview of CCS/R1CS rows. |
| `--matrix-head N` | Number of first witness-matrix columns to show. |
| `--matrix-tail N` | Number of last witness-matrix columns to show. |
| `--constraint-head N` | Number of first CCS/R1CS rows to show. |
| `--constraint-tail N` | Number of last CCS/R1CS rows to show. |
| `--full-matrix` | Print every witness-matrix column. Safe for small examples only. |
| `--full-constraints` | Print every CCS/R1CS row. Can be extremely large. |

## `folzinc build`

Builds the Rust/Zinc runner in release mode.

| Option | Practical meaning |
| --- | --- |
| `--runner PATH` | Runner directory or Cargo.toml to build instead of the bundled runner. |
| `--quiet` | Do not echo the cargo command before running it. |

## `folzinc run` / `folzinc prove`

Runs Zinc on an existing exported file, or exports an example first and then runs Zinc.

```bash
./zkfol_zinc_adapter/folzinc run --input out/power_2_8.json --repeat 3
./zkfol_zinc_adapter/folzinc run --example efficient --efficient-base 2 --efficient-exponent 32 --public-final --repeat 3
```

| Argument or option | Practical meaning |
| --- | --- |
| `input_pos` | Optional positional shorthand for `--input`. |
| `--input PATH` | Existing exported JSON to run. |
| `--example NAME` | Example to export first when `--input` is not supplied. Same names as `folzinc export`. |
| `--out PATH` | JSON path to write when exporting first. |
| `--repeat N` | Number of prove/verify repetitions to average. |
| `--check-only` | Run only the Rust local integer relation check; skip proof generation and verification. |
| `--int-limbs N` | Maximum Zinc integer profile. See the `--int-limbs` section above. |
| `--strict-int-limbs`, `--force-int-limbs` | Force the exact requested limb profile. |
| `--json` | Print machine-readable JSON from the Rust runner instead of the human report. |
| `--runner PATH` | Use a non-default Rust runner directory or Cargo.toml. |
| `--cargo-run` | Force `cargo run --release` instead of a previously built release binary. |
| `--check` / `--no-check` | When exporting first, run or skip the pure-Python checker. |
| `--pretty` | When exporting first, write indented JSON. |
| `--explain` | When exporting first, print the detailed export explanation before running Zinc. |
| `--public-final` | When exporting first, bind the final claim as public inputs where supported. |
| `--include-sympy` | When exporting first, include textual SymPy `mkQ` expressions. Use only for small/auditing cases. |
| `--quiet` | Reduce wrapper status output. |
| `--progress` / `--no-progress` | Enable or suppress the heartbeat. |
| `--progress-interval SEC` | Seconds between heartbeat lines. |
| `--max-single-allocation-gib N` | Refuse proof runs whose predicted largest dense allocation exceeds this cap. |
| `--allow-large`, `--allow-large-zinc`, `--run-large` | Override the resource-preflight safety gate. |
| `--power-base N`, `--power-exponent N`, `--efficient-base N`, `--efficient-exponent N`, `--factorial-n N`, `--fibonacci-n N` | Example input overrides used only when exporting first. |

## `folzinc demo`

Guided small example. By default it exports and checks a public exact-integer `2^4 = 16` instance and shows the witness matrix.

| Option | Practical meaning |
| --- | --- |
| `--example NAME` | Small example to demonstrate. Default is `power`. |
| `--out PATH` | Demo JSON output path. Default is chosen under `out/`. |
| `--zinc` | After export/check/inspect, invoke Zinc. |
| `--repeat N` | Number of prove/verify repetitions when `--zinc` is supplied. |
| `--check-only` | With `--zinc`, run only the Rust local relation check. |
| `--int-limbs N` | Maximum Zinc integer profile. Usually leave unset for the demo. |
| `--strict-int-limbs`, `--force-int-limbs` | Force the exact requested limb profile. |
| `--json` | With `--zinc`, print machine-readable JSON from the Rust runner. |
| `--runner PATH` | Use a non-default Rust runner directory or Cargo.toml. |
| `--cargo-run` | Force `cargo run --release` instead of a current release binary. |
| `--public-final` / `--no-public-final` | Bind or do not bind the final claim as public inputs. Default: bind it. |
| `--matrix` / `--no-matrix` | Show or suppress the witness-matrix preview. |
| `--constraints` | Also show first/last CCS/R1CS rows. |
| `--matrix-head N`, `--matrix-tail N` | Control witness-matrix preview length. |
| `--constraint-head N`, `--constraint-tail N` | Control constraint preview length. |
| `--full-matrix` | Print every witness-matrix column. |
| `--full-constraints` | Print every CCS/R1CS row; can be large. |
| `--full-explain` | Print the long field-by-field explanation during the demo. |
| `--progress` / `--no-progress` | Enable or suppress Zinc-run heartbeat. |
| `--progress-interval SEC` | Seconds between heartbeat lines. |
| `--max-single-allocation-gib N` | Resource-preflight cap. |
| `--allow-large`, `--allow-large-zinc`, `--run-large` | Override the resource-preflight safety gate. |
| Example input overrides | `--power-base`, `--power-exponent`, `--efficient-base`, `--efficient-exponent`, `--factorial-n`, `--fibonacci-n`. |

## `folzinc bench`

Exports benchmark suites and optionally runs Zinc on the selected cases.

```bash
./zkfol_zinc_adapter/folzinc bench power --skip-256 --power-profile efficient --run --repeat 3
./zkfol_zinc_adapter/folzinc bench fib --n 10000 --run --repeat 1 --int-limbs 128
```

| Argument or option | Practical meaning |
| --- | --- |
| `suite` | Benchmark suite: `power`, `fib`, `fibonacci`, or `all`. |
| `--out DIR` | Root directory for exported benchmark JSON and input summaries. |
| `--results DIR` | Directory for run JSONL and benchmark summaries. |
| `--run` | Invoke Zinc after exporting selected inputs. Without this, only export/check/summarise inputs. |
| `--repeat N` | Number of prove/verify repetitions for each selected case. |
| `--check-only` | With `--run`, run only the Rust local integer relation check. |
| `--int-limbs N` | Maximum Zinc integer profile. See the limb-profile section above. |
| `--strict-int-limbs`, `--force-int-limbs` | Force the exact requested limb profile. |
| `--runner PATH` | Use a non-default Rust runner directory or Cargo.toml. |
| `--cargo-run` | Force `cargo run --release` instead of a current release binary. |
| `--n N` | Fibonacci index for the exact-Fibonacci suite. Repeat for multiple values. Default suite values are `100`, `1000`, `10000`. |
| `--skip-10000` | Omit `F_10000` from the Fibonacci suite. Useful for quick runs. |
| `--skip-256` | Omit the larger efficient `2^256` power case. Useful for quick power runs. |
| `--skip-standard` | Do not export the naive standard recursive `2^32` case. |
| `--power-profile all|efficient|standard` | Select which power benchmark families to export/run. Prefer `efficient` for routine Zinc timing. |
| `--include-witness-rows` | Include duplicate full witness rows in exact-Fibonacci metadata. Off by default to keep large JSON smaller. |
| `--fib-profile compact|full` | `compact` is the faster exact-Fibonacci default. `full` keeps the older explicit four-row direct trace. |
| `--clean`, `--clean-output` | Remove old generated JSON/CSV/Markdown files in the suite output directory before exporting. Prevents stale-file confusion. |
| `--check` / `--no-check` | Run or skip the pure-Python checker after each export. |
| `--pretty` | Write indented JSON. Avoid for large benchmark files unless needed. |
| `--zkvm-csv PATH` | Optional CSV of external zkVM measurements to include in the generated summary. |
| `--quiet` | Reduce wrapper/exporter output. |
| `--progress` / `--no-progress` | Enable or suppress heartbeat during Zinc runs. |
| `--progress-interval SEC` | Seconds between heartbeat lines. |
| `--max-single-allocation-gib N` | Memory-preflight cap for each selected proof run. |
| `--allow-large`, `--allow-large-zinc`, `--run-large` | Override the memory-preflight safety gate. |

## `folzinc test`

Runs the integrated regression suite.

| Argument or option | Practical meaning |
| --- | --- |
| `paths` | Optional pytest file/directory selection. Leave empty for the whole suite. |
| `--install-dev` | Install `requirements-dev.txt` if pytest is missing. |
| `--cargo` | Include the real `cargo build --release` regression test for the Rust runner. |
| `--zinc-smoke` | Include a tiny real Zinc prove/verify smoke test. Implies the Cargo build test. |
| `--full` | Same as `--cargo --zinc-smoke`. |
| `-k EXPR`, `--keyword EXPR` | Pass a pytest `-k` expression to select tests by name. |
| `-x`, `--fail-fast` | Stop after the first test failure. |
| `-v`, `--verbose` | Verbose pytest output. |
| `-s`, `--show-output` | Do not capture test stdout/stderr. Useful when debugging progress output. |

## `folzinc raw`

Power-user pass-through to lower-level tools.

| Argument | Practical meaning |
| --- | --- |
| `tool` | One of `export`, `explain`, `check`, `bench`, `inspect`. |
| `args` | Remaining arguments are passed unchanged to the selected lower-level tool. |

## Lower-level: `zkfol-zinc-export`

Usually called via `folzinc export` or `folzinc raw export`. Options match the high-level export path:

| Option | Practical meaning |
| --- | --- |
| `--example NAME` | Example to export: `power`, `standard-power`, `efficient`, `efficient-power`, `factorial`, `fibonacci`, `fib`, `sk`, `sk-combinator`, or `all`. |
| `--out PATH` | Output JSON path or directory. |
| `--include-sympy` | Embed textual SymPy `mkQ` expressions for auditing small cases. |
| `--pretty` | Write indented JSON. |
| `--check` | Run the pure-Python checker after export. Lower-level default is off unless supplied. |
| `--public-final` | Add public-final binding constraints where supported. |
| `--quiet` | Print only output paths. |
| `--explain` | Print a fuller explanation of each exported instance. |
| Input overrides | `--power-base`, `--power-exponent`, `--efficient-base`, `--efficient-exponent`, `--factorial-n`, `--fibonacci-n`. |

## Lower-level: `zkfol-zinc-explain`

| Argument or option | Practical meaning |
| --- | --- |
| `paths` | Exported JSON file(s). |
| `--compact` | Shorter summary. |
| `--no-witness-preview` | Do not show witness rows. |

## Lower-level: `zkfol-zinc-check`

| Argument or option | Practical meaning |
| --- | --- |
| `paths` | Exported JSON file(s). |
| `--quiet` | Print only failures. |

## Lower-level: `zkfol-zinc-inspect`

Same display engine as `folzinc inspect`.

| Option | Practical meaning |
| --- | --- |
| `paths` | Exported JSON file(s). |
| `--matrix` / `--no-matrix` | Show or suppress the witness matrix. |
| `--constraints` | Show abbreviated CCS/R1CS rows. |
| `--matrix-head N`, `--matrix-tail N` | Control matrix preview length. |
| `--constraint-head N`, `--constraint-tail N` | Control constraint preview length. |
| `--full-matrix` | Print every matrix column. |
| `--full-constraints` | Print every CCS/R1CS row. |

## Lower-level: `zkfol-zinc-bench export-power`

| Option | Practical meaning |
| --- | --- |
| `--out DIR` | Output root for power benchmark JSON and summaries. |
| `--pretty` | Write indented JSON. |
| `--check` / `--no-check` | Run or skip pure-Python checker after each export. |
| `--skip-256` | Skip efficient `2^256`. |
| `--skip-standard` | Skip naive standard recursive `2^32`. |
| `--power-case all|efficient|standard`, `--power-profile all|efficient|standard` | Select which power profile(s) to export. |
| `--quiet` | Print less exporter output. |

## Lower-level: `zkfol-zinc-bench export-risc0-fib` and aliases

Aliases: `export-fibonacci-exact`, `export-fibonacci`.

| Option | Practical meaning |
| --- | --- |
| `--out DIR` | Output directory for exact Fibonacci benchmark JSON and summaries. |
| `--n N` | Fibonacci index to export. Repeat for several values. Default is `100`, `1000`, `10000`. |
| `--pretty` | Write indented JSON. |
| `--check` / `--no-check` | Run or skip pure-Python checker after each export. |
| `--skip-10000` | Skip the largest bundled exact-integer case. |
| `--include-witness-rows` | Include duplicate full witness rows in metadata. Usually leave off. |
| `--fib-profile compact|full` | Choose compact or older full exact-Fibonacci relation. |
| `--quiet` | Print less exporter output. |

## Lower-level: `zkfol-zinc-bench estimate-fibonacci-generic`

| Option | Practical meaning |
| --- | --- |
| `--n N [N ...]` | Fibonacci index values to estimate. |
| `--out PATH` | Markdown output path for the estimate. |
| `--json` | Print machine-readable JSON instead of writing Markdown. |
| `--quiet` | Suppress status output. |

## Lower-level: `zkfol-zinc-bench run-zinc`

Runs the Rust runner on one or more exported JSON inputs and writes JSONL timing records.

| Argument or option | Practical meaning |
| --- | --- |
| `inputs` | Exported JSON file(s) to run. Shell globs run every matching file; unlike high-level `folzinc bench`, this does not filter stale files for you. |
| `--runner PATH` | Rust runner directory or Cargo.toml. |
| `--cargo-run` | Force `cargo run --release`. |
| `--out PATH` | JSONL output file receiving one record per input. |
| `--repeat N` | Number of prove/verify repetitions per input. |
| `--check-only` | Run only the Rust local integer relation check. |
| `--int-limbs N` | Maximum Zinc integer profile. Downshifted unless strict mode is supplied. |
| `--strict-int-limbs`, `--force-int-limbs` | Force exact limb profile. |
| `--quiet` | Print less wrapper output. |
| `--progress` / `--no-progress` | Enable or suppress heartbeat. |
| `--progress-interval SEC` | Seconds between heartbeat lines. |
| `--max-single-allocation-gib N` | Resource-preflight cap. |
| `--allow-large`, `--allow-large-zinc`, `--run-large` | Override the memory-preflight safety gate. |

## Lower-level: `zkfol-zinc-bench summarize`

| Argument or option | Practical meaning |
| --- | --- |
| `inputs` | Exported JSON input files to summarise. |
| `--runs PATH` | JSONL run data from `run-zinc`. |
| `--zkvm-csv PATH` | Optional direct-comparison zkVM CSV. |
| `--out PATH` | Markdown summary output path. |
| `--csv PATH` | Optional CSV size summary output path. |
| `--quiet` | Suppress status output. |

## Direct Rust runner: `zkfol-zinc-runner`

Most users should call it through `folzinc run` or `folzinc bench`.  Direct invocation is useful for debugging the Rust/Zinc layer.

| Option | Practical meaning |
| --- | --- |
| `--input PATH`, `-i PATH` | Exported JSON file to run. Required. |
| `--check-only` | Check the integer relation and skip Zinc prove/verify. |
| `--repeat N` | Number of prove/verify repetitions. |
| `--json`, `--machine-json` | Print machine-readable JSON report. |
| `--explain` | Print the human-readable report. This is the default unless `--json` is supplied. |
| `--int-limbs N`, `--limbs N` | Exact Rust-runner integer profile request, or `auto`. The direct Rust runner does its own downshift unless strict mode is used. |
| `--strict-int-limbs`, `--force-int-limbs`, `--allow-oversized-limbs` | Force oversized limb profiles instead of downshifting. |
| `--progress` | Emit machine-readable phase markers on stderr. The high-level wrapper turns these into heartbeat lines. |
| `--no-progress` | Do not emit progress markers. |
| `--allow-large` | Override the Rust-side dense-allocation guard. |
| `--max-single-allocation-gib N` | Rust-side dense-allocation guard limit. |
| `--version`, `-V` | Print runner version. Used by the wrapper to avoid stale binaries after upgrades. |
