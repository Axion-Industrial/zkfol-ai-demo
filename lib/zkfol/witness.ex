defmodule Zkfol.Witness do
  @moduledoc """
  I am witness generation as a pass: a raw statement runs and its derivation is the
  witness, every other stage passing through untouched.
  """

  @behaviour Zkfol.Pipeline

  alias Zkfol.Al
  alias Zkfol.Refusal
  alias Zkfol.Statement

  @impl Zkfol.Pipeline
  @spec run(Statement.t(), keyword()) :: {:ok, Statement.t()} | {:error, Refusal.t()}
  def run(%Statement{stage: :raw} = statement, opts) do
    with {:ok, derivation} <- Al.derived(statement, statement.args, opts),
         do: {:ok, Statement.derived(statement, derivation)}
  end

  def run(statement, _opts), do: {:ok, statement}

  @impl Zkfol.Pipeline
  @spec verb() :: Zkfol.Pipeline.verdict()
  def verb, do: :solves
end
