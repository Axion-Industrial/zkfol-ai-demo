# FOL+Zinc exact-integer Fibonacci inputs for RISC Zero benchmark n-values

These cases bind final input/output cells as public benchmark claims. Power cases use Zinc public-input coordinates; the direct exact-Fibonacci cases use public CCS constants to avoid a multi-public-input edge case in the current Zinc proof-of-concept.

For Fibonacci, the FOL+Zinc exports in this package use exact, non-modular integer arithmetic. They deliberately do not match RISC Zero's documented modulo-2^64 Fibonacci arithmetic.

## FOL+Zinc input sizes

| case | profile | len(C) | max bits | public inputs | constraints | witness vars | z len | largest integer bits | exact output bits | exact output digits |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| fibonacci_exact_n100_public | compact | 100 | 69 | 1 | 101 | 100 | 102 | 69 | 69 | 21 |
| fibonacci_exact_n1000_public | compact | 1000 | 694 | 1 | 1001 | 1000 | 1002 | 694 | 694 | 209 |
| fibonacci_exact_n10000_public | compact | 10000 | 6942 | 1 | 10001 | 10000 | 10002 | 6942 | 6942 | 2090 |

## Direct zkVM comparison slots

No zkVM timing CSV was supplied. The generated `risc0_fibonacci_reference_notes.csv` records the source/arithmetic notes; fill `docs/zkvm_result_template.csv` with local RISC Zero/Jolt/Cairo/RISC0 results and rerun `zkfol-zinc-bench summarize --zkvm-csv ...`.

Interpretation note: the current FOL+Zinc numbers measure a deliberately explicit CCS bridge or, for the large exact Fibonacci cases, a clearly labelled trace-specialised exact-integer CCS. They are research baselines, not native-AIR lower bounds.

Resource note: run rows with `status = skipped-resource-guard` were not failed proofs. They were deliberately not launched because the adapter predicted that the current Zinc proof-of-concept would request a very large dense allocation after power-of-two padding. Use `folzinc estimate`, `--check-only`, or `--allow-large` as appropriate.
