# Zkfol

zkFOL in Elixir: the logic of *zk-SNARKs for First Order Logic* (Gabbay–Mendelsohn),
arithmetised to a uniform AIR and proved through Zinc+. A single Elixir application
drives the Zinc+ prover **in-process via a Rustler NIF** (not an external runner).

## Conventions (source of truth — read them)

The project's coding and git conventions live as skills in `.claude/skills/`. Read
them; do not rely on paraphrase (they evolve):

- `general-conventions/SKILL.md` — language-agnostic: minimize code, generalize
  don't special-case, dead code is noise, typed cross-module structures, **run
  examples before reviewing**, the anti-patterns (never add scope / single-use
  abstractions / handle impossible errors), the failure protocol.
- `elixir-conventions/SKILL.md` — pattern-match in heads, `with` over nested `case`,
  never nest reduces, map-then-combine over stateful reduce, `typedstruct`, ExExample.
- `git-conventions/SKILL.md` — the topic-branch DAG (base/next/main/maint, one concern
  per topic, base-on/merge, no evil merges, fold fixes to origin).
- `code-review/SKILL.md` — invoked on demand for reviews.

## Build / test / run

- `mix compile` — compiles Elixir + the Rust NIF (`native/zkfol_zinc_plus`, rustler).
  The NIF build is slow; avoid needless recompiles.
- `mix test` — runs the examples as tests (`test/examples_test.exs` wires each
  `Examples.E<Module>` in via `use ExExample.ExUnit`).
- `mix dialyzer` — type check (config in `.dialyzer_ignore.exs`).
- `mix format` — 98-char lines; run before finalizing.
- One-off: `timeout 60 mix run -e 'Examples.EFacts.factorial()'` (never `--no-halt`).
- Examples live in `lib/examples/e_<module>.ex`, module `E<Module>`. They are the
  primary verification — **run them, don't reason from signatures**.

## The pipeline (what compiles a statement to a proof)

A `Zkfol.Statement` flows through a `Zkfol.Pipeline` of passes (each `{module, opts}`),
its stage a sum-type — `Raw` → `Lowered` → `Solved`:

- `Zkfol.Lang` — the relational surface: `defrel`/`rel` macros → a predicate (`Ast`).
- `Zkfol.Al` — the AL backend: runs the statement as clauses, the derivation IS the
  witness (judged by the oracle). `Zkfol.Facts` reads order-2 descriptors; `Zkfol.Doubling`
  rewrites recurrences to a log-depth kernel.
- `Zkfol.Witness` — derives the witness via `Al.solve`.
- `Zkfol.Uair` — `emit/3` translates a Solved statement to Figure 2 over committed
  columns; `prove/3` proves it on Zinc+. Mode is a sum: `Uair.Plain | Lookup | Composed`
  (`Composed` = Section 4 lowering for unscheduled pointers; its reads prove
  natively on Zinc+'s pointer query).
- `Zkfol` — the front door: `compile/2` / `emit/2`, journalling the whole act.

Cross-cutting: `Zkfol.Ast` (the algebra, Figure 2), `Zkfol.Refusal` (typed refusals —
`{reason, detail}`, never string errors), `Zkfol.Log` (the command log = the only durable
state, mnesia; `application.ex` runs `Log.setup` + the `Prover`), `Zkfol.Interpretation`/
`Semantics`/`Range` (the witness oracle), `Zkfol.ZincPlus` (the NIF boundary).

`src/` is a **Glamorous Toolkit** Tonel package (live views over a uair, the pipeline as
a graph) that reads the running node over `gt_bridge` — independent of `lib/`.

## Git workflow — topic-branch DAG (see git-conventions skill)

Topics form a DAG off `base`/`main`, not a linear spine. A commit compiles and passes its
examples; a topic is a unit of concern. Single-prerequisite topics **base on** their
prereq; multi-prerequisite topics **merge** the minimal set (transitive-reduced — never
double-merge). `next` is a rebuildable collector: never rebase onto it or build on it;
topics enter only by merge. Bug fixes fold into the commit that introduced them. Commit
messages end with `Co-Authored-By:` only — **never a session-URL trailer** (dead link).

## Project-specific notes

- Zinc+ is a cargo git dep on the `mariari/zinc-plus` fork. The trace column wall depends
  on the pinned `PnttConfig`; read `native/zkfol_zinc_plus/src/config.rs` for the current
  limit rather than quoting a number (it moves with the pin).
- `src/` (Glamorous Toolkit) and `lib/` diverge in both directions — some GT work is done in
  the image, some on disk. Never export the image wholesale over the worktree; splice per file.
