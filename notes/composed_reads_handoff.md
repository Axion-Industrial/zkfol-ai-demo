# What changes when zinc+ ships the pointer query

The composed-read lowering (Section 4 of the paper) emits everything
the backend will need and refuses only at the prover boundary. This
note records which seams are permanent and which are the workaround,
so landing native support is a deletion, not an archaeology.

## Permanent (native support consumes these, do not undo)

The lowering lives in `Zkfol.Uair.Composed`; `Zkfol.Uair.emit/3` calls
`lower/4` and later `emitted/3`, and nothing else reaches inside.

- Bit rows, booleanity, reconstruction: emitted by
  `Zkfol.Uair.Composed.lower/4` in `lib/zkfol/uair/composed.ex`, the
  constraints built in `constraints/2`, the derived rows in `extend/4`.
  Survives
  because Section 4's mechanism IS evaluation at a committed bit-point;
  zinc+ verifies the claim at that point, it does not replace the
  encoding.
- Result row and the `{:cell, i, j}` to `{:cell, R}` rewrite:
  `rewrite/3` in `lib/zkfol/uair/composed.ex`. Survives because the result row
  is the claim r(x) = f_i at the bit-point that zinc+ will verify;
  the rewrite is what keeps arithmetize and the shifts untouched.
- Range discipline and the Word lookup: `Composed.admits/2` enforces
  Def 3.1(2) oracle-side through `confined/2`, and `lookups/3` records
  `{:word, mu}` per pointer column in the uair map. Survives because the
  lookup becomes zinc+'s lookup group and the oracle check stays the
  front line. `Zkfol.Accumulator` borrows `admits/2` and `spelled/2`
  rather than keeping its own copies, so the fallback and the real
  lowering cannot drift apart while both exist.
- The composed-read declaration: `reads/2` in
  `lib/zkfol/uair/composed.ex`, reached through `emitted/3`. Survives
  because it is the pointer query's
  binding list: value column, bit columns, result column.

## Temporary (the entire undo list when support lands)

- The refusal: the `%Composed{}` clause of `mode_payload/1` guarding
  `Zkfol.Uair.request/1` in `lib/zkfol/uair.ex`. Delete that clause
  alone; Plain and Lookup still answer there.
- The NIF encode: pass `lookups` and `composed_reads` through
  `Zkfol.ZincPlus` into `RuntimeUair::signature` in
  `native/zkfol_zinc_plus/src/runtime.rs`, where the `vec![]` in
  `UairSignature::new` is the lookup-specs slot (`lookup_specs`
  already exists upstream; `composed_reads` maps to whatever
  interface they ship).
- The pin: `native/zkfol_zinc_plus/Cargo.toml`, rev `7cf72c4e` today.
  Bump to the supporting rev.

Nothing else changes: no pass, no encoding, no witness shape.

## Risk

If zinc+ ships a Lasso-style interface that takes the address row and
does bit decomposition internally, the bit-row emission becomes
redundant: `constraints/2` and the bit rows in `extend/4` get deleted
wholesale, handing the pointer column bare. The blast radius is
contained to those two sites.

The F1 classifier over-refuses on the completeness side: a statement
whose pointer shares a target with a computed cell is pushed onto the
composed-read path, and so onto this refusal, even when an affine
schedule could have carried it, so some reads pay the composed-read
toll they do not strictly owe.

## Accumulator fallback (delete on arrival)

Until the pointer query lands, the default pipeline routes composed
reads through `Zkfol.Accumulator` (`lib/zkfol/accumulator.ex`), a
statement-to-statement pass between witness derivation and emit. It
respells the Section 4 claim R(x0) = C_i(A(x0)) as ordinary
constraints: index bits shared by the trace, the pointer's bits and
the read's result broadcast as constant rows pinned at their column
by a bit-selector, and an eq-weighted running sum whose endpoint
reads out R(x0), one instance per read per column. A degree-len
product pin (A - 1)...(A - len) = 0 closes the pointer range
in-circuit, so the expanded uair emits no `lookups` entry.

The readout trusts `:x`, the committed index column, to hold the true
column number. Emit left it free, so a coordinated forge could flatten
`:x` to column one, vacate the `selector(len)` readout, and swap in a
lying result row that the affine constraints never reach: it proved
and verified. `Zkfol.Uair.emit/3` now pins `:x` in-circuit (see
`index_pin/6`): a forced ones column, held to one across the
unconstrained last row by its own shift, is a trustworthy region
indicator, and the pin reads `:x` down as a strict decrement over the
real columns and one at column one and its padding. This is the
boundary anchor X(1) = 1 and the step X = prev + 1, carried in the
constraint so every selector reads at the true row. The same forge is
now refused at the prover.

Every shifted read sits in the step branch alone because the zinc+
shift zero-pads its tail (combined_poly_resolver.rs drops the first
shift_amount rows), so the wrap and padding steps satisfy the base
branch instead. Statements whose pointers all carry schedules pass
through byte-identical, and `emit/3` pins `:x` only when the predicate
reads it, which today is exactly the accumulator's expansion. The
boundary refusal still guards any uair that declares composed reads.
Evidence lives in `Examples.EAccumulator` (shape, end-to-end proof,
tamper rejection, the coordinated forge rejection, the standing
refusal), `Examples.EBench` under `measured_accumulator_hop`, and
`Examples.EPipeline.outside_the_class_passes_through`.

Cost in rows, for P pointers, K reads, len n, and mu index bits
(mu = num_vars): mu + 1 shared rows, mu per pointer, 1 per read,
and per column instance mu broadcast rows per pointer plus 2 rows
per read, in total mu + 1 + P mu + K + n (P mu + 2 K). hop at
n = 5 derives 44 rows over its 3-row witness, and the index pin adds
one ones column: 49 columns, 38 shifts, and a 9407-op program that
proves in about 110 ms and verifies in about 3 ms. The eq-tilde rides at full degree: the
pinned zinc+ accepted a root of degree 40 (measured, with synthetic
probes to the same depth), so the helper-row splitting we kept in
reserve (measured at 41 ms prove, 10 more rows) stays unshipped.
The fallback stops at len = 2^mu, where the index bits cannot
spell len; it refuses there by name.

Rip-out when zinc+ lands the pointer query:

- `lib/zkfol/accumulator.ex`, the whole module.
- Its slot and alias in `Zkfol.Pipeline.default/0`.
- `lib/examples/e_accumulator.ex` and its block in
  `test/examples_test.exs`.
- `measured_accumulator_hop` in `lib/examples/e_bench.ex`, its line
  in `report/0`, and `available_memory_mb/0` if nothing else grew a
  taste for it.
- The accumulator assertions in
  `Examples.EPipeline.outside_the_class_passes_through`.
- `index_pin/6` and its helpers in `lib/zkfol/uair.ex`, once no
  predicate reads `:x`; the native pointer query pins the address
  itself, so the emit-side pin retires with the accumulator.
- This section.
