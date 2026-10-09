# zkfol_ai_demo

A cryptographic safety harness for an LLM agent, built on [zkFOL](https://github.com/zkFOL/zkfol).

The agent writes text and takes actions. Nothing is released and nothing runs unless a zkFOL
proof says it satisfies a published policy. A verifier that has never seen the text accepts or
rejects the proof from two files. Everything runs the real prover (Zinc+, through zkFOL's
Rustler NIF), and a prompt-injected agent still cannot send anything the policy forbids.

There are three policies, and each is a relation in zkFOL's own language: no em dash in the
text, every figure in the text appears in the sources, and an action trace in which every
write and mail goes to a signed-allowlist destination after an approval. See
[harness/README.md](harness/README.md) for the five acts, the run order for a live demo, the
failure points and what the proofs do not say, and [RESULTS.md](RESULTS.md) for measured times
and proof sizes.

## The policies in zkFOL's own language

Each policy is a few `defrel` clauses, and nothing else is the policy. zkFOL's pipeline derives
the witness and lowers the relation to the predicate the prover is given. The first one fits in
one relation (`lib/zkfol_ai_demo/no_dash.ex`):

```elixir
defrel no_dash(text) do
  absent(8212, text)    # no codepoint of the text is U+2014
end
```

A text is its list of codepoints, using the string-literals topic. The other two are
`lib/zkfol_ai_demo/grounded.ex` (every figure is a `member` of the sources) and
`lib/zkfol_ai_demo/conduct.ex` (a run is a list of events: a write needs an earlier approval,
and every write and mail needs a destination in the allowlist, found by a recursive `entry`).
The SHA-256 of each file is a public input of every proof made under it.

`Examples.ENoDash` proves a clean text with the real prover and shows a dashed one has no
answer, so zkFOL proves nothing. The harness still runs the real prover on a dashed text, so a
refusal can be watched: it derives the nearest text the rule holds of, with each dash replaced
by a space, and puts the real codepoints in the committed columns. That witness cannot satisfy
the rule, and the prover fails with `AssertZero(0)`. The same is done for an action trace (each
refused event becomes a retrieval, found by asking the relation) and for figures the sources
lack. `ZkfolAiDemo.Canon` first normalises the ways a dash can be smuggled in, so the relation
only has to forbid one codepoint.

Two limits of the compiler shape this. It stops at 3,000 unrolled sites, which is 999
codepoints of text, so the demo asks the model for about 80 words. And its lookup check works
in 32-bit words, so a destination, which is 128 bits of a hash, is carried as four words. Both
are shown in `Examples.ENoDash` and `Examples.ETrace`, and both would move with the compiler.

## Using zkFOL in your own project

zkFOL is a git dependency. This project's `mix.exs` shows the shape:

```elixir
{:zkfol,
 git: "https://github.com/Axion-Industrial/zkfol-ai-demo.git",
 branch: "zkfol-ai/with-strings"}
```

The branch is zkFOL plus two topics: proof export with a standalone verifier (about 660
lines, on `zkfol-ai/proof-export`) and string literals (`mariari/string-literals`). Once it is merged the line becomes
`{:zkfol, git: "https://github.com/zkFOL/zkfol.git"}`.

Because it is a dependency, add the same overrides zkFOL needs (`gt_bridge`, `al`) and copy
the `config :al` block from `config/config.exs`.

## Run it

```sh
mix deps.get
mix compile                         # builds the NIF and verifier, a few minutes cold
MIX_ENV=test mix test               # the examples, run as tests
export ANTHROPIC_API_KEY=...        # only for the live model acts
export ZKFOL_MODEL=claude-haiku-4-5
bin/harness act2 --topic "a short note about autumn"
```

To record the demo for someone else to watch, run `bin/demo` (or `bin/demo --auto`, which needs
no key presses). It asks for your AI key without showing it, then plays every act in order, each
with a plain-English caption, so the recording explains itself.

You need Elixir 1.18 on OTP 27 and Rust (rustup fetches the pinned toolchain). All data in
this repository is synthetic.
