defmodule Examples.EDemo do
  @moduledoc """
  I am the examples of the guided demo: each part that needs no live model, run for real, and
  the wording of every caption checked.
  """

  use ExExample

  import ExUnit.Assertions
  import ExUnit.CaptureIO

  alias ZkfolAiDemo.Acts
  alias ZkfolAiDemo.Demo
  alias ZkfolAiDemo.Refusal
  alias ZkfolAiDemo.Show

  # No waiting, so the examples run at the speed of the code.
  @quick [auto: true, read_ms: 0]

  @doc "Every caption line fits the screen and holds no dash, so a recording never wraps or breaks the demo's own rule."
  @spec captions_fit_the_screen() :: %{atom() => Demo.caption()}
  example captions_fit_the_screen do
    captions = Demo.captions()

    for {_name, {title, lines}} <- captions, line <- [title | lines] do
      assert String.length(line) <= 90, line
      assert Show.dashes(line) == 0, line
    end

    captions
  end

  @doc "The rule on screen is the rule in its source, with the number that means an em dash."
  @spec the_rule_is_shown_as_written() :: String.t()
  example the_rule_is_shown_as_written do
    out = capture_io(fn -> assert :ok = Demo.rule(@quick) end)

    assert out =~ "defrel no_dash(text) do"
    assert out =~ "absent(8212, text)"
    out
  end

  @doc "The intro names the colours the rest of the demo relies on."
  @spec the_intro_names_the_colours() :: String.t()
  example the_intro_names_the_colours do
    out = capture_io(fn -> assert :ok = Demo.intro(@quick) end)

    assert out =~ "Green means"
    assert out =~ "Red means"
    out
  end

  @doc "An edit to the approved text is caught three ways: the old proof, a flipped byte, and the prover."
  @spec tampering_is_caught_three_ways() :: String.t()
  example tampering_is_caught_three_ways do
    capture_io(fn -> Acts.fixtures() end)
    clean = Path.join(Acts.out(), "sample-clean.txt")
    capture_io(fn -> assert {:ok, :released} = Acts.act2(topic: "autumn", from_file: clean) end)

    out = capture_io(fn -> assert :ok = Demo.tampering(@quick) end)

    assert length(Regex.scan(~r/\[REJECTED\]/, out)) == 2
    assert out =~ "OUTPUT WITHHELD"
    out
  end

  @doc "Without an API key the demo stops before it prints anything, and says why."
  @spec no_key_stops_the_demo_at_once() :: :ok
  example no_key_stops_the_demo_at_once do
    key = System.get_env("ANTHROPIC_API_KEY")
    System.delete_env("ANTHROPIC_API_KEY")

    try do
      out = capture_io(fn -> assert {:error, {:no_api_key, _}} = Demo.run(@quick) end)
      assert out == ""
    after
      if key, do: System.put_env("ANTHROPIC_API_KEY", key)
    end
  end

  @doc "The refusals the demo adds read as plain sentences."
  @spec the_demo_refusals_read_as_prose() :: [String.t()]
  example the_demo_refusals_read_as_prose do
    for refusal <- [{:no_compliant_output, %{}}, {:not_fooled, %{}}] do
      message = Refusal.message(refusal)
      assert String.length(message) > 40
      message
    end
  end
end
