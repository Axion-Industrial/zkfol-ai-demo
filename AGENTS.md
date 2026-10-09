# zkfol_ai_demo

A demo of a proof-gated LLM agent, built as an ordinary Elixir project on top of
[zkFOL](https://github.com/zkFOL/zkfol). An agent's text or action is released only if a real
zkFOL proof shows it meets a published policy, and a separate verifier process checks the
proof from two files. Read `README.md` for the idea and `harness/README.md` for the run order,
the failure points and what the proofs do not say.

## Rules for this project

- **No mocks, stubs or simulated proofs.** False statements go to the real prover and fail
  there. The only replay modes are labelled on screen.
- **All data is synthetic.** Addresses use the reserved `.example` domain. The two inboxes
  are processes in the application, so nothing leaves the VM.
- **The API key comes from `ANTHROPIC_API_KEY`** in the environment, never from a file or a
  commit. Cloud sessions ignore it, so live model runs happen on a real machine.
- **No em dashes** in code, docs or commits (`bin/harness lint` checks this), and British
  English in prose.
- **zkFOL is a dependency, not a fork.** Anything that needs the compiler or its Rust crate
  changed goes to zkFOL as its own topic. The proof export and standalone verifier are on
  `zkfol-ai/proof-export` and string literals on `mariari/string-literals`; `mix.exs` points at
  `zkfol-ai/with-strings`, which merges both, until they are merged into zkFOL.

## Build, test, run

- `mix deps.get && mix compile`: builds zkFOL's NIF and the `zkfol_verify` binary (slow the
  first time).
- `MIX_ENV=test mix test`: runs the examples as tests (about 10 seconds).
- `mix format` (98 columns) and `bin/harness lint` before finishing.
- `bin/demo` (or `bin/demo --auto`): the guided demo for a recording, every act in order with a
  caption before and after each. It is `bin/harness demo` with the key and model set up.
- `bin/harness act1` to `act5`, `probe-injections`, `bench`, `published`, `package`,
  `lint`, `fixtures`, `keygen`, `sign-allowlist`. It runs in the test environment so the proving
  store stays apart from a development node.

Examples are the primary verification: run them, do not reason from signatures.

## Layout

- `lib/zkfol_ai_demo/`: the policies (`canon`, `policy`, `text`, `grounding`, `figures`,
  `trace`), the gate, the agent and its tools, the inboxes (`mailbox`, started by
  `application`), the acts, the guided demo (`demo`) and the benchmark.
- `lib/examples/`: examples, wired into `test/examples_test.exs`.
- `lib/mix/tasks/harness.ex` and `bin/harness`: the command line.
- `harness/`: published policies, the signed allowlist, synthetic documents, injection templates.

## Conventions

The coding conventions are in `.claude/skills/`: `general-conventions` and
`elixir-conventions`. Read them rather than relying on a paraphrase.
