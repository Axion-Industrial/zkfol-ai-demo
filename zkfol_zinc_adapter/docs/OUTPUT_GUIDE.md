# Output guide

For the complete practical meaning of every command-line option, see `docs/OPTIONS_REFERENCE.md` or run `./zkfol_zinc_adapter/folzinc options`.

The common command is:

```bash
./zkfol_zinc_adapter/folzinc demo --zinc
```

The output has four layers.

## 1. Concrete statement

The demo says exactly what it is computing. By default:

```text
Concrete demo claim: exact integer 2^4 = 16 (public final claim).
```

For power examples, row `C1` is the base, row `C2` is the exponent, row `C3` is the output, and row `C4` is the recurrence pointer. The final column is the public claim when `--public-final` is enabled.

## 2. FOL semantic checks

The exporter checks the reference implementation in three ways:

```text
direct FOL semantics
beta_F(mkQ_x(<phi>))
fast beta evaluator
```

For valid witnesses these all agree and all predicate values are zero. In the paper's integer semantics, zero represents truth.

## 3. Witness matrix `C`

`folzinc inspect` prints the finite matrix interpretation used by the FOL predicate:

```bash
./zkfol_zinc_adapter/folzinc inspect out/demo_power_2_4_public.json
```

For the default demo you should see rows like:

```text
C1 base                       2  2  2  2  2
C2 exponent                   0  1  2  3  4
C3 output                     1  2  4  8  16
C4 previous-column pointer    1  1  2  3  4
```

This says every column satisfies either the base case or the recurrence case for exponentiation, and the last column is `2^4=16`.

For large examples, the matrix display is abbreviated. Use:

```bash
--matrix-head N
--matrix-tail N
--full-matrix
```

## 4. CCS/R1CS constraints

With `--constraints`, `folzinc inspect` prints an abbreviated preview of the rows handed to Zinc:

```bash
./zkfol_zinc_adapter/folzinc inspect out/demo_power_2_4_public.json --constraints
```

Each row has the form:

```text
<A,z> * <B,z> = <C,z>
```

The preview shows the first and last rows, including labels such as:

```text
mkq_x=1:...
public_binding:...
boolean:...
```

Use:

```bash
--constraint-head N
--constraint-tail N
--full-constraints
```

`--full-constraints` can print thousands of rows.

## 5. Variables, degree, and bit bound

Normal `folzinc run`, `folzinc bench ... --run`, `folzinc inspect`, and `folzinc explain` output now include the practical Zinc constraint shape.  This is the information to quote when asked for a target use case's number of variables, constraint degree, and bit bound.

```text
Zinc constraint shape for this target
-------------------------------------
scalar z variables:          1002 before padding = 1 public + 1 constant-one + 1000 private
constraints:                 1001 rows before padding
declared CCS/R1CS degree:    2 (<A,z>*<B,z>=<C,z>)
simplified witness degree:   at most 1 after fixing public inputs and the constant-one coordinate
bit-bound delta:             694 bits
  public input bits:         0
  witness value bits:        694
  coefficient bits:          694
```

The declared degree is always 2 for this adapter's R1CS/CCS bridge, because each row is represented as a product of two linear forms equalling a third linear form.  Some specialised benchmark rows are effectively linear after public constants are fixed; the `simplified witness degree` field records that.

The bit-bound delta is the largest absolute bit length among values and coefficients materialised in this exported integer relation.  It should not be read as a claim that Zinc's sampled prime must be larger than every value.

## Rust/Zinc timing fields

The Rust runner reports:

```text
relation_check_ms          local integer CCS check before calling Zinc
field_setup_ms             sampled random-field setup time per proof iteration
field_relation_check_ms    adapter diagnostic check after integer-to-field mapping
zinc_prove_call_ms         time inside the ZincProver::prove library call
zinc_verify_call_ms        time inside the ZincVerifier::verify library call
measured_iteration_ms      field setup + field check + prove call + verify call
prove_ms                   legacy alias for zinc_prove_call_ms
verify_ms                  legacy alias for zinc_verify_call_ms
ccs_m_padded               constraint rows after Zinc power-of-two padding
ccs_n_padded               z-vector length after Zinc power-of-two padding
proved                     true if Zinc prove and verify completed
```

These are prototype timings for the current explicit CCS bridge, not production cryptographic performance claims. In particular, `zinc_verify_call_ms` can be larger than `zinc_prove_call_ms` in the current public Zinc proof-of-concept: the verifier call performs field-side mapping, sumcheck verification, Zip/PCS verification, and final constraint-evaluation work. That behaviour is an implementation/measurement fact, not a theoretical claim that optimized SNARK verification should be slower than proving.

## Progress heartbeat

When `folzinc run`, `folzinc demo --zinc`, or `folzinc bench ... --run` invokes Cargo/Zinc, the wrapper prints periodic status lines to stderr.  A typical line is:

```text
[folzinc progress] case=fibonacci_exact_n10000_public | elapsed 12:05 | Zinc prove 1/3 | Zinc prover is running; exact sub-progress is not exposed by Zinc | 3/13 units (23.1%) | ETA estimating | CPU 742.1% | RSS 8.9 GiB | peak RSS 9.4 GiB | procs 7 | coarse progress | constraints=10,001 | witness_vars=10,000 | variables=10,002 | degree=2/simp≤1 | bit_bound=6,942
```

The unit count is intentionally coarse.  One unit is the local integer relation check; each repeat contributes four more units: sampled random-field setup, sampled-field relation check, Zinc proof generation, and Zinc verification.  For `--repeat 3`, the total is therefore `1 + 4*3 = 13` units.

The ETA is unavailable until at least one counted unit has completed.  It becomes an approximation after that, because proof and verification units can have very different costs.  CPU usage and RSS memory are measured from the current Linux `/proc` process tree rooted at Cargo or at the built runner binary.  They are approximate but helpful for distinguishing a still-working proof from an idle or stuck process.  `RSS` is current resident memory, `peak RSS` is the largest resident-memory value observed by the heartbeat, `procs` is the current process-tree size, and `top` lists the largest live processes when useful.  On non-Linux systems these fields may report `n/a`.

A run started under an older package cannot be retrofitted with progress reporting. Stop it and restart with the updated package.  The wrapper now checks the built Rust runner version; if a stale `target/release/zkfol-zinc-runner` is left behind after an upgrade, it falls back to Cargo or asks you to rebuild instead of silently using old behaviour.

## Resource-preflight skips

For large inputs, a run row may have:

```json
{"mode": "skipped-by-resource-preflight", "skipped": true}
```

This means the exported relation was produced, but Zinc was not launched because the current proof-of-concept was predicted to require a very large dense allocation after padding.  Such rows are not failed proofs; they are operational safety skips.  Use `folzinc estimate` to see the calculation, `--check-only` to validate the relation without proving, or `--allow-large` to override.
