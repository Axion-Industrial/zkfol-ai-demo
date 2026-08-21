defmodule Zkfol.Al.Ask do
  @moduledoc """
  I am one stepping ask: the question installed on a branch of my own, the
  goal that runs against it, the arguments the answer is shaped to, and AL's
  search state between answers.
  """

  use TypedStruct

  @typedoc "One answer: the argument list ground, a cell an integer over N."
  @type answer :: [Zkfol.Statement.datum()]

  @typedoc "What one step of me yields: an answer, the end of the search, or a refusal."
  @type outcome :: {:ok, answer()} | :exhausted | {:error, Zkfol.Refusal.t()}

  typedstruct enforce: true do
    field(:rels, [Zkfol.Lang.Rel.t()])
    field(:goal, [struct()])
    field(:arguments, [Zkfol.Statement.datum() | :_])
    field(:branch, AL.Branch.t())
    field(:state, AL.t() | nil, default: nil)
  end
end
