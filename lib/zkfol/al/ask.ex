defmodule Zkfol.Al.Ask do
  @moduledoc """
  I am one stepping ask: the question installed on a branch of my own,
  the goal that runs against it, the arguments the answer is shaped to,
  and AL's search state between answers.

  My state is the whole continuation of the search, so I never cross a
  process boundary: an exit reason is copied onto the receiver's heap,
  and a large derivation copied that way takes the node with it.
  Whoever opens me steps me.
  """

  use TypedStruct

  @typedoc """
  What one step of me yields: an answer, the end of the search, or a
  refusal to make one.
  """
  @type outcome :: {:ok, [integer()]} | :exhausted | {:error, Zkfol.Refusal.t()}

  typedstruct enforce: true do
    field(:name, atom())
    field(:goal, [struct()])
    field(:arguments, [integer() | :_])
    field(:branch, AL.Branch.t())
    field(:state, AL.t() | nil, default: nil)
  end
end
