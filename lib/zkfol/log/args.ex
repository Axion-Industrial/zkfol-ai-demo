defmodule Zkfol.Log.Args do
  @moduledoc "I am the arguments of one journaled act: statement, door, and opts."

  use TypedStruct

  alias Zkfol.Statement

  @typedoc "The door an act came through: the whole act, or the act up to emit."
  @type entry :: :compile | :emit

  typedstruct enforce: true do
    field(:statement, Statement.t())
    field(:entry, entry())
    field(:opts, keyword())
  end
end
