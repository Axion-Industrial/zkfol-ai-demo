defmodule Zkfol.Phi.Value do
  @moduledoc """
  I am the symbolic values shared by lowering and term realization.

  A view refers to existing cells, a cons constructs without allocating, and a ref
  names a stored term. Moving between call frames preserves those distinctions.

  ### Public API

  - `scalar/1`: the arithmetic reading of a value.
  - `count/1`: its known scalar count or outer sequence length.
  - `elements/1`: its elements for a primitive operation.
  - `frame/2`, `unframe/2`: express values across a call's column frame.
  """

  alias Zkfol.Ast
  alias Zkfol.Phi.{Cons, Ref, View}

  @typedoc """
  What a name holds: a literal, a term, a view, a known sequence, a passed relation, a
  handed count, a cell nothing read yet, or nothing yet.
  """
  @type t ::
          integer()
          | Ast.term_t()
          | View.t()
          | Cons.t()
          | Ref.t()
          | [t()]
          | {:rel, atom(), [t()]}
          | {:count, integer(), Ast.term_t()}
          | {:fresh, Ast.row_ref()}
          | :fresh

  @typedoc "Where a call reaches: an affine frame of the column, or a pointer cell."
  @type frame :: {integer(), integer()} | {:ptr, Ast.row_ref()}

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

  @doc "I express a callee value at its call address in the caller."
  @spec frame(t(), frame()) :: t()
  def frame({:fresh, ref}, frame), do: frame({:cell, ref}, frame)
  def frame(form, {1, 0}), do: form
  def frame(%Ref{id: id}, frame), do: %Ref{id: frame(id, frame)}
  def frame(%Cons{head: h, tail: t}, frame), do: Cons.new(frame(h, frame), frame(t, frame))
  def frame([h | t], frame), do: [frame(h, frame) | frame(t, frame)]
  def frame({:count, _q, form}, frame), do: frame(form, frame)
  def frame(%View{} = view, frame), do: View.framed(view, frame)
  def frame({:rel, _p, _f} = passed, _frame), do: passed
  def frame(form, _frame) when is_integer(form) or form in [:fresh, []], do: form

  def frame(form, frame) do
    Ast.postwalk(form, fn
      leaf when leaf == :x or (is_tuple(leaf) and elem(leaf, 0) == :cell) ->
        View.term(View.framed(View.of(leaf), frame))

      {:add, a, b} ->
        Ast.add(a, b)

      node ->
        node
    end)
  end

  @doc "I express the values a callee can retain in its own column frame."
  @spec unframe(t(), frame()) :: t()
  def unframe(form, {1, 0}), do: form
  def unframe(%Ref{} = ref, _frame), do: ref
  def unframe(%View{} = view, frame), do: View.reframed(view, frame)
  def unframe({:count, _q, _cell} = count, _frame), do: count

  def unframe(form, _frame) when is_list(form) or form == :fresh or elem(form, 0) == :rel,
    do: form

  def unframe(form, frame) do
    with leaf = %View{row: nil} <- View.of(form),
         worn = %View{col: {_b, _m, _a}} <- View.reframed(leaf, frame) do
      View.term(worn)
    else
      _unreached -> :fresh
    end
  end

  @doc "I read a scalar value, refusing structure where arithmetic requires a number."
  @spec scalar(t()) :: Ast.term_t()
  def scalar(ref = %Ref{}), do: Ref.read(:value, ref)
  def scalar({:count, _q, form}), do: form
  def scalar({:fresh, ref}), do: {:cell, ref}

  def scalar(form)
      when is_list(form) or is_struct(form, View) or is_struct(form, Cons) or
             (is_tuple(form) and elem(form, 0) == :rel),
      do: throw({:refused, {:unliftable_term, %{term: form}}})

  def scalar(form), do: form
end
