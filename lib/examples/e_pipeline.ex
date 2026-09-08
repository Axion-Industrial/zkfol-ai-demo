defmodule Examples.EPipeline do
  @moduledoc "I am the pipeline's evidence: the trail replays the act, a refusal names its pass."

  use ExExample

  import ExUnit.Assertions

  alias Examples.EUser
  alias Zkfol.Doubling
  alias Zkfol.Log
  alias Zkfol.Pipeline
  alias Zkfol.Prover
  alias Zkfol.Refusal
  alias Zkfol.Statement

  @spec the_trail_replays_the_act() :: [Log.Event.t()]
  example the_trail_replays_the_act do
    pipeline = %Pipeline{passes: [{Doubling, []}, {Zkfol.Phi, []}]}
    source = %Statement{rels: [EUser.fib()], args: [100]}
    ran = Zkfol.compile(source, pipeline: pipeline, name: :doubled_fibonacci, public: [:r, :e])
    trail = Log.trail(Log.snapshot(), ran)

    assert %Prover.Report{claims: [{_claim, value}, {"in", 1}, {_position, _walked}]} =
             Log.report(Log.snapshot(), ran)

    assert value == EUser.fib(100)

    # The trail's event shapes are ELog's claim; here the act replays:
    # the verdicts off the trail, the stages re-run from the source.
    assert Enum.find_value(trail, fn
             %Log.Event{body: {:piped, verdicts}} -> verdicts
             _event -> nil
           end) == [{Doubling, :rewrites}, {Zkfol.Phi, :declines}]

    # A stage is a re-run, never a record: 0 the source, 1 doubled,
    # 2 the same again, the lowering having nothing left to do.
    assert Log.Ran.stage(ran, 0) == {:ok, entered(ran.source)}
    assert {:ok, doubled} = Log.Ran.stage(ran, 1)
    assert Statement.pred(doubled) != nil
    assert Statement.claims(doubled) == []
    assert {:ok, %Statement{stage: %Statement.Solved{}}} = Log.Ran.stage(ran, 2)

    emitted = Zkfol.emit(source, pipeline: pipeline, name: :emitted_fibonacci)
    assert Log.report(Log.snapshot(), emitted) == nil

    trail
  end

  @spec a_refusal_names_its_pass() :: Refusal.t()
  example a_refusal_names_its_pass do
    source = %Statement{rels: [EUser.fib()], args: [0]}

    {:error, Doubling, refusal, []} =
      Pipeline.run(%Pipeline{passes: [{Doubling, []}, {Zkfol.Phi, []}]}, source)

    assert {:precedes_base_case, %{n: 0, base: 1}} = refusal
    refusal
  end

  @spec entered(Statement.t()) :: Statement.t()
  defp entered(%Statement{rels: [root | _rest] = rels} = source),
    do: with({:ok, reached} <- Zkfol.Lang.reached(root, rels), do: %{source | rels: reached})
end
