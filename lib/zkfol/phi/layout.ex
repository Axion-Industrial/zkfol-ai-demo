defmodule Zkfol.Phi.Layout do
  @moduledoc """
  I read a relation's parameters from its source: their names, the element shape of a
  list parameter, and whether a literal fits a bank. `Zkfol.Unrolling` decides where a
  parameter stands from these facts.

  ### Public API

  - `params/1`: a relation's parameter names.
  - `element/4`: what a list parameter's elements are, from the head patterns or a handed literal.
  - `matrix?/1`: whether a bank can hold a literal.
  """

  alias Zkfol.Lang
  alias Zkfol.Lang.Rel
  alias Zkfol.Phi.{Place, Shape}

  @typep clauses :: [{[term()], [term()]}]

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

  @doc """
  I return what a list parameter's elements are: a closed bracket in a head pattern is a
  record of that width; failing that, the nesting of a handed literal says it; else it is
  not yet known.
  """
  @spec element(clauses(), non_neg_integer(), Place.t(), Place.known()) :: Shape.t()
  def element(clauses, k, form, known) do
    from_patterns =
      Enum.find_value(clauses, fn {head, _body} ->
        case Enum.at(head, k) do
          {:cons, bracket = {:cons, _, _}, _tail} ->
            case Lang.Term.closed(bracket) do
              nil -> nil
              fields -> {:list, {0, length(fields)}, :scalar}
            end

          _other ->
            nil
        end
      end)

    case {from_patterns, Place.shape(form, known)} do
      {nil, {:list, _extent, element}} -> element
      {nil, _scalar_or_unknown} -> :unknown
      {record, _handed} -> record
    end
  end

  @doc "I say whether a bank can hold a literal: integers, or rows of integers all one width; a ragged or deeper literal is a term."
  @spec matrix?(Place.t()) :: boolean()
  def matrix?(cells) when is_list(cells) do
    rows = Enum.all?(cells, &(is_list(&1) and Enum.all?(&1, fn q -> is_integer(q) end)))
    Enum.all?(cells, &is_integer/1) or (rows and length(Enum.uniq_by(cells, &length/1)) == 1)
  end

  def matrix?(_place), do: true
end
