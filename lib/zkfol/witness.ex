defmodule Zkfol.Witness do
  @moduledoc """
  I am witness generation as a pass: the statement runs and its
  derivation is the witness, so I carry a raw statement to
  `Zkfol.Statement.Derived` through `Zkfol.Al.derived/3` and pass
  every other stage through untouched. The derivation answers on its
  own; `Zkfol.Lang` lays it against the predicate when a proof is
  wanted.
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
  def run(%Statement{stage: :raw} = statement, opts) do
    args = Keyword.get(opts, :args, statement.args)

    with {:ok, derivation} <- Al.derived(statement, args, opts),
         do: {:ok, Statement.derived(statement, derivation)}
  end

  def run(statement, _opts), do: {:ok, statement}

  @impl Zkfol.Pipeline
  @spec verb() :: Zkfol.Pipeline.verdict()
  def verb, do: :solves
end
