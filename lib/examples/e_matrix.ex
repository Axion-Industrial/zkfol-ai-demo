defmodule Examples.EMatrix do
  @moduledoc """
  I am the object level's evidence: declared data carries its layout,
  builds from runtime rows, reads back dense with the absent-cell
  sentinel, and takes its bank behind the derivation.
  """

  use ExExample

  import ExUnit.Assertions

  alias Examples.EUser
  alias Zkfol.Alloc
  alias Zkfol.Interpretation
  alias Zkfol.Matrix

  @spec clue_corner() :: Zkfol.Lang.Rel.t()
  example clue_corner do
    puzzle = Matrix.new(:puzzle, {2, 2}, [{0, 0, 5}, {1, 1, 3}], public: true)

    assert %Zkfol.Lang.Rel{name: :puzzle, arity: 3, layout: %Matrix{public: true}} = puzzle
    assert Matrix.shape(puzzle) == {2, 2}
    assert Matrix.extensional?(puzzle)
    puzzle
  end

  @spec data_is_dense_with_zero_sentinel() :: Interpretation.t()
  example data_is_dense_with_zero_sentinel do
    itp = Matrix.data(clue_corner())

    assert Interpretation.rows(itp) == [[5, 0], [0, 3]]
    itp
  end

  @spec from_rows_round_trips() :: Interpretation.t()
  example from_rows_round_trips do
    built = Matrix.from_rows(:grid, [[1, 2], [3, 4]])

    assert built |> Matrix.data() |> Interpretation.rows() == [[1, 2], [3, 4]]
    Matrix.data(built)
  end

  @spec a_list_is_one_row() :: Zkfol.Lang.Rel.t()
  example a_list_is_one_row do
    xs = Matrix.list(:xs, [7, 8, 9])

    assert xs.arity == 2
    assert Matrix.shape(xs) == {1, 3}
    assert xs |> Matrix.data() |> Interpretation.rows() == [[7, 8, 9]]
    xs
  end

  @spec an_existential_declares_without_facts() :: Zkfol.Lang.Rel.t()
  example an_existential_declares_without_facts do
    g = Matrix.new(:g, {2, 2})

    refute Matrix.extensional?(g)
    assert g.clauses == []
    g
  end

  @spec an_object_takes_its_bank_behind_the_derivation() :: Alloc.t()
  example an_object_takes_its_bank_behind_the_derivation do
    {:ok, shape} = Zkfol.Lang.compile(EUser.fib())
    alloc = Alloc.assign(shape, [clue_corner()])

    derivation = Alloc.assign(shape)

    assert Alloc.rows(alloc, :fib) == Alloc.rows(derivation, :fib)
    assert Alloc.rows(alloc, :puzzle) == (Alloc.width(derivation) + 1)..Alloc.width(alloc)
    assert alloc.public == [:puzzle]
    alloc
  end

  @spec declared_banks_read_their_facts() :: %{atom() => Interpretation.t()}
  example declared_banks_read_their_facts do
    {:ok, banks} = Alloc.declared([clue_corner()])

    assert %{puzzle: itp} = banks
    assert Interpretation.rows(itp) == [[5, 0], [0, 3]]
    banks
  end

  @spec an_unfilled_existential_refuses() :: Zkfol.Refusal.t()
  example an_unfilled_existential_refuses do
    {:error, reason} = Alloc.declared([an_existential_declares_without_facts()])

    assert {:existential_unfilled, %{symbol: :g}} = reason
    reason
  end
end
