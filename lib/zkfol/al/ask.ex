defmodule Zkfol.Al.Ask do
  @moduledoc """
  I am one stepping ask: the question installed on a branch of my own,
  the goal that runs against it, the arguments the answer is shaped to,
  and AL's search state between answers.

  My state is the continuation of the search, so I never cross a
  process boundary. Whoever opens me steps me.
  """

  use TypedStruct

  @typedoc """
  One answer: the argument list ground. The interpretation is over N,
  so a cell is an integer; this name is where that widens when layouts
  and lists arrive.
  """
  @type answer :: [integer()]

  @typedoc """
  What one step of me yields: an answer, the end of the search, or a
  refusal to make one.
  """
  @type outcome :: {:ok, answer()} | :exhausted | {:error, Zkfol.Refusal.t()}

  typedstruct enforce: true do
    field(:rels, [Zkfol.Lang.Rel.t()])
    field(:goal, [struct()])
    field(:arguments, [integer() | :_])
    field(:branch, AL.Branch.t())
    field(:state, AL.t() | nil, default: nil)
  end
end
