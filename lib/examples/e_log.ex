defmodule Examples.ELog do
  @moduledoc "I am the journal's evidence: every read a pure function of a snapshot."

  use ExExample

  import ExUnit.Assertions

  alias Examples.EUser
  alias Zkfol.Log
  alias Zkfol.Pipeline
  alias Zkfol.Prover
  alias Zkfol.Statement

  @spec journaled_proving() :: Log.Run.t()
  example journaled_proving do
    source = %Statement{rels: [EUser.fib()], args: [8]}
    ran = Zkfol.compile(source, name: :fibonacci, public: [:r])
    snap = Log.snapshot()
    assert %Prover.Report{} = report = Log.report(snap, ran)

    assert report.claims == [{"kernel.r", EUser.fib(8)}, {"in", 1}]

    assert [
             %Log.Event{
               body: {:define, :fibonacci, %Pipeline{}, [:r], %Log.Args{statement: ^source}}
             },
             %Log.Event{body: {:al_solved, _derivation}},
             %Log.Event{body: {:piped, _verdicts}},
             %Log.Event{body: {:prove_requested, :fibonacci}},
             %Log.Event{body: {:proved, ^report}}
           ] = Enum.take(Log.thread(snap, ran), -5)

    ran
  end

  @doc "The define carries the act whole, so its receipt runs it again."
  @spec replayed_from_the_log() :: Log.Run.t()
  example replayed_from_the_log do
    ran = journaled_proving()
    assert Log.Run.at(Log.snapshot(), ran.defined) == ran
    again = Log.Run.replay(ran)

    assert again.defined > ran.defined
    assert Log.Run.stage(again, 0) == Log.Run.stage(ran, 0)
    assert %Prover.Report{} = Log.report(Log.snapshot(), again)
    again
  end

  @doc "An act refused at its settle leaves the refusal on its trail: the story carries it."
  @spec a_refused_act_journals_its_refusal() :: Zkfol.Refusal.t()
  example a_refused_act_journals_its_refusal do
    ran = Zkfol.compile(%Statement{rels: [EUser.fib()], args: [8]}, public: [:nope])
    snap = Log.snapshot()

    assert {:unbound_variable, %{variable: :nope}} = refusal = Log.refusal(snap, ran)
    assert Log.report(snap, ran) == nil
    refusal
  end

  @doc "A verdict lingering from an abandoned wait is not this wait's."
  @spec stale_verdicts_are_not_heard() :: Prover.Report.t()
  example stale_verdicts_are_not_heard do
    stale = %EventBroker.Event{
      source_module: __MODULE__,
      body: %Log.Event{id: 1, basedon: 1, body: {:proved, %{stale: true}}}
    }

    send(self(), stale)

    {:ok, report, _id} =
      Prover.prove(Statement.pred(EUser.fibonacci()), Statement.witness(EUser.fibonacci()))

    assert %Prover.Report{} = report
    report
  end

  @doc "I owe the prover a verdict by hand and then stop it, so the debt lands on the log."
  @spec a_dead_prover_settles_its_debts() :: Zkfol.Refusal.t()
  example a_dead_prover_settles_its_debts do
    intent = Log.push({:prove_requested, :doomed})
    filter = [%Prover.Settled{intent: intent}]
    EventBroker.subscribe_me(filter)

    :sys.replace_state(Prover, &Map.put(&1, 0, {intent, []}))
    GenServer.stop(Prover, :shutdown)

    assert_receive %EventBroker.Event{body: %Log.Event{body: {:prove_failed, reason}}}, 1_000
    EventBroker.unsubscribe_me(filter)

    assert {:prover_died, _} = reason
    reason
  end
end
