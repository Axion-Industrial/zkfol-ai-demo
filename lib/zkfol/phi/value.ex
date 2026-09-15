defmodule Zkfol.Phi.Value do
  @moduledoc """
  I am the symbolic values shared by lowering and term realization.

  A view refers to existing cells, a cons constructs without allocating, and a ref
  names a stored term. Moving between call frames preserves those distinctions.

  ### Public API

  - `shaped/2`: substitute resolved element shapes in an access.
  - `scalar/1`: the arithmetic reading of a value.
  - `count/1`: its known scalar count or outer sequence length.
  - `elements/1`: its elements for a primitive operation.
  - `affine/1`: the coefficients of an expression in X, when it has that form.
  - `frame/2`, `unframe/2`: express values across a call's column frame.
  """

  alias Zkfol.Ast
  alias Zkfol.Phi.{Cons, Ref, View}
  alias Zkfol.Phi.View.{Element, Record}

  @typedoc "A scalar expression can name an element whose shape its constraint will resolve."
  @type scalar :: Ast.poly(Ast.ep_leaf() | {:reify, Ast.pred()} | Element.t())

  @typedoc """
  What a name holds: a literal, a term, a view, a known sequence, a passed relation, a
  handed count, an unobserved element, or nothing yet.
  """
  @type t ::
          scalar()
          | View.t()
          | Cons.t()
          | Ref.t()
          | [t()]
          | {:rel, atom(), [t()]}
          | {:count, integer(), Ast.term_t()}
          | {:fresh, Ast.row_ref()}
          | :fresh

  @typedoc "Where a call reaches: an affine frame of the column, or a pointer cell."
  @type frame :: Ast.address()

  @doc "I am a known scalar count or outer sequence length, nil when unknown."
  @spec count(t() | nil) :: integer() | nil
  def count({:count, q, _form}), do: q
  def count(q) when is_integer(q), do: q
  def count([]), do: 0
  def count(%Cons{tail: tail}), do: with(n when n != nil <- count(tail), do: n + 1)
  def count([_h | t]), do: with(n when n != nil <- count(t), do: n + 1)
  def count(%View{} = view), do: View.count(view)
  def count(_value), do: nil

  @doc "I expose a finite view or constructed sequence as the values a primitive consumes."
  @spec elements(t()) :: t()
  def elements(%View{} = view), do: View.cells(view)
  def elements(%Cons{head: h, tail: t}), do: [elements(h) | elements(t)]
  def elements([h | t]), do: [elements(h) | elements(t)]
  def elements({:count, _q, form}), do: form
  def elements(form), do: form

  @doc "I give back {m, a} for an expression m * X + a; other values have no affine form."
  @spec affine(t()) :: {integer(), integer()} | nil
  def affine(:x), do: {1, 0}
  def affine(q) when is_integer(q), do: {0, q}
  def affine({:count, _q, form}), do: affine(form)

  def affine({:add, a, b}) do
    with {m, k} <- affine(a), {0, q} <- affine(b), do: {m, k + q}, else: (_apart -> nil)
  end

  def affine({:mul, a, q}) when is_integer(q) do
    with {m, k} <- affine(a), do: {m * q, k * q}
  end

  def affine(_value), do: nil

  @doc "I express a callee value at its call address in the caller."
  @spec frame(t(), frame()) :: t()
  def frame({:fresh, ref}, frame), do: frame({:cell, ref}, frame)
  def frame(form, {:at, :x, 1, 0}), do: form

  def frame(element = %Element{col: col}, frame) do
    with col = {:at, _, _, _} <- Ast.reframe(col, frame),
         do: %{element | col: col},
         else: (_unreached -> throw({:refused, {:unliftable_term, %{term: element}}}))
  end

  def frame(%Ref{id: id}, frame), do: %Ref{id: frame(id, frame)}
  def frame(%Cons{head: h, tail: t}, frame), do: Cons.new(frame(h, frame), frame(t, frame))
  def frame([h | t], frame), do: [frame(h, frame) | frame(t, frame)]
  def frame({:count, _q, form}, frame), do: frame(form, frame)
  def frame(%View{} = view, frame), do: View.framed(view, frame)
  def frame({:rel, _p, _f} = passed, _frame), do: passed
  def frame(form, _frame) when is_integer(form) or form in [:fresh, []], do: form

  def frame(form, frame) do
    Ast.postwalk(form, fn
      :x ->
        Ast.naming(frame)

      {:add, a, b} ->
        Ast.add(a, b)

      cell when is_tuple(cell) and elem(cell, 0) == :cell ->
        {row, address} = Ast.read(cell)

        with {:at, base, m, a} <- Ast.reframe(address, frame),
             do: Ast.at(row, base, m, a),
             else: (_unreached -> throw({:refused, {:unliftable_term, %{term: cell}}}))

      node ->
        node
    end)
  end

  @doc "I express the values a callee can retain in its own column frame."
  @spec unframe(t(), frame()) :: t()
  def unframe(form, {:at, :x, 1, 0}), do: form

  def unframe(element = %Element{col: col}, frame) do
    with col = {:at, _, _, _} <- Ast.unframe(col, frame),
         do: %{element | col: col},
         else: (_unreached -> throw({:refused, {:unliftable_term, %{term: element}}}))
  end

  def unframe(%Ref{} = ref, _frame), do: ref
  def unframe(%View{} = view, frame), do: View.reframed(view, frame)
  def unframe({:count, _q, _cell} = count, _frame), do: count

  def unframe(form, _frame) when is_list(form) or form == :fresh or elem(form, 0) == :rel,
    do: form

  def unframe(form, frame) do
    case affine(form) do
      {0, q} ->
        q

      {m, a} ->
        with local = {:at, _, _, _} <- Ast.unframe(Ast.address(:x, m, a), frame),
             do: Ast.naming(local),
             else: (_unreached -> :fresh)

      nil ->
        :fresh
    end
  end

  @doc "I substitute known element shapes in an access, including values built from it."
  @spec shaped(t() | Ast.pred(scalar()), %{Ast.row_ref() => View.element()}) ::
          t() | Ast.pred(scalar())
  def shaped(view = %View{row: row}, shapes),
    do: %{view | element: Map.get(shapes, row, view.element)}

  def shaped(element = %Element{row: row, col: {:at, base, m, a}, part: :whole}, shapes) do
    case Map.get(shapes, row, :unknown) do
      :unknown -> element
      :scalar -> Ast.at(row, base, m, a)
      %Record{} -> shaped(%{element | part: {:fields, 0}}, shapes)
    end
  end

  def shaped(
        fields = %Element{
          row: row = {bank, first},
          col: {:at, base, m, a},
          part: {:fields, n}
        },
        shapes
      ) do
    case Map.get(shapes, row) do
      %Record{width: width} when is_integer(width) ->
        Enum.map(n..(width - 1)//1, &Ast.at({bank, first + &1}, base, m, a))

      _unresolved ->
        fields
    end
  end

  def shaped(%Cons{head: h, tail: t}, shapes), do: Cons.new(shaped(h, shapes), shaped(t, shapes))
  def shaped([h | t], shapes), do: [shaped(h, shapes) | shaped(t, shapes)]
  def shaped(ref = %Ref{id: id}, shapes), do: %{ref | id: shaped(id, shapes)}

  def shaped(value, shapes) when is_tuple(value),
    do: value |> Tuple.to_list() |> Enum.map(&shaped(&1, shapes)) |> List.to_tuple()

  def shaped(value, _shapes), do: value

  @doc "I read a scalar value, refusing structure where arithmetic requires a number."
  @spec scalar(t()) :: scalar()
  def scalar(fields = %Element{part: {:fields, _n}}),
    do: throw({:refused, {:unliftable_term, %{term: fields}}})

  def scalar(ref = %Ref{}), do: Ref.read(:value, ref)
  def scalar({:count, _q, form}), do: form
  def scalar({:fresh, ref}), do: {:cell, ref}

  def scalar(form)
      when is_list(form) or is_struct(form, View) or is_struct(form, Cons) or
             (is_tuple(form) and elem(form, 0) == :rel),
      do: throw({:refused, {:unliftable_term, %{term: form}}})

  def scalar(form), do: form
end
