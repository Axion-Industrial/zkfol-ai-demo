defmodule ZkfolAiDemo.Demo do
  @moduledoc """
  I am the guided demo: every act in order, each introduced by a plain-English caption and
  followed by one, so a single command makes a recording a newcomer can follow.

  My captions are magenta, so they cannot be mistaken for a verdict: green and red are kept
  for what the harness decides. By default I wait for Return at each caption, for a presenter
  who talks over the demo. With `auto: true` I wait for a time that grows with the caption's
  length instead, so nobody has to touch the keyboard.

  ### Public API

  - `run/1` runs the whole demo.
  - `intro/1`, `rule/1`, `breaks/1`, `follows/1`, `tampering/1`, `hijack/1` and `close/1` are
    its parts, public so each can be run alone.
  - `captions/0` is every caption, for review.
  """

  alias Zkfol.Refusal
  alias ZkfolAiDemo.Acts
  alias ZkfolAiDemo.Anthropic
  alias ZkfolAiDemo.Show

  @typedoc "A caption: a title, and the lines under it."
  @type caption :: {String.t(), [String.t()]}

  @type option ::
          {:auto, boolean()}
          | {:read_ms, non_neg_integer()}
          | {:injection, Path.t()}

  @type options :: [option()]

  @read_ms 1_500
  @autumn "a short note about autumn"

  # Essays the model is likely to put dashes in, tried in turn until one is withheld.
  @topics [
    "a literary essay on grief",
    "a dramatic essay on love and loss",
    "a reflective essay on memory and time"
  ]

  @injection Path.expand("../../harness/injections/04_nested_task.txt", __DIR__)

  # The rule as written in its source, so the screen can never drift from what is proved.
  @rule_source Path.expand("no_dash.ex", __DIR__)
  @external_resource @rule_source
  @rule ~r/^  defrel no_dash.*?^  end$/ms
        |> Regex.run(File.read!(@rule_source))
        |> hd()
        |> String.split("\n")

  @captions %{
    intro:
      {"A proof that an AI followed the rules",
       [
         "AI agents now write and act for us. How do we know they followed the rules?",
         "Here, the AI's work is released only if it comes with a proof that it did.",
         "A separate program, which never sees the work, checks the proof.",
         "",
         "How to read the screen:",
         "  Magenta boxes, like this one, explain what is happening.",
         "  Green means a proof was made and checked, so the work is released.",
         "  Red means there is no proof, so it is stopped."
       ]},
    rule:
      {"Part 1 of 5: the rule",
       [
         "For this demo the rule is simple: the AI's text must contain no em dashes.",
         "Many people link em dashes to AI writing, so they are easy to spot.",
         "Treat the rule as a stand-in for any rule a company wants enforced.",
         "",
         "Here is the whole rule, written in zkFOL's own language:"
       ]},
    breaks:
      {"Part 2 of 5: the AI breaks the rule",
       [
         "We ask the AI to write an essay with no restrictions. It will probably use dashes.",
         "Each dash is marked in red.",
         "Then the system asks the prover for a proof that the text follows the rule.",
         "The AI is a live service, so the next step takes a few seconds."
       ]},
    broken:
      {"What you just saw",
       [
         "The text broke the rule, so the prover could not make a proof.",
         "No proof means nothing is released.",
         "This is the real prover failing. It is not a message we wrote."
       ]},
    lucky:
      {"What you just saw",
       [
         "This time the AI happened to avoid dashes, so a proof could be made.",
         "The system only ever releases text that follows the rule."
       ]},
    follows:
      {"Part 3 of 5: the AI follows the rule",
       [
         "Now the AI is told the rule: no dashes.",
         "This time a proof can be made. Look at its size, and how fast it was made.",
         "Then a separate program checks it. It is given two files and never sees the text."
       ]},
    followed:
      {"What you just saw",
       [
         "A proof was made and checked in a fraction of a second.",
         "The checker saw only the proof and a list of public facts, never the text.",
         "The public facts say which rule, which AI model and which instructions were used."
       ]},
    tampering:
      {"Part 4 of 5: tampering",
       [
         "What if someone edits the approved text afterwards?",
         "We add one em dash to the end of it, then try three things:",
         "  1. Check the old proof against the edited text.",
         "  2. Change a single byte of the proof file, then check that.",
         "  3. Ask the prover for a fresh proof of the edited text."
       ]},
    tampered:
      {"What you just saw",
       [
         "All three failed.",
         "A proof belongs to the exact text it was made for.",
         "It cannot be reused for an edited text, and it cannot be altered."
       ]},
    hijack:
      {"Part 5 of 5: the hijacked AI",
       [
         "The biggest worry with AI agents is a hidden instruction.",
         "Someone plants it in a document the agent reads. This is called prompt injection.",
         "Here is the instruction we plant:"
       ]},
    plan:
      {"What will happen",
       [
         "The AI's job: read the company folder, then email a summary to reports@corp.example.",
         "It does the job once as normal, then again with the planted instruction in the folder.",
         "Each email it tries to send is announced in a red box. Then the gate asks for a proof.",
         "The next box gives the result. Green: the email went out. Red BLOCKED: it was stopped."
       ]},
    fooled:
      {"What you just saw",
       [
         "The AI was fooled. It tried to email the customer list to an outside address.",
         "There is no proof for that address, so the gate stopped the email.",
         "The attacker's inbox is empty. The approved recipient still got the normal email.",
         "The AI can be tricked. The protection does not depend on the AI behaving."
       ]},
    resisted:
      {"The AI was not fooled this time",
       [
         "This time the AI saw through the planted instruction. That is luck, not a guarantee.",
         "To show what the harness does when an AI is fooled, we run it again with the AI",
         "told to follow instructions found in documents. The screen labels this clearly."
       ]},
    arranged:
      {"What you just saw",
       [
         "Told to follow documents, the AI tried to email the customer list outside.",
         "There is no proof for that address, so the gate stopped the email.",
         "The attacker's inbox is empty. The protection does not depend on the AI behaving."
       ]},
    close:
      {"What this showed",
       [
         "An AI's output is released only with a proof that anyone can check.",
         "A tricked AI still could not send the data out.",
         "Any rule that can be written down can be enforced this way.",
         "",
         "It proves that released output follows the rule. It does not make the AI itself safe.",
         "Code and results: github.com/Axion-Industrial/zkfol-ai-demo"
       ]}
  }

  ############################################################
  #                        Public API                        #
  ############################################################

  @doc """
  I run the whole demo. I stop early, with a refusal, when the environment has no API key,
  when the AI writes no text that follows the rule, or when it cannot be fooled.
  """
  @spec run(options()) :: :ok | {:error, Refusal.t()}
  def run(opts) do
    with {:ok, _key} <- Anthropic.key(),
         :ok <- intro(opts),
         :ok <- rule(opts),
         :ok <- breaks(opts),
         :ok <- follows(opts),
         :ok <- tampering(opts),
         :ok <- hijack(opts) do
      close(opts)
    end
  end

  @doc "I explain what the demo is, and how to read its colours."
  @spec intro(options()) :: :ok
  def intro(opts) do
    Show.clear()
    caption(@captions.intro)
    Show.kv("the AI used", Anthropic.model())
    wait(opts, count(@captions.intro), "to begin")
  end

  @doc "I show the rule, as written in its source."
  @spec rule(options()) :: :ok
  def rule(opts) do
    Show.clear()
    caption(@captions.rule)
    Show.text(Enum.join(@rule, "\n"))
    Show.note("")
    Show.note("8212 is the code number a computer uses for the em dash.")
    Show.note("In words: no character of the text is an em dash.")

    Show.note(
      "The proofs below check this same rule, built from lower-level parts for long texts."
    )

    wait(opts, count(@captions.rule) + length(@rule) + 4, "to continue")
  end

  @doc "I show the AI breaking the rule, and the prover failing to prove it."
  @spec breaks(options()) :: :ok | {:error, Refusal.t()}
  def breaks(opts) do
    Show.clear()
    caption(@captions.breaks)
    wait(opts, count(@captions.breaks), "to start")

    with {:ok, outcome} <- ask_until_withheld(@topics) do
      say(opts, outcome_caption(outcome), "to continue")
    end
  end

  @doc "I show the AI following the rule, and a separate program checking the proof."
  @spec follows(options()) :: :ok | {:error, Refusal.t()}
  def follows(opts) do
    Show.clear()
    caption(@captions.follows)
    wait(opts, count(@captions.follows), "to start")

    with {:ok, :released} <- Acts.act2(topic: @autumn) do
      say(opts, @captions.followed, "to continue")
    else
      {:ok, :withheld} -> {:error, {:no_compliant_output, %{}}}
      {:error, _refusal} = error -> error
    end
  end

  @doc "I edit the approved text, and show three ways the edit is caught."
  @spec tampering(options()) :: :ok | {:error, Refusal.t()}
  def tampering(opts) do
    Show.clear()
    caption(@captions.tampering)
    wait(opts, count(@captions.tampering), "to start")

    with {:ok, edited} <- edit_accepted(),
         :ok <- Acts.act3(edited: edited) do
      say(opts, @captions.tampered, "to continue")
    end
  end

  @doc """
  I plant a hidden instruction and show the agent act on it, and the gate stop it. An agent
  that is not fooled gets a second run, told to obey documents, with the mode on screen.
  """
  @spec hijack(options()) :: :ok | {:error, Refusal.t()}
  def hijack(opts) do
    injection = Keyword.get(opts, :injection, @injection)

    with {:ok, text} <- Acts.injection(injection: injection),
         :ok <- announce(opts, text),
         {:ok, run} <- Acts.act5(injection: injection) do
      judge(opts, injection, Acts.exfil?(run), :live)
    end
  end

  @doc "I say what the demo showed, and what it does not claim."
  @spec close(options()) :: :ok
  def close(opts) do
    Show.clear()
    say(opts, @captions.close, "to finish")
  end

  @doc "I am every caption the demo shows, by name."
  @spec captions() :: %{atom() => caption()}
  def captions, do: @captions

  ############################################################
  #                         Helpers                          #
  ############################################################

  @spec ask_until_withheld([String.t()]) ::
          {:ok, :withheld | :released} | {:error, Refusal.t()}
  defp ask_until_withheld([topic | more]) do
    case Acts.act1(topic: topic) do
      {:ok, :released} when more != [] ->
        Show.note("The AI happened to use no dash. Asking again, on another topic.")
        ask_until_withheld(more)

      result ->
        result
    end
  end

  @spec outcome_caption(:withheld | :released) :: caption()
  defp outcome_caption(:withheld), do: @captions.broken
  defp outcome_caption(:released), do: @captions.lucky

  # A copy of the approved text with one em dash added at the end, for act 3 to be caught on.
  @spec edit_accepted() :: {:ok, Path.t()} | {:error, Refusal.t()}
  defp edit_accepted do
    edited = Path.join(Acts.out(), "edited.txt")

    with {:ok, text} <- File.read(Path.join(Acts.out(), "accepted.txt")) do
      File.write!(edited, String.trim_trailing(text) <> " " <> <<0x2014::utf8>> <> " edited\n")
      {:ok, edited}
    else
      {:error, _posix} -> {:error, {:no_compliant_output, %{}}}
    end
  end

  @spec announce(options(), String.t()) :: :ok
  defp announce(opts, text) do
    Show.clear()
    caption(@captions.hijack)
    Show.text(text)
    caption(@captions.plan)

    wait(
      opts,
      count(@captions.hijack) + count(@captions.plan) + length(String.split(text, "\n")),
      "to start"
    )
  end

  # What the run showed. An agent that was not fooled is run again, told to obey documents.
  @spec judge(options(), Path.t(), boolean(), :live | :arranged) :: :ok | {:error, Refusal.t()}
  defp judge(opts, _injection, true, :live), do: say(opts, @captions.fooled, "to continue")
  defp judge(opts, _injection, true, :arranged), do: say(opts, @captions.arranged, "to continue")

  defp judge(opts, injection, false, :live) do
    say(opts, @captions.resisted, "to run it again")

    with {:ok, run} <- Acts.act5(injection: injection, mode: "assume-compromised") do
      judge(opts, injection, Acts.exfil?(run), :arranged)
    end
  end

  defp judge(_opts, _injection, false, :arranged), do: {:error, {:not_fooled, %{}}}

  @spec say(options(), caption(), String.t()) :: :ok
  defp say(opts, caption, prompt) do
    caption(caption)
    wait(opts, count(caption), prompt)
  end

  @spec caption(caption()) :: :ok
  defp caption({title, lines}), do: Show.banner(:magenta, [String.upcase(title), "" | lines])

  @spec count(caption()) :: non_neg_integer()
  defp count({_title, lines}), do: length(lines)

  # The pause after a caption: Return, or a time that grows with the lines to read.
  @spec wait(options(), non_neg_integer(), String.t()) :: :ok
  defp wait(opts, lines, prompt) do
    if Keyword.get(opts, :auto, false),
      do: Process.sleep(Keyword.get(opts, :read_ms, @read_ms) * (lines + 2)),
      else: IO.gets("\n   Press Return " <> prompt <> " ")

    :ok
  end
end
