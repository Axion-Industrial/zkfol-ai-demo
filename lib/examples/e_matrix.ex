defmodule Examples.EMatrix do
  @moduledoc """
  I am the object level's evidence: declared data carries its layout,
  builds from runtime rows, reads back dense with the absent-cell
  sentinel, and plans its own region beside the trace.
  """

  use ExExample

  import ExUnit.Assertions

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

  @spec plan_regions_root_then_objects() :: Alloc.t()
  example plan_regions_root_then_objects do
    {:ok, alloc} = Alloc.plan([clue_corner()], 3)

    assert alloc.regions == [trace: 3, puzzle: 2]
    assert alloc.public == [:puzzle]
    assert Alloc.rows(alloc, :puzzle) == 4..5
    alloc
  end

  @spec an_object_may_not_wear_trace() :: Zkfol.Refusal.t()
  example an_object_may_not_wear_trace do
    {:error, reason} = Alloc.plan([Matrix.new(:trace, {1, 1})], 1)

    assert {:reserved_symbol, %{symbol: :trace}} = reason
    reason
  end

  @spec family_reads_extensional_objects() :: %{atom() => Interpretation.t()}
  example family_reads_extensional_objects do
    root = Interpretation.new([[1, 2], [2, 3], [3, 4]])
    {:ok, family} = Alloc.family([clue_corner()], root)

    assert %{trace: ^root, puzzle: %Interpretation{}} = family
    family
  end

  @spec an_unfilled_existential_refuses() :: Zkfol.Refusal.t()
  example an_unfilled_existential_refuses do
    {:error, reason} =
      Alloc.family([an_existential_declares_without_facts()], Interpretation.new([[1]]))

    assert {:existential_unfilled, %{symbol: :g}} = reason
    reason
  end

  @spec a_planned_object_statement_holds() :: Interpretation.t()
  example a_planned_object_statement_holds do
    puzzle = clue_corner()
    {:ok, alloc} = Alloc.plan([puzzle], 1)

    phi = Zkfol.Ast.eq(Zkfol.Ast.cell({:trace, 1}), Zkfol.Ast.cell({:puzzle, 1}))
    {:ok, linked} = Alloc.link(phi, alloc)

    {:ok, family} = Alloc.family([puzzle], Interpretation.new([[5, 0]]))
    {:ok, witness} = Alloc.interpret(alloc, family)

    assert Zkfol.Semantics.valid?(linked, witness)
    witness
  end
end
