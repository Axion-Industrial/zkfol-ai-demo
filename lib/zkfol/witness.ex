defmodule Zkfol.Witness do
  @moduledoc """
  I am witness generation as a pass: the statement runs and its
  derivation is the witness, so I carry a lowered statement to
  `Zkfol.Statement.Solved` through `Zkfol.Al.solve/3` and pass every
  other stage through untouched.
  The statement's arguments drive the derivation, `:args` in my
  options overriding them; `:bind`, `:heap`, `:branch`, `:depth`,
  and `:basedon` pass through.
  """

  @behaviour Zkfol.Pipeline

  alias Zkfol.Al
  alias Zkfol.Refusal
  alias Zkfol.Statement

  @impl Zkfol.Pipeline
  @spec run(Statement.t(), keyword()) :: {:ok, Statement.t()} | {:error, Refusal.t()}
  def run(%Statement{stage: %Statement.Lowered{} = lowered} = statement, opts) do
    args = Keyword.get(opts, :args, statement.args)

    with {:ok, witness} <- Al.solve(statement, args, opts),
         do: {:ok, %{statement | stage: Statement.Lowered.solved(lowered, witness)}}
  end

  def run(statement, _opts), do: {:ok, statement}

  @impl Zkfol.Pipeline
  @spec verb() :: Zkfol.Pipeline.verdict()
  def verb, do: :solves
end
