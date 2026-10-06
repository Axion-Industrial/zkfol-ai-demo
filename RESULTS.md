# Results

Every figure below was measured in one run of `bin/harness bench`. Nothing is extrapolated.
Each cell is the median of 5 runs, with the range beside it. The box is a cloud VM
("sandbox") and not the stage machine: re-run `bin/harness bench` on the machine that
will be used, and the file is rewritten with its own stamp.

## Stamp

| | |
|---|---|
| zkFOL commit | `08149197ff133536fa201a48ce9cc9703b0603f5` |
| Zinc+ commit | `5a01924a06b8748e3250bda37aafd7a34135b223` (the `Cargo.lock` revision of `zinc-protocol`) |
| CPU | Intel(R) Xeon(R) Processor @ 2.80GHz, 4 cores |
| Memory | 15.7 GB |
| OS | Ubuntu 24.04.5 LTS |
| Erlang / Elixir / Rust | 27 (erts 15.2.7) / 1.18.4 / rustc 1.91.0 (f8297e351 2025-10-28) |
| Date | 2026-10-06 |
| Run order | cells run strictly one at a time, in the order below |
| Load average at cell starts (1 minute) | 0.63 to 1.51 |
| CPU steal over the whole run | 3.15 % |

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
| 300 words | 1 row of 4095 cells | 111 (108 to 118) | 32.0 (26.6 to 37.4) | 284 (284 to 284) KB | 31 (29 to 46) MB |
| 1000 words | 2 rows of 4095 cells | 140 (123 to 145) | 31.8 (28.6 to 46.1) | 298 (298 to 298) KB | 42 (40 to 48) MB |
| 3000 words | 6 rows of 4095 cells | 289 (267 to 296) | 28.1 (27.1 to 34.6) | 351 (351 to 351) KB | 89 (80 to 105) MB |

## grounding

| Input | Shape | Prove (ms) | Verify (ms) | Proof | RSS delta |
|---|---|---|---|---|---|
| 300 words | 20 figures, 50 source figures | 154 (143 to 162) | 20.4 (18.4 to 22.8) | 415 (415 to 415) KB | 3 (1 to 3) MB |
| 1000 words | 67 figures, 50 source figures | 161 (150 to 176) | 20.7 (17.8 to 23.5) | 415 (415 to 415) KB | 2 (1 to 3) MB |
| 3000 words | 200 figures, 50 source figures | 171 (166 to 182) | 21.9 (19.6 to 23.6) | 415 (415 to 415) KB | 2 (1 to 3) MB |

## trace

| Input | Shape | Prove (ms) | Verify (ms) | Proof | RSS delta |
|---|---|---|---|---|---|
| 10 events | 10 events in 127 columns | 173 (153 to 182) | 10.6 (10.0 to 13.6) | 486 (486 to 486) KB | 0 (0 to 1) MB |
| 50 events | 50 events in 127 columns | 172 (158 to 180) | 10.6 (10.1 to 17.2) | 486 (486 to 486) KB | 1 (0 to 1) MB |
| 200 events | 200 events in 255 columns | 304 (294 to 320) | 13.0 (11.1 to 15.7) | 531 (531 to 531) KB | 1 (1 to 1) MB |

## trace with exfiltration

| Input | Shape | Prove (ms) | Verify (ms) | Proof | RSS delta |
|---|---|---|---|---|---|
| 10 events | 10 events in 127 columns | refused after 171 (166 to 185) | none | none | 0 (0 to 1) MB |
| 50 events | 50 events in 127 columns | refused after 179 (170 to 192) | none | none | 1 (0 to 1) MB |
| 200 events | 200 events in 255 columns | refused after 326 (311 to 335) | none | none | 1 (0 to 2) MB |


## Limits found while measuring

- **2^15 rows.** The pinned Zinc+ rejects an honest proof once a column needs 2^15 rows
  (`Proximity failure` at the integer commitment), so a row holds at most 16383 cells and
  a long text spans several rows.
- **2^56.** An honest proof of a column holding a value above about 2^56 beside small
  ones is rejected, so every cell stays under it. Figures encode under 2^54, and a
  destination identifier is 54 bits of a hash.
- **Degree.** The protocol's degree bound is 32. The trace predicate's largest term has
  degree 16.
