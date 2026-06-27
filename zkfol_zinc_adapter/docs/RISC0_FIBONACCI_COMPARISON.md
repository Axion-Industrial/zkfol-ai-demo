# RISC Zero Fibonacci comparison notes

For the practical meaning of benchmark options such as `--n`, `--fib-profile`, `--int-limbs`, and `--strict-int-limbs`, see `docs/OPTIONS_REFERENCE.md` or run `./zkfol_zinc_adapter/folzinc options`.

This package includes exact, non-modular FOL+Zinc Fibonacci inputs at the same
indices used by the documented RISC Zero Fibonacci benchmark: 100, 1000, and
10000.

The important arithmetic distinction is:

| system/profile | public statement | arithmetic |
| --- | --- | --- |
| RISC Zero documented `cargo bench --bench fib` | compute Fibonacci at n = 100, 1000, 10000 | modulo `2^64` |
| FOL+Zinc `export-risc0-fib` | prove public relation constants `n` and exact `F_n` | ordinary integers, no modulo |

The FOL+Zinc statement is therefore not an arithmetic-identical replacement for
the RISC Zero benchmark. It is deliberately a stronger, larger exact-integer
statement at the same indices.

## Generate FOL+Zinc exact inputs

```bash
zkfol-zinc-bench export-risc0-fib --out benchmark_inputs/risc0_fib_exact
```

This writes compact-profile inputs by default:

```text
fibonacci_exact_n100_public.json
fibonacci_exact_n1000_public.json
fibonacci_exact_n10000_public.json
fol_zinc_risc0_fib_exact_size_summary.csv
FOL_ZINC_RISC0_FIB_EXACT_SUMMARY.md
risc0_fibonacci_reference_notes.csv
GENERIC_MKQ_FIBONACCI_ESTIMATE.md
```

## Run FOL+Zinc

Start with check-only for the largest exact integer case:

```bash
zkfol-zinc-bench run-zinc benchmark_inputs/risc0_fib_exact/fibonacci_exact_n10000_public.json \
  --check-only --int-limbs 128 \
  --out benchmark_results/fol_zinc_fib10000_check_only.jsonl
```

Then collect proof timings:

```bash
zkfol-zinc-bench run-zinc benchmark_inputs/risc0_fib_exact/fibonacci_exact_n*.json \
  --repeat 3 \
  --out benchmark_results/fol_zinc_risc0_fib_exact_runs.jsonl
```

## Run RISC Zero locally

Inside a RISC Zero checkout, run:

```bash
cargo bench --bench fib
```

Record the RISC Zero version, host CPU/GPU, feature flags, proof mode, and whether
reported preprocessing/setup is reusable across inputs. Put the resulting numbers
into a copy of `docs/zkvm_result_template.csv` and summarise alongside FOL+Zinc:

```bash
zkfol-zinc-bench summarize benchmark_inputs/risc0_fib_exact/fibonacci_exact_n*.json \
  --runs benchmark_results/fol_zinc_risc0_fib_exact_runs.jsonl \
  --zkvm-csv docs/zkvm_result_template.csv \
  --out benchmark_results/FOL_ZINC_WITH_ZKVM_COMPARISON.md
```

## Included external reference rows

`risc0_fibonacci_reference_notes.csv` and `docs/zkvm_result_template.csv` include
placeholders for the official RISC Zero benchmark and two third-party context rows
from zkbenchmarks.com/Aligned for `N = 10000`. Treat those as context only unless
you reproduce them on the same hardware and software versions used for your
FOL+Zinc run.

## Expected FOL+Zinc exact input sizes

The default compact exporter/checker produces these exact-integer CCS sizes before Zinc padding:

| case | len(C) | constraints | scalar variables | private witness variables | degree | simplified degree | bit-bound delta | exact output digits |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `fibonacci_exact_n100_public` | 100 | 101 | 102 | 100 | 2 | 1 | 69 | 21 |
| `fibonacci_exact_n1000_public` | 1000 | 1001 | 1002 | 1000 | 2 | 1 | 694 | 209 |
| `fibonacci_exact_n10000_public` | 10000 | 10001 | 10002 | 10000 | 2 | 1 | 6942 | 2090 |

These are ordinary-integer values.  The size growth is intentionally different from a machine-word modulo-`2^64` benchmark.  The older explicit four-row direct profile remains available with `--fib-profile full`; its sizes are approximately 500, 5,000, and 50,000 constraints for n=100,1000,10000 respectively.
