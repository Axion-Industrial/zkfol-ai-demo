# Zkfol

zkFOL in Elixir: the logic of *zk-SNARKs for First Order Logic* (Gabbay-Mendelsohn),
arithmetised to a uniform AIR and proved through Zinc+.

## The pipeline

Evaluation asks AL for a derivation. Proving also lowers the relations to a uniform
AIR and places that derivation on the compiler's allocation.

| Role                                               | Module                 |
|----------------------------------------------------|------------------------|
| Figure 1 syntax + Figure 2 arithmetisation           | `Zkfol.Ast`            |
| Definition 2.16 interpretations                     | `Zkfol.Interpretation` |
| Figure 3 semantics + judgement (the one oracle)      | `Zkfol.Semantics`      |
| the relational surface: `defrel`/`rel` to clauses    | `Zkfol.Lang`           |
| order-2 descriptors read off a relation              | `Zkfol.Facts`          |
| the doubling rewrite to a log-depth kernel          | `Zkfol.Doubling`       |
| the AL backend: the derivation is the witness        | `Zkfol.Al`             |
| witness generation as a pass                        | `Zkfol.Witness`        |
| relation lowering to symbolic AIR and allocation    | `Zkfol.Phi`            |
| slots, banks, and call-site layout                  | `Zkfol.Alloc`          |
| the derivation placed on that allocation            | `Zkfol.Lay`            |
| committed AIR and pointer reads for the backend     | `Zkfol.Uair`           |
| proving on Zinc+ through the NIF                    | `Zkfol.Prover`         |
| the front door: one call from relations to a receipt | `Zkfol`                |
| the system shaped for a viewer                     | `Zkfol.Face`           |

The only essential state is the command log (`Zkfol.Log`): events are appended,
never rewritten; every other datum, witness to report, is derived on demand.
Worked examples in `lib/examples/` (`ExExample`) are the documentation, fixtures,
and tests at once: `Examples.EUser` is the book
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

Fetch dependencies, then compile the app and its Rust NIF. A Rust toolchain is required.

```sh
mix deps.get
mix compile
mix test          # examples on the isolated .mnesiastore-test/ store
mix dialyzer      # type checking
```

`mix test` selects the test environment automatically and can run beside the live node.
For a standalone benchmark on the test store:

```sh
MIX_ENV=test mix run -e 'Examples.EBench.report() |> Enum.each(&IO.inspect/1)'
```

## In iex

`iex --sname fol -S mix` opens the live node. Each named node owns its store at
`.mnesiastore-<node>/`, so `iex --sname fol2 -S mix` starts an independent node.
`AL_MNESIA_DIR` overrides the directory. To retain an existing `.mnesiastore/`
on its original node, link its new path to it once:

```sh
ln -s .mnesiastore ".mnesiastore-fol@$(hostname -s)"
```

The front door returns a receipt for a proof; evaluation opens a query holding its first answer:

```elixir
ran = Zkfol.compile(Examples.EUser.fib(), args: [8])
query = Zkfol.eval!(Examples.EUser.fib(), [:_, :_])
Zkfol.Query.taken(query)           # [[1, 1]]
Zkfol.Query.next(query)            # {:ok, [2, 1]}
Zkfol.Query.close(query)
```

## Installation in GT

The inspector side lives under `src/` as Tonel packages, `BaselineOfZkfol` and
`Zkfol`, reading the running node over gt_bridge. Inspect a receipt for its Pipeline
and Trail views. From Objects, open `lay` for Grid and Join, or `emitted uair` for
Pointer grid, Cost, Commitment, and Failures. The live GT examples compose on the
Elixir examples, so the backing node must run this tree; the node-free examples
run against recorded feed fixtures. A fresh `load` also rides AL's GToolkit
tooling in, so the AL GUI displays alongside the grid.

```st
"fresh image: load Zkfol and the bridge and AL tooling declared by its baseline"
Metacello new
	repository: 'github://bellissimogiorno/20260627-zkfol-zinc-playground:main/src';
	baseline: #Zkfol;
	load
```

When you are hacking a work-in-progress bridge or AL, `load: #dev` loads only
`Zkfol` against what is already in the image and touches no pin. To load your
local checkout:
`repository: 'tonel://<repo>/src'; baseline: #Zkfol; load: #dev`.
