# Performance baseline (2026-07-04)

This is the reference point that all future performance work diffs against.
Every row below is a real, verified proof (prove + verify both succeeded)
measured on this machine, except the explicitly refused row.

Environment: AMD Ryzen 7 5700X (8 cores / 16 threads), Linux, single-threaded
runner (the `parallel` feature is measurably a no-op for these workloads —
102% CPU). Adapter 0.6.0, Rust runner release build, cargo 1.92.0,
Python 3.14.6, Zinc pinned at NethermindEth/zinc rev `0c9ed214`.

## Measured baseline

| case                                 | what is proved                 | constraints | padded dim | Int/Field profile    |   prove |      verify | prime setup |                                      total/iter | proof size |     peak RSS |
|--------------------------------------|--------------------------------|------------:|-----------:|----------------------|--------:|------------:|------------:|------------------------------------------------:|-----------:|-------------:|
| power 2^4 (typed demo)               | exact 2^4 = 16                 |         163 |        256 | Int<2> / 256-bit     | 3.62 ms |     28.2 ms |     0.51 ms |                                         32.8 ms |   1.16 MiB |     14.1 MiB |
| fib n=100 (exact, 69-bit output)     | exact F_100, all 21 digits     |         101 |        128 | Int<2> / 256-bit     | 3.03 ms |     13.6 ms |     0.54 ms |                                         17.4 ms |    684 KiB |      8.4 MiB |
| fib n=1000 (exact, 694-bit output)   | exact F_1000, all 209 digits   |       1,001 |      1,024 | Int<16> / 2048-bit   |  234 ms |      4.69 s |      2.33 s |                                          7.32 s |   15.9 MiB |      594 MiB |
| fib n=10000 (exact, 6942-bit output) | exact F_10000, all 2090 digits |      10,001 |     16,384 | Int<128> / 16384-bit |      —  |           — |           — | **refused**: predicted 768 GiB dense allocation |          — |            — |
| standard power 2^32 (typed)          | exact 2^32                     |       4,755 |      8,192 | Int<2> / 256-bit     | 43.7 ms | **17.36 s** |     0.49 ms |                                         17.42 s |   4.20 MiB | **6.03 GiB** |
| efficient power 2^32                 | exact 2^32                     |         325 |        512 | Int<2> / 256-bit     | 6.03 ms |     61.4 ms |     0.60 ms |                                         69.3 ms |   1.19 MiB |     32.9 MiB |

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

## After width decoupling (Phase 1, 2026-07-04)

The runner now accepts `--field-limbs 4` to pair a wide integer profile with
a 256-bit sampled prime (soundness: eprint 2025/316 Lemma 2.1, a per-instance
bound; see ZINC_COST_MODEL.md §7.1). Caveat: the pinned PoC samples q from a
transcript holding only public inputs — before the witness is committed —
which the Lemma 2.1 counting argument requires (§7.2, reported upstream), so
the guarantee attaches to these numbers only once that ordering is fixed.
A general small-field license is what Zinc+'s improved soundness provides,
not this per-instance bound. Same statements, same machine, measured:

| case                                  | profile              |   prove |  verify | prime setup | total/iter | proof size |  peak RSS | vs baseline |
|---------------------------------------|----------------------|--------:|--------:|------------:|-----------:|-----------:|----------:|------------:|
| fib n=1000 (exact, 694-bit output)    | Int<16> / 256-bit    | 34.3 ms |  820 ms |     11.8 ms |     872 ms |   15.9 MiB |   153 MiB | 8.4× faster |
| fib n=10000 (exact, 6,942-bit output) | Int<128> / 256-bit   |  20.5 s | 235.6 s |      2.8 ms |    257.2 s |  525.6 MiB | 26.96 GiB | was refused (768 GiB predicted at legacy pairing) |

Notes: fib n=10000 is the first completed exact-F_10000 proof in this repo.
Proof size matched the cost-model formula (1000·sqrt(n)·32·N bytes) within
0.25% and peak RSS within 5%. Proof size is unchanged by decoupling (it
scales with integer width N, not field width F) — that is the CRT
formulation's job. Verify remains dominated by the pad² dense-MLE artifact
plus N-wide column checks — the fast-doubling formulation's job.

## After fast doubling (Phase 2 commit 2, 2026-07-04)

`fast_doubling_fibonacci.py` proves the same public claim (exact integer F_n
as a public CCS constant) with a logarithmic trace: 3 multiplication rows per
bit of n, state carried as linear forms (no copy rows). F_10000 drops from
10,001 constraints to 40. Measured, repeat 3, same machine:

| case                            | rows | pad | profile            |   prove |  verify | prime setup | total/iter | proof size | peak RSS |
|---------------------------------|-----:|----:|--------------------|--------:|--------:|------------:|-----------:|-----------:|---------:|
| fib n=1000, fast-doubling       |   28 |  32 | Int<16> / 256-bit  |  3.7 ms | 81.7 ms |     11.8 ms |    97.4 ms |   2.11 MiB | 11.5 MiB |
| fib n=10000, fast-doubling      |   40 |  64 | Int<128> / 256-bit |  101 ms |  10.6 s |      2.8 ms |     10.7 s |   31.5 MiB |  100 MiB |

Context: exact F_10000 proving is now 17x faster than RISC Zero's published
1.7 s GPU Fibonacci number and 107x faster than their 10.8 s 64-core CPU
number, on a single CPU core, for the exact 2,090-digit integer rather than
its remainder mod 2^64. Formulation caveat: this is a value claim (F_n equals
this integer), not a step-by-step trace attestation; both are labelled as
such in the exports.

Remaining verify cost at pad 64 is almost entirely the N=128 wide-integer
PCS column checks (proof and verify both scale with integer width) — the
CRT residue formulation targets exactly this.

Reproduction (until harness wiring lands):

```sh
python -c "import json; from zkfol_zinc_adapter.fast_doubling_fibonacci import \
build_fast_doubling_fibonacci_ccs_export as b; \
json.dump(b(10000, check=True), open('fastdbl10000.json','w'))"
./zkfol_zinc_adapter/rust/zkfol-zinc-runner/target/release/zkfol-zinc-runner \
  --input fastdbl10000.json --int-limbs 128 --field-limbs 4 --repeat 3 --json
```

## After CRT residue channels (Phase 2 commit 3, 2026-07-04)

`crt_fast_doubling_fibonacci.py` runs the fast-doubling trace independently
per residue channel with lifted-modular reduction rows (c + p*u quotient
witnesses; eprint 2025/316's R1CSl shape), so witness width becomes a chosen
parameter instead of F_n's size. Channel width sweeps padded dimension
against integer width; all corners measured, exact F_10000, repeat 3
(cb120 repeat 1):

All rows below prove Fibonacci at n = 10000. The first three prove the
exact 2,090-digit integer F_10000 (pinned by CRT residues); the last row
proves the weaker statement F_10000 mod 2^64 — the arithmetic RISC Zero's
documented benchmark uses — and is included for statement parity.

| what is proved                    | corner              | channels | rows |  pad | profile           |  prove |  verify | total/iter | proof size | peak RSS |
|-----------------------------------|---------------------|---------:|-----:|-----:|-------------------|-------:|--------:|-----------:|-----------:|---------:|
| exact F_10000 (2,090 digits)      | 500-bit channels    |       14 |  560 | 1024 | Int<16> / 256-bit | 31 ms  |  818 ms | **864 ms** |   15.9 MiB |  152 MiB |
| exact F_10000 (2,090 digits)      | 250-bit channels    |       28 | 1120 | 2048 | Int<8> / 256-bit  | 27 ms  | 1.24 s  |     1.27 s |    8.1 MiB |  418 MiB |
| exact F_10000 (2,090 digits)      | 120-bit channels    |       59 | 2360 | 4096 | Int<4> / 256-bit  | 34 ms  | 4.37 s  |     4.41 s |    8.1 MiB |  1.6 GiB |
| F_10000 mod 2^64 (RISC0's statement) | single channel   |        1 |   40 |  128 | Int<4> / 256-bit  | 3.5 ms |  25 ms  | **30 ms**  |   1.16 MiB |    9 MiB |

Pre-registered tax-model predictions vs measured: proof sizes within ~2%
(cb250 better than predicted), cb120/cb250 verify within noise, cb500
verify 2.3x over prediction (the wide-column term is systematically
underestimated; same bias as the fast-doubling row). The cb500 verify
(818 ms at pad 1024/Int<16>) matches the Phase-1 linear-trace verify at the
same profile within 2 ms — verify cost is (pad, N)-determined and
formulation-independent, as the model claims.

Day trajectory for exact F_10000 (prove / verify / proof):
refused -> 20.5 s / 236 s / 526 MiB (decoupling) -> 101 ms / 10.6 s /
31.5 MiB (fast doubling) -> **31 ms / 818 ms / 15.9 MiB** (CRT, cb500).
The mod-2^64 parity row proves RISC Zero's own documented statement in
30 ms end-to-end on one CPU core, vs their published 1.7 s (RTX A6000
prove-only) and 10.8 s (64-core EPYC).

Provenance: all rows in this section are hand-formulated direct exports
(compiler targets), not generic-bridge compilations; see the provenance
discussion in this file's baseline section.

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
