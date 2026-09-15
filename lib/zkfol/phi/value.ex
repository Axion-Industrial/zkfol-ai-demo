defmodule Zkfol.Phi.Value do
  @moduledoc """
  I am the operations the unifier needs on a value: a place, a list of them, a handed
  count, a passed relation, or nothing yet.

  ### Public API

  - `shaped/2`: read an element whose bank's shape has since been learned.
  - `scalar/1`: the arithmetic reading of a value.
  - `elements/2`: its elements for a primitive operation.
  - `frame/2`, `unframe/2`: express values across a call's column frame.
  - `handed/1`: the value a callee is handed for a caller's value.
  """

  alias Zkfol.Ast
  alias Zkfol.Phi.Place

  require Place

  @typedoc "A scalar expression can name an element whose shape its constraint will resolve."
  @type scalar :: Ast.poly(Ast.ep_leaf() | {:reify, Ast.pred()} | Place.t())

  @typedoc "What a name holds: a place, or a scalar expression over places."
  @type t :: Place.t() | scalar()

  @typedoc "Where a call reaches: an affine frame of the column, or a pointer cell."
  @type frame :: Ast.address()

  @doc "I expose a finite list to a primitive, preserving its elements; each bank's width must be known."
  @spec elements(t(), Place.known()) :: t()
  def elements(laid, known) when Place.is_laid(laid) do
    case Place.size(laid, known) do
      nil -> throw({:refused, {:unliftable_term, %{term: laid}}})
      _size -> Place.elements(laid, known)
    end
  end

  def elements({:pair, h, t}, known), do: [elements(h, known) | elements(t, known)]
  def elements([h | t], known), do: [elements(h, known) | elements(t, known)]
  def elements({:count, _q, form}, _known), do: form
  def elements(form, _known), do: form

  @doc """
  I return the value a callee is handed for a caller's value: cells of the caller's
  column, data, counts and lists along the trace as they are; a held list or a pair as a
  node the callee equates with its parameter.
  """
  @spec handed(t()) :: t()
  def handed(node = {:node, _id}), do: node
  def handed(held = {:held, _, _, _}), do: Place.node_of(held)
  def handed(element = {:across, _, _, _}), do: element
  def handed(along = {:along, _, _}), do: along
  def handed(pair = {:pair, _, _}), do: Place.node_of(pair)
  def handed(form) when is_list(form) or is_integer(form) or form == :fresh, do: form
  def handed({tag, _a, _b} = form) when tag in [:count, :rel], do: form
  def handed(form), do: if(Place.affine(form) != nil, do: form, else: :fresh)

  @doc "I express a callee value at its call address in the caller."
  @spec frame(t(), frame()) :: t()
  def frame({:fresh, ref}, frame), do: frame({:cell, ref}, frame)
  def frame(form, {:at, :x, 1, 0}), do: form
  def frame({:node, id}, frame), do: {:node, frame(id, frame)}
  def frame({:pair, h, t}, frame), do: {:pair, frame(h, frame), frame(t, frame)}
  def frame([h | t], frame), do: [frame(h, frame) | frame(t, frame)]
  def frame({:count, _q, form}, frame), do: frame(form, frame)
  def frame({:rel, p, fixed}, frame), do: {:rel, p, Enum.map(fixed, &frame(&1, frame))}
  def frame(form, _frame) when is_integer(form) or form in [:fresh, []], do: form

  def frame(laid, frame) when Place.is_laid(laid),
    do: Place.headed(elem(laid, 1), reframed(Place.address(laid), frame, laid))

  def frame({:across, row, address, n}, frame),
    do: {:across, row, reframed(address, frame, {:across, row, address, n}), n}

  def frame(form, frame) do
    Ast.postwalk(form, fn
      :x ->
        Ast.naming(frame)

      {:add, a, b} ->
        Ast.add(a, b)

      cell when is_tuple(cell) and elem(cell, 0) == :cell ->
        {row, address} = Ast.read(cell)

        case Ast.reframe(address, frame) do
          nil -> throw({:refused, {:unliftable_term, %{term: cell}}})
          {:at, base, m, a} -> Ast.at(row, base, m, a)
        end

      node ->
        node
    end)
  end

  # An address the frame cannot express refuses the value.
  @spec reframed(Ast.address(), frame(), t()) :: Ast.address()
  defp reframed(address, frame, value) do
    Ast.reframe(address, frame) || throw({:refused, {:unliftable_term, %{term: value}}})
  end

  @doc """
  I express the values a callee can retain in its own column frame. A list the frame
  cannot express keeps the caller's address; the callee re-heads it at its own extent.
  """
  @spec unframe(t(), frame()) :: t()
  def unframe(form, {:at, :x, 1, 0}), do: form

  def unframe(place = {:across, row, address, n}, frame) do
    case Ast.unframe(address, frame) do
      nil -> throw({:refused, {:unliftable_term, %{term: place}}})
      address -> {:across, row, address, n}
    end
  end

  def unframe(node = {:node, _id}, _frame), do: node

  def unframe(laid, frame) when Place.is_laid(laid) do
    case Ast.unframe(Place.address(laid), frame) do
      nil -> laid
      address -> Place.headed(elem(laid, 1), address)
    end
  end

  def unframe({:count, _q, _cell} = count, _frame), do: count

  def unframe(form, _frame) when is_list(form) or form == :fresh or elem(form, 0) == :rel,
    do: form

  def unframe(form, frame) do
    case Place.affine(form) do
      {0, q} ->
        q

      {m, a} ->
        case Ast.unframe(Ast.address(:x, m, a), frame) do
          nil -> :fresh
          local -> Ast.naming(local)
        end

      nil ->
        :fresh
    end
  end

  @doc "I read an element whose bank's shape has since been learned, wherever it stands."
  @spec shaped(t() | Ast.pred(scalar()), Place.known()) :: t() | Ast.pred(scalar())
  def shaped(element = {:across, _row, _address, _n}, known), do: Place.resolved(element, known)

  def shaped({:pair, h, t}, known), do: {:pair, shaped(h, known), shaped(t, known)}
  def shaped([h | t], known), do: [shaped(h, known) | shaped(t, known)]
  def shaped({:node, id}, known), do: {:node, shaped(id, known)}
  def shaped(laid, _known) when Place.is_laid(laid), do: laid

  def shaped(value, known) when is_tuple(value),
    do: value |> Tuple.to_list() |> Enum.map(&shaped(&1, known)) |> List.to_tuple()

  def shaped(value, _known), do: value

  @doc "I read a scalar value, refusing structure where arithmetic requires a number."
  @spec scalar(t()) :: scalar()
  def scalar({:node, id}), do: Place.read(:value, id)
  def scalar({:count, _q, form}), do: form
  def scalar({:fresh, ref}), do: {:cell, ref}

  def scalar(form)
      when is_list(form) or
             (is_tuple(form) and elem(form, 0) in [:along, :pair, :rel]),
      do: throw({:refused, {:unliftable_term, %{term: form}}})

  def scalar(form), do: form
end
