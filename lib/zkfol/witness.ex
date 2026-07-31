defmodule Zkfol.Witness do
  @moduledoc """
  I am witness generation as a pass: the statement runs and its
  derivation is the witness, so I carry a lowered statement to
  `Zkfol.Statement.Solved` through `Zkfol.Al.solve/3` and pass every
  other stage through untouched.
  The statement's arguments drive the derivation, `:args` in my
  options overriding them; a root relation lends the program its
  name. `:bind`, `:heap`, `:branch`, `:depth`, and `:basedon` pass
  through.
  """

  @behaviour Zkfol.Pipeline

  alias Zkfol.Al
  alias Zkfol.Refusal
  alias Zkfol.Statement

  @impl Zkfol.Pipeline
  @spec run(Statement.t(), keyword()) :: {:ok, Statement.t()} | {:error, Refusal.t()}
  def run(%Statement{stage: %Statement.Lowered{} = lowered} = statement, opts) do
    args = Keyword.get(opts, :args, statement.args)

    with {:ok, witness} <- Al.solve(statement, args, named(statement, opts)),
         do: {:ok, %{statement | stage: Statement.Lowered.solved(lowered, witness)}}
  end

  def run(statement, _opts), do: {:ok, statement}

  @doc "I am my verdict: `:solves` for a lowered statement, `:declines` for any other stage."
  @impl Zkfol.Pipeline
  @spec plan(Statement.t(), keyword()) :: Zkfol.Pipeline.verdict()
  def plan(%Statement{stage: %Statement.Lowered{}}, _opts), do: :solves
  def plan(_statement, _opts), do: :declines

  defp named(%Statement{rels: [root | _rest]}, opts),
    do: Keyword.put_new(opts, :name, root.name)

  defp named(_statement, opts), do: opts
end
