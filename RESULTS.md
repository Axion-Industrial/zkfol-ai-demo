# Results

Every figure below was measured in one run of `bin/harness bench`. Nothing is extrapolated.
Each cell is the median of 5 runs, with the range beside it. The box is a cloud VM
("sandbox") and not the stage machine: re-run `bin/harness bench` on the machine that
will be used, and the file is rewritten with its own stamp.

## Stamp

| | |
|---|---|
| Demo commit | `5fc4a982dfc2d06e00c4972ed8fe90bdf255f5bd` |
| zkFOL commit | `10374e1e7e334cf0cffd923b381f3d9f0790816c` |
| Zinc+ commit | `5a01924a06b8748e3250bda37aafd7a34135b223` (the `Cargo.lock` revision of `zinc-protocol`) |
| CPU | Intel(R) Xeon(R) Processor @ 2.80GHz, 4 cores |
| Memory | 15.7 GB |
| OS | Ubuntu 24.04.5 LTS |
| Erlang / Elixir / Rust | 27 (erts 15.2.7) / 1.18.4 / rustc 1.91.0 (f8297e351 2025-10-28) |
| Date | 2026-10-09 |
| Run order | cells run strictly one at a time, in the order below |
| Load average at cell starts (1 minute) | 0.75 to 3.17 |
| CPU steal over the whole run | 3.22 % |

"Uncontended" here means what those two rows say: the runner starts one cell at a time,
and the load average and steal time above are what the machine reported. The load average
covers the last minute, so it includes the runner's own proving in the cells before: it
is an upper bound on what else was running. Steal is time the hypervisor took from this
machine, and a value above zero means the machine was shared. Neither is a guarantee
about anything outside the run.

## What the columns are

- **Prove**: Zinc+ proving time, from the prover itself, in milliseconds.
- **Verify**: the standalone verifier's own time, including its parameter setup, with no
  process start-up and no file reads. It never sees the plaintext.
- **Proof**: the proof file the verifier is given, in kilobytes.
- **RSS delta**: the process's peak resident memory during the prove, minus its resident
  memory before it, in whole megabytes (never below 0). The peak counter is reset first,
  as `Examples.EBench` does.
- A **refused** cell is a statement the prover cannot prove. Its time is how long the
  prover ran before the statement failed to verify, and it has no proof.

## text (no em dash)

| Input | Shape | Prove (ms) | Verify (ms) | Proof | RSS delta |
|---|---|---|---|---|---|
| 100 characters | 100 cells | 33.9 (27.1 to 34.0) | 7.8 (5.7 to 8.8) | 89.0 (89.0 to 89.0) KB | 0 (0 to 8) MB |
| 500 characters | 500 cells | 76.5 (62.8 to 81.1) | 11.9 (8.2 to 12.3) | 116 (116 to 116) KB | 7 (0 to 9) MB |
| 999 characters | 999 cells | 135 (129 to 140) | 16.0 (12.9 to 21.3) | 145 (145 to 145) KB | 9 (0 to 13) MB |

## grounding

| Input | Shape | Prove (ms) | Verify (ms) | Proof | RSS delta |
|---|---|---|---|---|---|
| 10 figures | 10 figures, 10 source figures | 118 (109 to 131) | 11.7 (9.7 to 13.4) | 509 (509 to 509) KB | 0 (0 to 1) MB |
| 25 figures | 25 figures, 25 source figures | 367 (356 to 383) | 20.3 (17.2 to 21.3) | 618 (618 to 618) KB | 11 (0 to 17) MB |
| 50 figures | 50 figures, 50 source figures | 1379 (1353 to 1567) | 49.1 (44.2 to 70.4) | 890 (890 to 890) KB | 60 (28 to 90) MB |

## trace

| Input | Shape | Prove (ms) | Verify (ms) | Proof | RSS delta |
|---|---|---|---|---|---|
| 10 events | 10 events in 43 columns | 568 (516 to 574) | 23.2 (19.9 to 26.2) | 2596 (2596 to 2596) KB | 1 (0 to 4) MB |
| 50 events | 50 events in 211 columns | 2142 (2096 to 2245) | 28.8 (26.6 to 42.5) | 2950 (2950 to 2950) KB | 21 (20 to 51) MB |
| 200 events | 200 events in 841 columns | 9284 (9043 to 10946) | 41.2 (37.4 to 44.7) | 3400 (3400 to 3400) KB | 180 (150 to 216) MB |

## trace with exfiltration

| Input | Shape | Prove (ms) | Verify (ms) | Proof | RSS delta |
|---|---|---|---|---|---|
| 10 events | 10 events in 43 columns | refused after 612 (570 to 624) | none | none | 1 (0 to 6) MB |
| 50 events | 50 events in 211 columns | refused after 2231 (2142 to 2269) | none | none | 6 (5 to 10) MB |
| 200 events | 200 events in 841 columns | refused after 9601 (9480 to 10291) | none | none | 159 (111 to 183) MB |


## Limits found while measuring

- **Unroll budget.** The compiler unrolls a relation at every step of its derivation and
  stops at 3,000 sites, which is 999 codepoints for the no-dash rule. A longer text is
  refused before anything is derived.
- **32-bit words.** The compiled program's lookup check works in 32-bit words: an
  allowlist of two entries wider than a word failed to prove (`Lookup(FinalEvaluationMismatch)`),
  so a destination is four words, the first 128 bits of the hash of its address.
- **2^56.** An honest proof of a column holding a value above about 2^56 beside small
  ones is rejected, so every cell stays under it. Figures encode under 2^54, and the
  grounding sentinel is 2^55.
