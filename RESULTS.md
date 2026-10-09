# Results

Every figure below was measured in one run of `bin/harness bench`. Nothing is extrapolated.
Each cell is the median of 5 runs, with the range beside it. The box is a cloud VM
("sandbox") and not the stage machine: re-run `bin/harness bench` on the machine that
will be used, and the file is rewritten with its own stamp.

## Stamp

| | |
|---|---|
| Demo commit | `d399b815bf304d8d57d59630bc3124b71ab090e2` |
| zkFOL commit | `10374e1e7e334cf0cffd923b381f3d9f0790816c` |
| Zinc+ commit | `5a01924a06b8748e3250bda37aafd7a34135b223` (the `Cargo.lock` revision of `zinc-protocol`) |
| CPU | Intel(R) Xeon(R) Processor @ 2.80GHz, 4 cores |
| Memory | 15.7 GB |
| OS | Ubuntu 24.04.5 LTS |
| Erlang / Elixir / Rust | 27 (erts 15.2.7) / 1.18.4 / rustc 1.91.0 (f8297e351 2025-10-28) |
| Date | 2026-10-09 |
| Run order | cells run strictly one at a time, in the order below |
| Load average at cell starts (1 minute) | 0.88 to 3.52 |
| CPU steal over the whole run | 3.19 % |

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
| 100 characters | 100 cells | 34.2 (31.9 to 45.4) | 7.7 (7.0 to 8.7) | 89.0 (89.0 to 89.0) KB | 0 (0 to 7) MB |
| 500 characters | 500 cells | 82.4 (76.7 to 85.4) | 9.6 (8.3 to 13.3) | 116 (116 to 116) KB | 5 (0 to 7) MB |
| 999 characters | 999 cells | 134 (132 to 149) | 13.3 (11.1 to 17.1) | 145 (145 to 145) KB | 5 (0 to 8) MB |

## grounding

| Input | Shape | Prove (ms) | Verify (ms) | Proof | RSS delta |
|---|---|---|---|---|---|
| 10 figures | 10 figures, 10 source figures | 127 (112 to 146) | 11.2 (9.4 to 15.9) | 509 (509 to 509) KB | 0 (0 to 0) MB |
| 25 figures | 25 figures, 25 source figures | 349 (332 to 353) | 16.6 (15.4 to 22.4) | 618 (618 to 618) KB | 11 (0 to 16) MB |
| 50 figures | 50 figures, 50 source figures | 1356 (1332 to 1397) | 44.8 (40.6 to 46.6) | 890 (890 to 890) KB | 74 (63 to 97) MB |

## trace

| Input | Shape | Prove (ms) | Verify (ms) | Proof | RSS delta |
|---|---|---|---|---|---|
| 10 events | 10 events in 71 columns | 1038 (984 to 1087) | 24.6 (22.1 to 28.8) | 2762 (2762 to 2762) KB | 2 (2 to 4) MB |
| 50 events | 50 events in 351 columns | 4307 (4151 to 4899) | 34.4 (31.1 to 39.5) | 3157 (3157 to 3157) KB | 92 (83 to 150) MB |
| 200 events | 200 events in 1401 columns | 19360 (18073 to 20720) | 56.7 (51.4 to 70.8) | 3715 (3715 to 3715) KB | 406 (373 to 574) MB |

## trace with exfiltration

| Input | Shape | Prove (ms) | Verify (ms) | Proof | RSS delta |
|---|---|---|---|---|---|
| 10 events | 10 events in 71 columns | refused after 1091 (1077 to 1154) | none | none | 3 (1 to 5) MB |
| 50 events | 50 events in 351 columns | refused after 4313 (4220 to 4419) | none | none | 29 (0 to 33) MB |
| 200 events | 200 events in 1401 columns | refused after 19471 (18872 to 20324) | none | none | 362 (321 to 394) MB |


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
