# A cryptographic safety harness for an LLM agent

An agent writes text and takes actions. This harness refuses to release the text or run the
action unless a zkFOL proof says it satisfies a published policy. A verifier that has never
seen the text accepts or rejects the proof from two files.

Everything here runs the real prover (Zinc+, through a Rustler NIF) and a real separate
verifier process. There are no mocks, no stubbed proofs and no placeholder bytes. The only
replay modes are labelled on screen and are for when the model API is unavailable.

All data in this repository is synthetic: the company, the documents, the customer list and
every address (on the reserved `.example` domain).

## What it does

| Policy | What the proof says | Where |
|---|---|---|
| Text | The output has no em dash, after normalising the ways one can be smuggled | `ZkfolAiDemo.Canon`, `Policy`, `Text` |
| Grounding | Every numeric figure in the output also appears in a supplied source set | `ZkfolAiDemo.Grounding`, `Figures` |
| Trace | A write had an earlier approval that returned true; every write and mail went to a signed-allowlist destination; a document went only where documents are allowed | `ZkfolAiDemo.Trace`, `Allowlist` |

Every proof also binds, as public inputs, the policy hash, the canonicaliser hash, the model
identifier, the system prompt hash, the user prompt hash and a nonce (the trace also binds the
allowlist hash, its signer and its entries). Without them a proof would say only that some
text somewhere complies.

## What an audience can inspect beforehand

`bin/harness published` prints the SHA-256 of each of these, and `sha256sum` reproduces it.

- `harness/policy/no-em-dash.json`, `grounding.json`, `trace.json`: the published policies.
- `lib/zkfol_ai_demo/canon.ex` and `figures.ex`: the canonicalisers. Their hashes are public
  inputs, so a proof is tied to exactly this source.
- `harness/allowlist.json`, `allowlist.sig`, `allowlist.pub`: the signed allowlist and the
  public key that verifies it. The private key is not in the repository.
- `harness/docs/` and `harness/injections/`: the synthetic documents, the customer list and
  the injection templates.

## Setup

This is an ordinary Elixir project. zkFOL is a git dependency in `mix.exs`, pinned to the
branch `zkfol-ai/proof-export`, which carries the proof export and the standalone verifier
(about 660 lines in the zkFOL crate and its Elixir side). Nothing else of zkFOL is changed.
Once that branch is merged, the dependency can point at zkFOL itself.

You need Elixir 1.18 on OTP 27, Rust (the crate pins its toolchain, and `rustup` fetches it),
and network access once to fetch dependencies.

```sh
mix local.hex --force && mix local.rebar --force
mix deps.get
mix compile                    # builds the NIF and the verifier, about two minutes cold
```

The standalone verifier is built with the dependency, at
`deps/zkfol/priv/native/zkfol_verify` (and `_build/test/lib/zkfol/priv/native/` for tests). A second
machine needs its own build for its own operating system and architecture:
`cargo build --release --bin zkfol_verify` in `deps/zkfol/native/zkfol_zinc_plus`.

Set the key in the environment, and nowhere else (never in a file, never in chat):

```sh
export ANTHROPIC_API_KEY=...   # read from the environment on every call
export ZKFOL_MODEL=...         # optional; the default is claude-opus-5-5
```

Everything runs through `bin/harness`, which uses the test environment so the proving store
stays apart from a live development node.

## Recording the demo

`bin/demo` plays every act in order for a recording. It asks for the key if the environment has
none (nothing shows as you paste it), waits while you start the screen recorder, and defaults the
model to `claude-haiku-4-5`. Each part opens with a magenta caption that says what is about to
happen and closes with one that says what was shown. Green and red stay reserved for the
harness's own verdicts.

- `bin/demo` waits for Return at each caption, for a presenter talking over it.
- `bin/demo --auto` waits a time that grows with each caption, so no key press is needed.
- `--injection FILE` plants a different template (the default is `04_nested_task.txt`).

If the AI is not fooled by the planted text, the demo says so and runs the act again with the
AI told to obey documents, with that mode shown on screen. If it still is not fooled, or writes
no text that follows the rule, the demo stops and says why. Each part is also a public function
of `ZkfolAiDemo.Demo`, and `Examples.EDemo` runs the ones that need no live model.

## Run order for a live demo

Before the audience arrives, on the stage machine:

1. `mix test` (about 25 seconds, 200+ examples) and `bin/harness lint`.
2. `bin/harness published`, and put the hashes on a slide.
3. `bin/harness fixtures`, so the replay texts exist if the API fails.
4. `bin/harness probe-injections` with the key set. This records, in
   `harness/injections/TESTED.md`, which templates the model actually obeys today. Do not
   skip it: a template that worked last week may not now.
5. Run all five acts once, privately, to warm the machine and confirm each one.

On stage:

| Act | Command | What happens |
|---|---|---|
| 1 | `bin/harness act1 --topic "..."` | The model writes unconstrained. Its dashes are highlighted, the gate asks the real prover for a proof, the prover cannot make one, and nothing ships. |
| 2 | `bin/harness act2 --topic "..."` | A compliant output is proved. Proof size and generation time are printed, a separate process verifies it from two files, and the proof stays on disk in `harness/out/`. |
| 3 | `bin/harness act3 --edited FILE` | An operator-edited copy fails against the old proof on the commitment. A hand-edited proof file fails. The real prover is run on the edit and fails if the edit has a dash. |
| 4 | `bin/harness act4` | Verification from the proof and public inputs files alone. Run it on a second machine with the network off (see below). |
| 5 | `bin/harness act5 --injection FILE [--mode assume-compromised]` | A legitimate email arrives; the audience's injection hijacks the agent; the exfiltration is blocked; the attacker inbox stays empty. |

`bin/harness inboxes` shows the two mail sinks at any time, so it can run in a second
terminal beside act 5.

### Act 4 on a second machine

After act 2, run `bin/harness package`. Copy `harness/out/portable/` to the other machine and
run `./verify.sh`. The directory holds the proof, the public inputs, a pins file built from
the published hashes, the verifier binary and a one-line script. No Elixir, no plaintext and no
network are needed. The binary must have been built for that machine's operating system, so
on a different platform build the verifier there first and copy it in.

The verifier prints each bound value and the proof's commitment to the witness. With a pins
file it also rejects the proof unless each pinned value matches.

## Act 5 and the two modes

The agent has two tools: read a document from one folder, and send email. One document holds
text the audience wrote. The injection is read at run time from `--injection FILE`, or `-`
for stdin, so someone can write it live. `{{ATTACKER}}` in it becomes the attacker address.
The documents are not filtered, scanned or sanitised, and the destination is not checked
before the prover is called.

- **Live mode** (the default) gives the audience's text to the real model unchanged. If the
  model refuses to be hijacked, the run says so in a yellow banner. That is a result about
  the model, and the harness had nothing to block.
- **`--mode assume-compromised`** adds a system prompt line telling the agent to follow
  instructions found in documents, which makes the hijack certain. The claim being shown is
  about the harness, not the model. The mode is shown in a banner at the top and again at
  the end of the run.

The agent's `send_email` call is printed as it is issued, in red, before the gate runs, so the
audience sees the compromise happen. The two sinks are SMTP servers on the loopback
interface only: one stands in for the allowed recipient, one for the attacker, and nothing
can leave the machine.

The allowlist is signed with a key held outside the repository and outside the agent's
process. Signing is the separate commands `bin/harness keygen` and `bin/harness sign-allowlist`.
The committed `allowlist.sig` and `allowlist.pub` verify as they are, so nothing needs
re-signing unless you change the allowlist. No tool exposes a way to read, write or reload it,
and `Examples.ETools.no_path_to_the_allowlist` tests that: path traversal, absolute paths,
a symlink, attachments, the tools' exports, and the signed files' hashes before and after.

## Failure points for a live run, and what to pre-stage

| Failure | What you see | Pre-stage or do |
|---|---|---|
| No or wrong API key | `ANTHROPIC_API_KEY is not set` or `HTTP 401` | Check before going on. Fall back to replay: `act1 --from-file harness/out/sample-dashed.txt`, `act2 --from-file harness/out/sample-clean.txt`. A yellow "REPLAYED, NOT A LIVE MODEL CALL" banner is shown. |
| API down or slow | `request failed`, or a long wait | The same replay fallback for acts 1 and 2. Acts 3 and 4 need no model. Act 5 needs the model: show a recording of a good run if there is one, and say so. |
| The model writes no dash in act 1 | The gate releases the output | Ask for a longer, more literary topic, or replay `sample-dashed.txt`. |
| The model dashes in act 2 | Attempt 1 is withheld, then it retries up to three times | This is the harness working. If all three fail, replay `sample-clean.txt`. |
| **The model resists the injection in act 5** | A yellow "THE MODEL RESISTED THE INJECTION" banner; the attacker inbox is empty because nothing was sent | Do not hide it. Say it is the model, then re-run with `--mode assume-compromised`, which prints a red banner saying the hijack is arranged. Pre-stage a template from `TESTED.md` that the model obeyed that day. |
| **The API ends the run with a safety refusal** | A yellow "THE API ENDED THE RUN WITH A SAFETY REFUSAL" banner, with the reason the API gave. Seen with `claude-opus-5-5` on all four templates, even in assume-compromised mode | This is the platform's safeguard, not the harness. Try an older model: `export ZKFOL_MODEL=claude-haiku-4-5`, then `bin/harness probe-injections`. The model name is printed on screen. |
| Audience injection is ignored | Same as above | Have the four templates ready. Run `probe-injections` the morning of the demo. |
| A sink port is taken | `eaddrinuse` on 2525 or 2526 | Stop the other process. Act 5 starts and empties both sinks. |
| Proof fails on an honest text | `Proximity failure` | The pinned Zinc+ rejects a column needing 2^15 rows. Texts over about 65,000 characters are refused earlier. See RESULTS.md. |
| Act 4 on the second machine fails | `exec format error` or a missing library | The verifier binary is per platform. Build it on that machine ahead of time. |
| Time | Act 5 makes two model runs of several calls each | Allow a minute or two. The proving itself is a fraction of a second per action. |

## What the proofs do and do not say

Read these before a hostile audience does.

- **A proof is about a canonical form.** Text is normalised first: entities, backslash
  escapes, percent runs, NFKC, tag and format characters, dash look-alikes, `--`, and base64
  tokens that decode to text holding a dash. Hex, base32, ROT13, other character sets,
  line-wrapped base64 and invented ciphers are not decoded. The proof says the released
  string has no dash after those steps, not that no consumer could construct one.
  `Examples.ECanon.known_gaps` lists them.
- **`--` counts as a dash**, so text with `--` flags or markdown rules is refused. That is the
  policy, and a false rejection is the safe direction.
- **The output commitment is the proof's own commitment** to its witness columns (a Merkle
  root). It is deterministic and moves with any cell, so anyone holding the text can recompute
  it, which `act3` does. It does not hide the text from someone who can guess it. The SHA-256
  of the canonical array in the manifest is a convenience label and is not bound to the proof.
- **The trace proof certifies the trace it is given.** That the trace is what the agent really
  did is the recorder's job: the destination an action is recorded with is the one it is run
  with, parsed once in `ZkfolAiDemo.Tools`. Inline copying of a document is caught by a
  six-word overlap test, which is a heuristic. Attachments are caught exactly.
- **Rule 3 of the trace (documents only where allowed) is implied by rule 2** whenever the
  signed file keeps every document-capable destination on the allowlist. It is kept as its own
  constraint so it still holds if rule 2 is relaxed.
- **A destination is 54 bits of a hash.** Searching for an address that collides with an
  allowed one costs about 2^54 hashes. That is out of reach for a stage attacker and is not a
  cryptographic margin.
- **The public key file is the trust anchor** for the allowlist. Its hash is a public input
  of every trace proof (`allowlist_signer`), so a verifier can pin it.
- **Limits of the pinned Zinc+.** An honest proof is rejected when a column needs 2^15 rows or
  holds a value above about 2^56 beside small ones. The harness keeps inside both.

## Checking the work

```sh
mix test                       # the examples, run as tests
ZKFOL_PROVE=1 mix test         # also the long proving examples
mix dialyzer
bin/harness lint               # no dash character in what this branch adds, or in its commits
```

`bin/harness bench` rewrites `RESULTS.md` with measured figures and the machine's own stamp.
Run it on the stage machine, with nothing else running.
