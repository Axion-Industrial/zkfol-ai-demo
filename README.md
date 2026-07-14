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
(pinned at 13f540d) and interpreting the UAIR over three cell widths -- i64,
768-bit, and 7040-bit. Proving runs on a dedicated thread and answers to an id.
`analysis/` holds the frozen measurement record; the retired Python proof of
concept is on branch `attic/python`.

```sh
mix test          # every example, including live proofs through the NIF
mix dialyzer      # type checking
mix run -e 'Examples.EBench.report() |> Enum.each(&IO.inspect/1)'   # the benchmark
```
