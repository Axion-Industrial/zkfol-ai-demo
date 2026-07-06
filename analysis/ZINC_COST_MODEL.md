# Black-box cost model of Zinc (rev `0c9ed21`, NethermindEth/zinc)

Derived 2026-07-04 by code analysis of the pinned checkout
(`~/.cargo/git/checkouts/zinc-*/0c9ed21`; paths below relative to it). The
full paper (eprint 2025/316, Garreta–Waldner–Hristova–Dall'Ava, CRYPTO 2025)
has since been read; paper-verified soundness facts are in §7 below. We treat
Zinc strictly as a black box: this document exists so the frontend compiler
can target Zinc's fast paths, not so we patch Zinc.

Notation: `m×n` = padded CCS dims, `t` = #matrices, `d` = max degree,
`nnz` = total nonzeros, `N` = integer limbs (`Int<N>`, 64N-bit),
`F` = field limbs (`RandomField<F>`, 64F-bit prime q), `s = log m`.
PCS row length `l = next_pow2(ceil(sqrt(n)))`, rows `R = n/l ≈ sqrt(n)`,
column openings `Q = 1000`, proximity tests `P = 1` (`DefaultLinearCodeSpec`,
`src/zip/code.rs:229-242`).

**Critical structural fact**: `CCS_Z::pad` (`src/ccs/ccs_z.rs:111-129`) forces
**m = n = next_pow2(max(m, n))** — the system is always padded square.

## 1. Cost drivers

### Prover — Θ(nnz + d·m + n), no dense objects

`ZincProver::prove` (`src/zinc/prover.rs:50-88`):
1. Map z and matrices to F_q: O((n+nnz)·(division + F²)) (`src/field.rs:536-568`).
2. Sumcheck 1 (Spartan linearization): t sparse mat-vecs = O(nnz) field mults
   (`src/zinc/utils.rs:121-135`); sumcheck ≈ 2m·(d+2)·Σ|S_i| mults — for R1CS
   (t=3, d=2) ≈ 24m (`src/sumcheck/prover.rs:126-173`).
3. Sumcheck 2: O(nnz) sparse eval table + ≈6n mults (`prover.rs:261-303`).
4. Zip PCS commit: RAA-encode R rows = O(n) integer adds at width 4N; one
   blake3 Merkle tree over 2l leaves (`src/zip/pcs/commit.rs:51-78`).
5. Zip PCS open: n mults at width 8N + Q=1000 column openings
   (`src/zip/pcs/open_z.rs:22-143`).

Field mult ≈ 2F² word-mults (schoolbook + Montgomery,
`src/field/config.rs:163-170`). At m=n=8192, F=4: ~10⁶ field mults →
measured 44.5 ms is consistent.

### Verifier — Θ(t·m·n) time AND memory: the measured 17.2 s

`ZincVerifier::verify` (`src/zinc/verifier.rs:45-77`):
1. Re-samples the prime (same cost as prover setup).
2. Maps the whole statement to F_q (no preprocessing/holography): O(nnz).
3. Sumcheck verification: O(s·d²) — microseconds.
4. Zip verify: ≈ Q·R ≈ 1000·sqrt(n) field + wide-int mults
   (`src/zip/pcs/verify_z.rs:19-190`; in-code TODOs admit the inner product
   is slow).
5. **THE BOTTLENECK — V_xy** (`verifier.rs:249-261`): for each of the t
   matrices, `DenseMultilinearExtension::from_matrix` materializes the full
   padded m×n dense table (`vec![F::zero(); rows*cols]`,
   `src/poly_f/mle/dense.rs:69-87`), then `evaluate()` clones the entire
   vector and runs a serial O(m·n) fold (`dense.rs:142-174`). At 8192², F=4:
   ~48 B/cell → ~3.2 GB alloc + 3.2 GB clone per matrix, ×3 matrices ≈ 20 GB
   of single-threaded memory traffic. Matches measured 17.2 s and 6.03 GiB
   peak RSS.

This is an implementation artifact, not protocol-inherent: a sparse MLE
evaluation (Σ_nnz val·eq(r_x,row)·eq(r_y,col) = O(nnz+m+n)) would suffice,
and `SparseMultilinearExtension` already exists in the codebase
(`src/poly_f/mle/sparse.rs`) — the verifier path just doesn't use it.

### Scaling summary

| Quantity             | Prover                           | Verifier                    | Proof size         |
|----------------------|----------------------------------|-----------------------------|--------------------|
| padded m×n           | O(m + n + nnz)                   | **Θ(t·m·n)** time+memory    | O(sqrt(n))         |
| field limbs F        | ×F² (mults), ×F (memory)         | ×F² and ×F on the m·n table | ~independent       |
| nnz vs dense         | linear in nnz                    | insensitive (m·n dominates) | independent        |
| degree d / Σ\|S_i\|  | ×(d+2)·Σ\|S_i\| on the m term    | negligible                  | +s·(d+2) elems     |
| t matrices           | +t sparse matvecs                | **×t on the m·n term**      | +t elems           |
| int limbs N          | PCS int ops ×N²                  | column checks ×N²           | **×N** (dominant)  |

Prime sampling (`src/prime_gen.rs:15-28`): expected candidates ≈ 22·F, each
Miller-Rabin ≈ O(64F modexp squarings × F²) → setup ≈ O(F⁴). Negligible at
F=4; explodes for oversized fields (fib n=1000's 2.33 s at F=32). The
verifier pays it again.

## 2. The two modes (ZZ vs FF)

Zinc = Zinc-PIOP (reduce the integer statement mod a randomly sampled prime
q, run a Spartan-style PIOP over F_q) + Zip (Brakedown-type PCS from an IOP
of proximity to the integers). It natively targets ℤ and ℚ (paper abstract).

In this rev, **only ZZ mode is a supported end-to-end API**:
prove/verify take `CCS_Z`/`Statement_Z`/`Witness_Z` over `Int<N>` plus a
config from `draw_random_field`; the verifier hard-rejects any config that
is not the transcript-derived sampled prime (`verifier.rs:53-57`). A fixed
finite field is expressible (`field_config!`, used in tests), but only by
driving the sub-protocols (SpartanProver/Verifier + MultilinearZip) directly.

Cost difference: FF mode = ZZ mode minus prime sampling; nothing else
changes (integers are mapped into the field either way; Zip commits integer
polynomials regardless). No cheaper native-field pipeline exists to unlock.

PoC soundness caveat (observed, not a verdict): q is derived from the
transcript after absorbing only the public inputs — before the witness is
bound (`src/zinc/utils.rs:161-171`, "Fixing the random prime q for now").

## 3. Parallelism (`parallel` feature)

Parallelized: sumcheck prover fold, PCS encode_rows, combine_rows, Merkle
building. Serial: the entire verifier bottleneck (dense from_matrix +
fix_variables), map_to_field, the 1000-column PCS verify loop, RAA
accumulate. Measured 102% CPU is exactly what the code predicts: the
parallelizable parts are already sub-50 ms; ~100% of verify time is serial.

## 4. Cross-profile Int<N> with small RandomField<F> — feasible

The trait bounds on `prover.rs:43-48` / `verifier.rs:35-43` are satisfied
for **any** (N, F): crypto-bigint `resize` gives `Int<N>: From<&Int<M>>` for
all N, M (`src/field/int.rs:194-199`); `FieldMap for BigInt<M>` explicitly
handles M > F by reducing `value % modulus` in wide arithmetic before
narrowing (`src/field.rs:536-568`). The shipped example already pairs
asymmetric widths (`Int<1>` + `RandomField<4>`, `examples/simple_r1cs.rs`).
The adapter's F = 2N table is a convention, not a requirement.

Expected costs at Int<128>/RandomField<4>: map_to_field does 8192-bit ÷
256-bit divisions (n+nnz of them); PCS integer ops at widths up to
Int<1024>; proof ≈ Q·R·32N bytes ≈ 262 MB at n=8192, N=128 (vs 4.4 MB at
N=2) — so CRT/fast-doubling formulations that keep N small remain preferable
to brute-width even after decoupling. Soundness of the pairing is quantified
in §7.1 (Lemma 2.1, a per-instance bound), conditional on the q-sampling-order
caveat in §7.2; a general small-field license is what Zinc+'s improved
soundness provides, not this bound.

## 5. Proof contents and size

`ZincProof = SpartanProof + ZipProof` (`src/zinc/structs.rs:16-35`). PCS
proof layout (verified by in-repo test `proof_size_is_correct_for_parameters`,
`src/zip/pcs/commit.rs:656-719`):

```
P·l·sizeof(Int<8N>) + Q·[ R·sizeof(Int<4N>) + (log2(2l))·32 + 24 ] + l·8F
```

Dominant term: **Q·R·32N ≈ 1000·sqrt(n)·32N bytes** — sqrt in circuit size,
linear in integer width, independent of F. Measured: fib n=100 = 684 KiB
(pad 128, N=2); standard power 2^32 = 4.20 MiB (pad 8192, N=2); fib n=1000 =
15.9 MiB (pad 1024, N=16). The runner now reports
`proof_size_bytes_estimate` / `proof_pcs_bytes` per run.

## 6. Compiler guidance (what to minimize, in order)

1. **Minimize max(rows, z-length) above all.** Square padding means the
   verifier pays Θ(t·pad²); halving padded dim ⇒ ~4× faster verify, 4× less
   memory, √2 smaller proof. Balance rows vs columns; never creep just past
   a power of two.
2. **Don't spend rows/columns buying sparsity.** Verifier cost is
   insensitive to nnz; the prover pays ~1 field mult per nonzero. Dense-ish
   rows are fine; extra rows are not.
3. **Prefer higher degree / more multisets over more rows or matrices.**
   Degree is cheap (prover ×(d+2)·Σ|S_i| on the m term, +s·(d+2) proof
   elements); each extra matrix multiplies the dominant verifier m·n term.
   Folding two R1CS rows into one degree-3 CCS row with the same t=3
   matrices is a straight win.
4. **Keep integer magnitudes small — they set N.** Proof size ∝ N, PCS
   integer mults ∝ N². But rule 1 dominates: at 8192², one extra bit of
   width is far cheaper than one extra power of two of dimension.
5. **F need not track N** (subject to the §4 soundness caveat). Fixing F=4
   while N grows keeps field ops constant.
6. **Parallelism will not save the verifier; don't shape for it.** If verify
   latency is the product constraint, the levers are pad dimension and t —
   or an upstream sparse-MLE fix to V_xy (O(nnz) in principle,
   `verifier.rs:249-261`).

## 7. Paper-verified facts (from the full text of eprint 2025/316)

Read 2026-07-04 (local copy: `~/Documents/Papers/Math/ZK-SNARKs/2025-316.pdf`).
Section/lemma pointers are to the paper.

1. **Decoupling is sound, quantitatively (Lemma 2.1 / Prop 4.6).** If witness
   and coefficient bit-sizes are bounded by B and the constraint polynomial
   has total partial degree d, the number of "bad" primes (where a false
   integer relation survives reduction) is at most
   `(B·d + B + 2^d) / λ` for λ-bit primes. Soundness error = bad primes /
   sampleable primes. Concretely for exact F_10000 (B ≈ 6,942 bits, d = 2,
   256-bit q): ≤ ~82 bad primes out of ~2^248 — negligible. **q never needs
   to exceed witness values**; the F = 2N convention has no mathematical
   basis. Caveat: the error bound degrades linearly in B, and the guarantee
   collapses entirely if the PCS does not enforce the bit-size bound
   (Remark 2.2) — Zip's testing phase (Protocol 3: integrality + magnitude
   check on a random linear combination of committed rows) is what enforces
   it, with extracted bound B = 2·B' + (6·dim + 2)·(λ + log dim) for honest
   bound B' and dim ≈ sqrt(#coefficients) (Eq. 6).

2. **Prime-sampling order is load-bearing (Protocols 1 and 4).** In both the
   PIOP and the PCS evaluation protocol, the verifier samples q *after* the
   witness oracles/commitments exist — they are part of the instance. The
   counting argument in (1) extracts the witness independently of q; if a
   prover could pick the witness after seeing q, it could craft an error
   divisible by q and the argument breaks. **The PoC runner derives q from a
   transcript containing only public inputs ("Fixing the random prime q for
   now", src/zinc/utils.rs:161-171) — a genuine deviation to report
   upstream.** In Fiat-Shamir form, q must be derived after absorbing the
   witness commitment.

3. **The paper's design point is small witnesses (~2λ bits).** The relation
   REL_R1CSl,Z carries an explicit bit-size bound B on all entries, and the
   paper argues satisfiable lifted-modular statements always admit witnesses
   of ~2λ bits (Section 2, "we make sure that the prover and verifier always
   work with integers of ≈ λ bit-size"). Exact 6,942-bit Fibonacci values are
   legal (B is a parameter) but far off the intended operating point.

4. **Native lifted-modular arithmetic (R1CSl).** The paper's core relation is
   `(A·z) ∘ (B·z) = C·z + m ∘ u` with a *public per-row modulus vector* m
   and a witness quotient vector u: every row can independently compute
   modulo its own m_y — non-prime moduli like 2^64 explicitly included, at
   the cost of one quotient witness entry per modular row and **no bit
   decomposition or range machinery for the modulus itself**. This makes the
   mod-2^64 and CRT-residue Fibonacci formulations the paper's *intended
   usage pattern*, not workarounds. (The PoC's CCS_Z path is plain
   integer CCS; the m ∘ u term can be emulated as an ordinary extra witness
   column per row with coefficient m_y. Range checks are needed only where a
   canonical representative must be bound.)

5. **A lookup relation is part of the framework (REL_Look, Protocol 2).**
   Zinc-PIOP includes a lookup argument over Q, used to force integrality of
   witnesses. Not implemented in the PoC's public API, but protocol-level
   support exists — relevant to eventually replacing the O(len^2) one-hot
   pointer machinery.

6. **Fiat-Shamir is explicitly unanalyzed (Section 2.4).** "We leave as
   further work the task of analyzing the state-restoration soundness of our
   schemes, so that we can reliably compile our succinct arguments into a
   SNARK using the Fiat-Shamir transform." The PoC's non-interactive mode
   (KeccakTranscript) therefore runs ahead of the paper's own security
   analysis. All external claims should label results as research-prototype
   measurements, not production-soundness statements.

7. **Column-opening count.** The evaluation/testing protocols open
   |J| = Θ(λ) columns (Protocols 3 and 4); the PoC's Q = 1000 is that
   parameter with margin. Proof-size trade-offs against λ go through here.
