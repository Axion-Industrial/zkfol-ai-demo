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

## Using zkFOL in your own project

zkFOL is a git dependency. This project's `mix.exs` shows the shape:

```elixir
{:zkfol,
 git: "https://github.com/Axion-Industrial/zkfol-ai-demo.git",
 branch: "zkfol-ai/proof-export"}
```

The branch adds proof export and a standalone verifier to zkFOL (about 660 lines, nothing else
changed). Once it is merged the line becomes
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

You need Elixir 1.18 on OTP 27 and Rust (rustup fetches the pinned toolchain). All data in
this repository is synthetic.
