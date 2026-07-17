# What the log affords a viewer

Ideas for a live proof view over `Zkfol.Log`, collected before building
anything. The discipline throughout: the log stays the only essential
state; every view here is a pure function of `snapshot/0`, and the
broker only tells a viewer *when* to re-derive, never *what*. If an
idea needs new state outside the log, it is wrong.

The vocabulary is already sufficient for most of this: `{:define, name,
value}` states, `{:prove_requested, name}` intends, `{:proved, report}`
/ `{:prove_failed, reason}` observe, and `basedon` is the provenance
arrow. The one writer rule for new facts: derivations stay pure
functions; the *caller who acts on one* journals the decision, based on
what it read. A rewrite is not an event -- choosing to prove the
rewritten statement is.

## Views, cheapest first

**Open obligations.** Intents without observations, with age and tier.
The prover currently owes N verdicts; the oldest is 40s into the
7040-bit tier. Today a long benchmark is a silent terminal; the log
already knows all of this.

**The image.** `Log.image/1` live: what is known now, each name with
its latest report, tier, prove/verify cost. After "a proof defines what
it proves", this view exists; a viewer is just its rendering.

**The time scrubber.** `image_down/2` at every id: drag through the
journal and watch knowledge accrete, definitions supersede, failures
land. Update Reconsidered's time axis made tangible. The diff of two
adjacent images answers "what did event 17 teach us?".

**Provenance threads.** `lifeline/2` unrolls define -> derived define
(the rewrite, journaled by its user with `basedon`) -> intent ->
observation. Click a claim, read why it is believed: fib(10000) = X
because this 14-column kernel was proven, derived from that 10000-column
statement, at this cost. Each rewrite edge carries its collapse ratio --
the doubling edge shows 10000 columns becoming 14.

**Two-route agreement.** When the same claim name is proven through two
threads (generic route and doubled route), the viewer can display their
values agreeing -- consensus derived from the journal, the
EDoubling.same_claim example as a standing fact instead of a one-shot
assertion.

**The refusal taxonomy.** `prove_failed` reasons grouped by kind:
non-affine pointer, unscheduled deref, negative cell, claim outside the
witness, no model, prover died. The compiler's refusals as data -- this
is the language-gap research instrument: which paper statements the
pipeline declines, measured from use rather than argued.

**Cost genealogy.** Reports carry prove_ms / verify_ms / num_vars /
backend, and EBench already proves under stable names. The journal
accumulates the measurement record across runs: the same name charted
over time is regression detection for free, `frozen_shapes` as a live
gate, and eventually `analysis/BASELINE.md` derived instead of frozen.

**Tier occupancy.** Which proofs needed 768-bit or 7040-bit cells, and
how close their witnesses came to the bound. Whether the wide tiers
earn their keep, from the record.

**Honesty markers.** Prover-death settlements (`terminate/2` debts) and
timeouts are ordinary events in the thread, so a statement's history
shows its infrastructure failures inline, not in a lost crash log.

## The zkFOL-specific one: displaying the boundary

The log is prover-side, so it may hold everything -- seeds, witnesses,
traces. A verifier is entitled only to claims, public columns, reports.
That makes the ZK boundary itself displayable: two projections of one
journal, the prover's image beside the public image, and the difference
between them is exactly what stays zero-knowledge. Needs one new
writer (whoever generates a witness journals seeds -> witness, based on
the statement); the projection is then a filter over bodies.

## Front end

Not in zkfol. `gt_bridge` is already a dep: Glamorous Toolkit connects
to the node, tails the broker as its invalidation signal, and renders
`events/0` as a `basedon` graph (libgraph is already transitive), with
`image` as a table and `image_down` as a scrubber. That viewer is the
broker's second subscriber -- the criterion by which the journal
apparatus fully pays for itself.
