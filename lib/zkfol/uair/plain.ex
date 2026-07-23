defmodule Zkfol.Uair.Plain do
  @moduledoc """
  I am the mode of a UAIR that needs nothing beyond its committed
  columns: no shadow columns, no Section 4 lowering. The common case,
  and the one that proves straight through.
  """

  # A marker carries no data, so it is a bare struct rather than a typedstruct.
  defstruct []

  @type t :: %__MODULE__{}
end
