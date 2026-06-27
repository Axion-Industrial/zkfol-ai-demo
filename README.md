# FOL-Zinc development bundle

This bundle packages the current FOL-Zinc development state so that colleagues can unpack it, read the paper context, install the reference implementation and adapter together, and run the examples from one top-level command.

## What is included

```text
fol-zinc-development-bundle/
  README.md                 This file.
  setup.sh                  Creates .venv and configures the source-backed environment.
  folzinc                   Top-level command wrapper.
  zkfol_reference/          Reference FOL-to-mkQ/beta implementation from the original zkfol package.
  zkfol_zinc_adapter/       Zinc adapter and Rust runner, version 0.5.14.
  paper/                    Supplied fol-zinc.pdf paper plus extracted text for search.
  notes/                    Development notes, including large-integer/Zinc performance discussion.
  scripts/                  Convenience wrappers for build and smoke tests.
```

The adapter is experimental research software. It is meant to make the FOL-to-Zinc route runnable, inspectable, and benchmarkable; it is not production cryptography.

## One-minute start

From the directory containing this README:

```sh
./setup.sh
./folzinc doctor
./folzinc demo
```

Both `./folzinc` and `./zkfol_zinc_adapter/folzinc` work after the same setup; the top-level wrapper is the recommended entry point for new users.

The default demo runs a small public exact-integer computation and explains the witness matrix and exported constraint shape. To run the Zinc prover/verifier as well:

```sh
./folzinc build
./folzinc demo --zinc
```

The Zinc-backed commands require Rust/Cargo >= 1.85 because the runner uses Rust edition 2024. The Rust runner pins Zinc to the commit recorded in `zkfol_zinc_adapter/rust/zkfol-zinc-runner/Cargo.toml` for reproducible builds. The first build fetches the public Zinc Rust proof-of-concept from GitHub through Cargo, so it needs network access unless Cargo already has the dependencies cached.

## Typical commands

Show what is available:

```sh
./folzinc examples
./folzinc options
./folzinc run --help
./folzinc bench --help
```

Run a concrete power example:

```sh
./folzinc run --example power --power-base 3 --power-exponent 13 --public-final --repeat 1
```

Export and run an exact, non-modular Fibonacci benchmark:

```sh
./folzinc bench fib --n 1000 --run --repeat 3
```

Estimate resource use before proving:

```sh
./folzinc bench fib --n 10000 --clean
./folzinc estimate benchmark_inputs/risc0_fib_exact/fibonacci_exact_n10000_public.json
```

Run the Python regression suite, after installing pytest with `./setup.sh --dev` or in an environment that already has pytest:

```sh
./folzinc test
```

Run the optional Cargo build/proof smoke tests on a machine with Rust/Cargo >= 1.85:

```sh
./folzinc test --cargo
./folzinc test --zinc-smoke
```

## What the system is doing

The paper-level route is:

```text
FOL predicate + finite witness matrix
    -> enriched polynomial syntax
    -> mkQ_x^F polynomial constraints
    -> beta_F evaluation on range-checked witness data
    -> integer CCS/R1CS-style relation
    -> Zinc prove/verify path
```

The adapter exports JSON containing the integer relation and witness, checks it locally, and invokes the Rust Zinc runner. The runner reports the concrete computation, variables, constraints, declared degree, simplified private-witness degree where known, bit bound, padding, local relation-check timing, sampled-field setup/check timing, Zinc prover-call timing, Zinc verifier-call timing, memory heartbeat, and resource estimates.

## Reading the paper material

See `paper/`. This updated bundle includes the supplied `fol-zinc.pdf` file as `paper/fol-zinc.pdf`. A plain-text extraction is also included as `paper/fol-zinc-text-extracted.md` for quick searching, but the PDF is the authoritative paper file.

## Performance caveats

The current route is intentionally explicit and auditable. It is not a hand-optimised native AIR. Some encodings are much larger than others. For example, efficient repeated-squaring power is suitable for routine Zinc runs, while the naive standard power encoding can trigger enormous dense allocations and is skipped by default unless explicitly overridden.

For large exact integers, distinguish implementation representation width from Zinc's mathematical sampled-prime soundness story. The current adapter still has fixed Rust/Zinc integer profiles, and large exact constants can require wide host-side representation. This is an area for further optimization and cryptographic review; see `notes/fol_zinc_large_integer_performance_note.md`.

## Common workflow for colleagues

1. Read this README.
2. Run `./setup.sh` and `./folzinc doctor`. By default, `setup.sh` does not need network access because the top-level wrapper runs directly from the included source trees and vendored SymPy copy. Use `./setup.sh --editable` only if you specifically want editable pip installs.
3. Run `./folzinc demo` to see the small example and matrix/constraint inspection.
4. Run `./folzinc demo --zinc` after `./folzinc build` to test the full Zinc path.
5. Try one benchmark, such as `./folzinc bench fib --n 1000 --run`.
6. Use `./folzinc inspect <json>` and `./folzinc estimate <json>` to understand exported inputs before proving them.
7. Use `./folzinc options` for the complete option reference.

## Troubleshooting

If `./folzinc` says the environment is missing, rerun:

```sh
./setup.sh
```

If Zinc commands fail because the release binary is stale, rebuild:

```sh
./folzinc build
```

If a benchmark is skipped due to estimated memory, inspect it first:

```sh
./folzinc estimate path/to/input.json
```

Then use a smaller/efficient profile, or deliberately override with `--allow-large` only if the machine has enough memory.

## File provenance

- `zkfol_reference/` is the reference implementation source used by the adapter.
- `zkfol_zinc_adapter/` is the current adapter package, version 0.5.14.
- `paper/fol-zinc.pdf` is the supplied paper PDF included in this updated bundle.
- `notes/` contains selected development notes from this conversation.

