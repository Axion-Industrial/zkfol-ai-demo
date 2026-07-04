# Performance baseline (2026-07-04)

This is the reference point that all future performance work diffs against.
Every row below is a real, verified proof (prove + verify both succeeded)
measured on this machine, except the explicitly refused row.

Environment: AMD Ryzen 7 5700X (8 cores / 16 threads), Linux, single-threaded
runner (the `parallel` feature is measurably a no-op for these workloads —
102% CPU). Adapter 0.6.0, Rust runner release build, cargo 1.92.0,
Python 3.14.6, Zinc pinned at NethermindEth/zinc rev `0c9ed214`.

## Measured baseline

| case | what is proved | constraints | padded dim | Int/Field profile | prove | verify | prime setup | total/iter | proof size | peak RSS |
| --- | --- | ---: | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| power 2^4 (typed demo) | exact 2^4 = 16 | 163 | 256 | Int<2> / 256-bit | 3.62 ms | 28.2 ms | 0.51 ms | 32.8 ms | 1.16 MiB | 14.1 MiB |
| fib n=100 (exact, 69-bit output) | exact F_100, all 21 digits | 101 | 128 | Int<2> / 256-bit | 3.03 ms | 13.6 ms | 0.54 ms | 17.4 ms | 684 KiB | 8.4 MiB |
| fib n=1000 (exact, 694-bit output) | exact F_1000, all 209 digits | 1,001 | 1,024 | Int<16> / 2048-bit | 234 ms | 4.69 s | 2.33 s | 7.32 s | 15.9 MiB | 594 MiB |
| fib n=10000 (exact, 6942-bit output) | exact F_10000, all 2090 digits | 10,001 | 16,384 | Int<128> / 16384-bit | — | — | — | **refused**: predicted 768 GiB dense allocation | — | — |
| standard power 2^32 (typed) | exact 2^32 | 4,755 | 8,192 | Int<2> / 256-bit | 43.7 ms | **17.36 s** | 0.49 ms | 17.42 s | 4.20 MiB | **6.03 GiB** |
| efficient power 2^32 | exact 2^32 | 325 | 512 | Int<2> / 256-bit | 6.03 ms | 61.4 ms | 0.60 ms | 69.3 ms | 1.19 MiB | 32.9 MiB |

Timing figures are the Zinc library calls averaged over `--repeat` (3 for the
small cases, 1 for fib n=1000 and the power suite). Proof size is the
structural estimate now emitted by the runner (`proof_size_bytes_estimate`;
the exact `pcs_proof` byte vector is >99% of it). Peak RSS is the runner
process high-water mark (`VmHWM`).

## External reference (the race)

RISC Zero, Fibonacci n=10000, **mod 2^64** (weaker per-value claim than the
exact-integer rows above): 1.7 s on an NVIDIA RTX A6000; 10.8 s on a 64-core
AMD EPYC 8534P (zkbenchmarks.com / Aligned). RISC Zero verification is
milliseconds and receipts are sub-MiB; our current verify times and proof
sizes above are the gap to close, not just prove time.

## What the baseline says (see ZINC_COST_MODEL.md for derivations)

1. Proving is already fast and scales with nonzeros; it is never the
   bottleneck in any measured row.
2. Verify time and peak RSS scale with padded_dim^2: the verifier
   materializes three dense padded matrices as multilinear-extension tables
   (~12·field_limbs bytes/cell, single-threaded). This is an implementation
   artifact of the Zinc PoC (`DenseMultilinearExtension::from_matrix`), not
   protocol-inherent.
3. The Int/Field pairing is a convention, not a constraint: field width is
   hardwired to 2x integer width, which is why 694-bit Fibonacci values drag
   in a 2048-bit prime (2.33 s of the 7.32 s) and why fib n=10000 is refused.
   Cross-profile pairing (wide Int, small field) is trait-legal in Zinc as
   pinned.
4. Proof size ≈ 1000·sqrt(n)·32·int_limbs bytes: linear in integer width,
   sqrt in circuit size. Fib n=1000's 15.9 MiB is Int<16> tax; the same
   circuit at Int<2> would be ~2 MiB.

## Reproduction

```sh
./setup.sh && ./folzinc build
./folzinc bench fib --n 100 --run --repeat 3
./folzinc bench fib --n 1000 --run --repeat 1
./folzinc bench power --skip-256 --run --repeat 1
./folzinc estimate benchmark_inputs/risc0_fib_exact/fibonacci_exact_n10000_public.json
./zkfol_zinc_adapter/rust/zkfol-zinc-runner/target/release/zkfol-zinc-runner \
  --input out/demo_power_2_4_public.json --repeat 3 --json   # after ./folzinc demo
```

Generated summaries (`benchmark_results/FOL_ZINC_*_SUMMARY.md`) now lead with
a plain-English "Headline results" section reporting the same columns.
