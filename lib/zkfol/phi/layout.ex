defmodule Zkfol.Phi.Layout do
  @moduledoc """
  I read a relation's parameters from its source: their names, the element shape of a
  list parameter, and whether a literal fits a bank. `Zkfol.Unrolling` decides where a
  parameter stands from these facts.

  ### Public API

  - `params/1`: a relation's parameter names.
  - `list?/2`: whether the clauses read a parameter as a list.
  - `element/2`: what a handed list's elements are.
  - `matrix?/1`, `data?/1`: whether a bank can hold a literal, and whether a literal is data.
  """

  alias Zkfol.Lang
  alias Zkfol.Lang.Rel
  alias Zkfol.Phi.{Place, Shape, Value}

  @doc "I name a relation's parameters: the longest clause's variables, `a<k>` for a pattern."
  @spec params(Rel.t()) :: [atom()]
  def params(%Rel{clauses: clauses}) do
    {head, _body} = Enum.max_by(clauses, fn {_head, body} -> length(body) end)

    for {pattern, k} <- Enum.with_index(head) do
      case pattern do
        {:var, name} -> name
        _other -> :"a#{k + 1}"
      end
    end
  end

  @doc "I say whether the clauses read parameter `k` as a list: some head has a bracket at it."
  @spec list?([{[term()], [term()]}], non_neg_integer()) :: boolean()
  def list?(clauses, k),
    do: Enum.any?(clauses, fn {head, _body} -> Lang.Term.sequence?(Enum.at(head, k)) end)

  @doc "I return what a handed list's elements are, from the literal or the place it stands at; nothing handed, nothing known."
  @spec element(Place.t(), Place.known()) :: Shape.t()
  def element(form, known) do
    case Place.shape(form, known) do
      {:list, _extent, element} -> element
      _scalar_or_unknown -> :unknown
    end
  end

  @doc "I say whether a bank can hold a literal: integers, or rows of integers all one width; a ragged or deeper literal is a term."
  @spec matrix?(Place.t()) :: boolean()
  def matrix?(cells) when is_list(cells) do
    rows = Enum.all?(cells, &(is_list(&1) and Enum.all?(&1, fn q -> is_integer(q) end)))
    Enum.all?(cells, &is_integer/1) or (rows and length(Enum.uniq_by(cells, &length/1)) == 1)
  end

  def matrix?(_place), do: true

  @doc "I say whether a list is data, integers or lists of integers, which take a bank. A list of cells is already placed."
  @spec data?(Value.t()) :: boolean()
  def data?([]), do: false

  def data?(cells) when is_list(cells),
    do: Enum.all?(cells, &(is_integer(&1) or &1 == [] or data?(&1)))

  def data?(_form), do: false
end
