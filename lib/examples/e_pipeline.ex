defmodule Examples.EPipeline do
  @moduledoc """
  I am the pipeline's evidence: generation fills the witness slot, a
  manual witness needs no pass, the doubled route rides the same rail
  with its decision journaled, and a refusal names its pass.
  """

  use ExExample

  import ExUnit.Assertions

  alias Examples.EFibonacci
  alias Zkfol.Doubling
  alias Zkfol.Log
  alias Zkfol.Pipeline
  alias Zkfol.Statement
  alias Zkfol.Uair
  alias Zkfol.Witness

  @spec generation_fills_the_slot() :: Statement.t()
  example generation_fills_the_slot do
    source = %Statement{pred: EFibonacci.fibonacci_predicate()}
    pipeline = %Pipeline{passes: [{Witness, len: 8, seeds: %{{1, 2} => 2}}]}

    {:ok, statement, trace} = Pipeline.run(pipeline, source)

    assert statement.witness == EFibonacci.fibonacci_witness(8)
    assert [{Witness, ^statement}] = trace
    statement
  end

  @spec a_manual_witness_needs_no_pass() :: Statement.t()
  example a_manual_witness_needs_no_pass do
    manual = %Statement{
      pred: EFibonacci.fibonacci_predicate(),
      witness: EFibonacci.fibonacci_witness(8)
    }

    {:ok, statement, _trace} = Pipeline.run(%Pipeline{passes: [{Witness, len: 8}]}, manual)

    assert statement == manual
    statement
  end

  @spec doubled_through_the_pipeline() :: map()
  example doubled_through_the_pipeline do
    pipeline = %Pipeline{passes: [{Doubling, n: 100}]}
    source = %Statement{pred: EFibonacci.fibonacci_predicate()}

    {:ok, statement, _trace} = Pipeline.run(pipeline, source)
    define = Log.push({:define, :doubled_fibonacci, pipeline})

    {:ok, report, _id} =
      Uair.prove(statement.pred, statement.witness,
        claims: statement.claims,
        name: :doubled_fibonacci,
        basedon: define
      )

    assert [{_claim, value}, {_position, _walked}] = report.claims
    assert value == EFibonacci.fib(100)

    # The decision journaled: the pipeline rides the define the proof is
    # based on, so the lifeline runs pipeline -> intent -> observation.
    assert [
             %Log.Event{body: {:define, :doubled_fibonacci, ^pipeline}},
             %Log.Event{body: {:prove_requested, :doubled_fibonacci}},
             %Log.Event{body: {:proved, ^report}}
           ] = Enum.take(Log.lifeline(Log.snapshot(), :doubled_fibonacci), -3)

    report
  end

  @spec a_refusal_names_its_pass() :: String.t()
  example a_refusal_names_its_pass do
    source = %Statement{pred: EFibonacci.fibonacci_predicate()}

    {:error, Doubling, reason, []} =
      Pipeline.run(%Pipeline{passes: [{Doubling, n: 0}]}, source)

    assert reason =~ "precedes"
    reason
  end
end
