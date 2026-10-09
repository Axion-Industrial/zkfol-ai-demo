# zkfol_ai_demo

A cryptographic safety harness for an LLM agent, built on [zkFOL](https://github.com/zkFOL/zkfol).

The agent writes text and takes actions. Nothing is released and nothing runs unless a zkFOL
proof says it satisfies a published policy. A verifier that has never seen the text accepts or
rejects the proof from two files. Everything runs the real prover (Zinc+, through zkFOL's
Rustler NIF), and a prompt-injected agent still cannot send anything the policy forbids.

There are three policies: no em dash in the text, every figure in the text appears in the
sources, and an action trace in which every write and mail goes to a signed-allowlist
destination after an approval. See [harness/README.md](harness/README.md) for the five acts,
the run order for a live demo, the failure points and what the proofs do not say, and
[RESULTS.md](RESULTS.md) for measured times and proof sizes.

## The no-dash check in zkFOL's own language

The whole policy fits in one relation (`lib/zkfol_ai_demo/no_dash.ex`):

```elixir
defrel no_dash(text) do
  absent(8212, text)    # no codepoint of the text is U+2014
end
```

A text is its list of codepoints, using the string-literals topic. `Examples.ENoDash` proves a
clean text with the real prover and shows a dashed one has no answer, so nothing is proved.
The harness's own check (`ZkfolAiDemo.Canon`) first normalises the ways a dash can be
smuggled in, then proves the same absence.

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
