# Zkfol

zkFOL in Elixir: the logic of *zk-SNARKs for First Order Logic* (Gabbay-Mendelsohn),
arithmetised to a uniform AIR and proved through Zinc+.

## The pipeline

| Stage                                              | Module                 |
|----------------------------------------------------|------------------------|
| Figure 1 syntax (terms, predicates)                | `Zkfol.Ast`            |
| Figure 1 range checks R                            | `Zkfol.Range`          |
| Definition 2.16 interpretations                    | `Zkfol.Interpretation` |
| Figure 3 semantics + judgement (the one oracle)    | `Zkfol.Semantics`      |
| Figure 2 arithmetisation (predicate to polynomial) | `Zkfol.Enrich`         |
| statement to UAIR, proved on Zinc+ through the NIF | `Zkfol.Uair`           |
| generating semantics (seeds to witness)            | `Zkfol.Witness`        |

The only essential state is the command log (`Zkfol.Log`): events are appended,
never rewritten; every other datum -- witnesses, UAIRs, claims, reports -- is
derived on demand. Worked examples in `lib/examples/` (`ExExample`) are the
documentation, the fixtures, and the tests at once; every performance claim is an
assertion in `Examples.EBench`, re-derived on the machine that runs it.

The recurrence pass (`Zkfol.Facts`, `Zkfol.Doubling`) rewrites certified
order-2 recurrences to log-n bit-walk traces.

The Rust prover is `native/zkfol_zinc_plus`, a Rustler NIF binding zinc-plus
(pinned at 7cf72c4e) and interpreting the UAIR over three cell widths -- i64,
768-bit, and 7040-bit. Proving runs on a dedicated thread and answers to an id.
Its field is a fixed secp256k1 projecting prime, so proofs on this lineage are
honest-prover-only. `analysis/` holds the frozen measurement record; the retired
Python proof of concept is on branch `attic/python`.

```sh
mix test          # every example, including live proofs through the NIF
mix dialyzer      # type checking
mix run -e 'Examples.EBench.report() |> Enum.each(&IO.inspect/1)'   # the benchmark
```

## Environment

The toolchain is managed with asdf. `.tool-versions` pins Erlang and Elixir, so
`asdf install` provisions them; `mix deps.get` then builds the app and its Rust NIF.

## In iex

`iex -S mix` opens a session with everything loaded. The benchmark examples double
as a smoke test, and each returns its measurement:

```elixir
Examples.EBench.measured_fibonacci()
Examples.EBench.report()
```

## Installation in GT

The inspector side lives under `src/` as Tonel packages, `BaselineOfZkfol`
and `Zkfol`. It ships one view, the Uair pointer grid: the emitted
statement's committed columns as rows, colored by derived kind (pointer
bits, dereference results, looked-up pointers), with claimed rows outlined.
Cells and row labels are clickable and spawn the named cell or row in the
next pane. The live GT examples compose on the Elixir examples, so the
backing node must run the lookup/uair-struct stack; the node-free examples
run against a proxy-shaped fixture. A fresh `load` also rides AL's GToolkit
tooling in, so the AL GUI displays alongside the grid.

```st
"fresh / CI: pins gt_bridge v0.18.1, rides AL's GUI in, loads Zkfol"
Metacello new
	repository: 'github://bellissimogiorno/20260627-zkfol-zinc-playground:main/src';
	baseline: #Zkfol;
	load
```

The `default` group pins gt_bridge v0.18.1 (the version `mix.exs` asks for) and
brings AL in through its own dev group, so the one bridge is the single pin.
When you are hacking a work-in-progress bridge or AL, `load: #dev` loads only
`Zkfol` against what is already in the image and touches no pin. Until this
package lands on `main`, load it from your checkout instead:
`repository: 'tonel://<repo>/src'; baseline: #Zkfol; load: #dev`.
