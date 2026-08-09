# Zkfol

zkFOL in Elixir: the logic of *zk-SNARKs for First Order Logic* (Gabbay-Mendelsohn),
arithmetised to a uniform AIR and proved through Zinc+.

## The pipeline

| Stage                                                | Module                 |
|------------------------------------------------------|------------------------|
| Figure 1 syntax + Figure 2 arithmetisation           | `Zkfol.Ast`            |
| Definition 2.16 interpretations                      | `Zkfol.Interpretation` |
| Figure 3 semantics + judgement (the one oracle)      | `Zkfol.Semantics`      |
| the relational surface: `defrel`/`rel` to predicates | `Zkfol.Lang`           |
| order-2 descriptors read off a relation              | `Zkfol.Facts`          |
| the doubling rewrite to a log-depth kernel           | `Zkfol.Doubling`       |
| the AL backend: the derivation is the witness        | `Zkfol.Al`             |
| witness generation as a pass                         | `Zkfol.Witness`        |
| statement to UAIR, proved on Zinc+ through the NIF   | `Zkfol.Uair`           |
| the front door: one call from relations to a receipt | `Zkfol`                |
| the system shaped for a viewer                       | `Zkfol.Face`           |

The only essential state is the command log (`Zkfol.Log`): events are appended,
never rewritten; every other datum, witness to report, is derived on demand. Worked examples in `lib/examples/` (`ExExample`) are the
documentation, the fixtures, and the tests at once: `Examples.EUser` is the book
of relations, and every performance claim is an assertion in `Examples.EBench`,
re-derived on the machine that runs it. Every refusal is a typed value,
`{reason, detail}`, indexed in `Zkfol.Refusal`.

The Rust prover is `native/zkfol_zinc_plus`, a Rustler NIF binding a pinned
zinc-plus fork and interpreting the UAIR over three cell widths: i64, 768-bit,
and 7040-bit. Proving runs on a dedicated thread and answers to an id. Its field
is a fixed secp256k1 projecting prime, so proofs on this lineage are
honest-prover-only. The cell widths and trace limits live in
`native/zkfol_zinc_plus/src/config.rs`; the fork rev is pinned in its
`Cargo.toml`. `analysis/` holds the frozen measurement record.

## Environment

`mix deps.get` builds the app and its Rust NIF.

```sh
mix test          # every example on its own store (.mnesiastore-test/), safe beside a live node
mix dialyzer      # type checking
mix run -e 'Examples.EBench.report() |> Enum.each(&IO.inspect/1)'   # the benchmark
```

## In iex

`iex --sname fol -S mix` opens the live node; its log lives in `.mnesiastore/`.
The front door is one call, evaluation needs no proof, and the benchmark
examples double as a smoke test:

```elixir
Examples.EUser.compiled()          # one act: relations to a proof, the receipt on the log
query = Zkfol.eval!(Examples.EUser.fib(), [:_, :_])   # answers without proving
Zkfol.Query.next(query)            # the next answer, prolog's ;
Examples.EBench.measured_fibonacci()
Examples.EBench.report()
```

## Installation in GT

The inspector side lives under `src/` as Tonel packages, `BaselineOfZkfol` and
`Zkfol`, reading the running node over gt_bridge. Inspecting a receipt dresses
it in the act's pipeline and trail; an emitted statement wears the Uair pointer
grid with its deref chains, hover, and failures views; a route wears its passes;
a pass module its record and examples. The live GT examples compose on the
Elixir examples, so the backing node must run this tree; the node-free examples
run against recorded feed fixtures. A fresh `load` also rides AL's GToolkit
tooling in, so the AL GUI displays alongside the grid.

```st
"fresh / CI: pins the gt_bridge mix.exs asks for, rides AL's GUI in, loads Zkfol"
Metacello new
	repository: 'github://bellissimogiorno/20260627-zkfol-zinc-playground:main/src';
	baseline: #Zkfol;
	load
```

When you are hacking a work-in-progress bridge or AL, `load: #dev` loads only
`Zkfol` against what is already in the image and touches no pin. Until this
package lands on `main`, load it from your checkout instead:
`repository: 'tonel://<repo>/src'; baseline: #Zkfol; load: #dev`.
