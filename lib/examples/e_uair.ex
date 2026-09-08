defmodule Examples.EUair do
  @moduledoc """
  I am the prover boundary's evidence: a tampered witness rejected, a
  claim outside the witness refused, a negative cell refused at the
  door, a pointer off its schedule refused, values past int64 riding
  the wider backend, two acts proving at once, and the emission
  shapes frozen against translation growth.
  """

  use ExExample

  import ExUnit.Assertions

  alias Examples.EAl
  alias Examples.EAst
  alias Examples.EDoubling
  alias Examples.EFacts
  alias Examples.EUser
  alias Zkfol.Al
  alias Zkfol.Ast
  alias Zkfol.Interpretation
  alias Zkfol.Lang
  alias Zkfol.Log
  alias Zkfol.Pipeline
  alias Zkfol.Prover
  alias Zkfol.Refusal
  alias Zkfol.Semantics
  alias Zkfol.Statement
  alias Zkfol.Uair
  alias Zkfol.ZincPlus

  @spec big_values_prove(pos_integer()) :: Log.Ran.t()
  example big_values_prove(n \\ 98) do
    # The plain route on purpose: the trace's own values need int768.
    route = EUser.plain()
    ran = Zkfol.compile(%Statement{rels: [EFacts.factorial()], args: [n]}, pipeline: route)

    assert %Prover.Report{} = report = Log.report(Log.snapshot(), ran)
    assert report.backend =~ "int768"
    ran
  end

  @doc "A full trace reserves padding: the backend's exempt final row is never an actual cell."
  @spec the_exempt_row_is_padding() :: Uair.t()
  example the_exempt_row_is_padding do
    {:ok, uair} = Uair.emit(Ast.eq(Ast.cell(1), 2), Interpretation.new([List.duplicate(2, 8)]))
    assert Uair.num_vars(uair) == 4
    assert [column] = uair.columns
    assert length(column) == 16
    actual = %{uair | columns: [List.replace_at(column, 7, 3)]}
    padding = %{uair | columns: [List.replace_at(column, 15, 3)]}
    assert {:error, {:verifier_rejected, _}} = Prover.prove_uair(actual)
    assert {:ok, %Prover.Report{}, _id} = Prover.prove_uair(padding)
    uair
  end

  @spec tampered_is_rejected() :: Refusal.t()
  example tampered_is_rejected do
    {:ok, uair} =
      Uair.emit(Statement.pred(EUser.fibonacci()), Statement.witness(EUser.fibonacci()))

    tampered = %{uair | columns: List.update_at(uair.columns, 1, &List.replace_at(&1, 4, 999))}

    {:error, reason} = Prover.prove_uair(tampered)
    assert {:verifier_rejected, _} = reason
    reason
  end

  @spec out_of_range_claim_is_refused() :: Refusal.t()
  example out_of_range_claim_is_refused do
    {:error, reason} =
      Prover.prove(Statement.pred(EUser.fibonacci()), Statement.witness(EUser.fibonacci()),
        claims: [{"n", 9, 1}]
      )

    assert {:claim_outside_witness, _} = reason
    reason
  end

  @spec negative_cell_is_refused() :: Refusal.t()
  example negative_cell_is_refused do
    {:ok, uair} =
      Uair.emit(Statement.pred(EUser.fibonacci()), Statement.witness(EUser.fibonacci()))

    negated = %{uair | columns: List.update_at(uair.columns, 0, &List.replace_at(&1, 0, -1))}

    {:error, reason} = ZincPlus.request(negated)
    assert {:witness_value_negative, %{value: -1}} = reason
    reason
  end

  @spec out_of_schedule_pointer_is_refused() :: Refusal.t()
  example out_of_schedule_pointer_is_refused do
    {:error, reason} =
      Prover.prove(Statement.pred(EUser.power()), EAst.out_of_range_pointer_is_rejected())

    assert {:witness_unsatisfies_schedule, %{column: 4}} = reason
    reason
  end

  @spec concurrent_proves_hold() :: [{:ok, Prover.Report.t(), pos_integer()}]
  example concurrent_proves_hold do
    factorial = EFacts.factorial()
    {:ok, factorial_pred} = Lang.lower(factorial, [factorial])
    {:ok, factorial_witness} = Al.solve(factorial, [6])

    reports =
      [
        fn ->
          Prover.prove(Statement.pred(EUser.fibonacci()), Statement.witness(EUser.fibonacci()))
        end,
        fn -> Prover.prove(factorial_pred, factorial_witness) end
      ]
      |> Enum.map(&Task.async/1)
      |> Task.await_many(:infinity)

    assert Enum.all?(reports, &match?({:ok, %Prover.Report{}, _id}, &1))
    reports
  end

  @spec frozen_shapes() :: [Uair.t()]
  example frozen_shapes do
    # The regression gates: translation growth is a failure, not a
    # drift. v0.1.0 froze 279/111 opcodes at 7/5 columns; the X-forge
    # fix costs its four index pins (60 opcodes) and the ones column.
    # Each guard costs its slack column and 16 opcodes a clause: the
    # kernel guards two of its three, the generic one.
    doubled = EDoubling.rewritten_fibonacci(100)
    {:ok, kernel} = Uair.emit(Statement.pred(doubled), Statement.witness(doubled), doubled.claims)

    {:ok, generic} =
      Uair.emit(Statement.pred(EUser.fibonacci()), Statement.witness(EUser.fibonacci(12)))

    assert Uair.num_cols(kernel) == 9
    assert Uair.num_cols(generic) == 7
    assert length(kernel.program) == 371
    assert length(generic.program) == 187

    [kernel, generic]
  end

  @doc """
  I am the pointer held to the region its reads reach. The bits spell `len - a` and
  hold the address under the cube, which leaves `a = 0` spellable and aimed at the
  padding no column of the derivation occupies; the region product is the whole lower
  bound. Aimed at 0 with its bits respelled to match, every cell of the trace stays a
  natural and the verifier rejects it; drop the product and the same trace proves.
  """
  @spec aimed_out_of_region_is_rejected() :: Refusal.t()
  example aimed_out_of_region_is_rejected do
    {:ok, statement, _trace} =
      Pipeline.run(Pipeline.default(), %Statement{rels: [EAl.hop_rel()], args: [5]})

    {:ok, uair} = Uair.emit(Statement.pred(statement), Statement.witness(statement))
    assert %Uair.Composed{reads: [%{row: address, bit_rows: [low, high | _rest]} | _]} = uair.mode
    assert uair.len == 2

    at = fn columns, column, value ->
      List.update_at(columns, column, &List.replace_at(&1, 0, value))
    end

    aimed = uair.columns |> at.(address, 0) |> at.(low, 0) |> at.(high, 1)
    assert Enum.all?(List.flatten(aimed), &(&1 >= 0))

    {:error, reason} = Prover.prove_uair(%{uair | columns: aimed}, name: :aimed_out_of_region)
    assert {:verifier_rejected, _said} = reason
    reason
  end

  @doc """
  I am the reach of the program's last-row exemption, measured. The program runs to
  the cube's last row and stops there, and that row is `x = 1` exactly when the trace
  fills its cube. A move of a cell at `x = 1` is held when some column past 1 breaks
  under it and free when none does, and the backend keeps that split exactly: it
  refuses a held move and proves every free one. What the free list holds is how far
  the exemption reaches on that trace, which is nothing at all on some of them.
  """
  @spec last_row_exemption() ::
          [{atom(), [{pos_integer(), integer()}], [{pos_integer(), integer()}]}]
  example last_row_exemption do
    for {name, statement} <- traces(),
        {:ok, uair} <- [Uair.emit(Statement.pred(statement), Statement.witness(statement))],
        2 ** Uair.num_vars(uair) == uair.len do
      witness = Statement.witness(statement)

      moves =
        for row <- 1..Interpretation.arity(witness),
            held = Interpretation.at(witness, row, 1),
            to <- [held + 1, held - 1],
            to >= 0,
            {true, beyond} <- [broken(Statement.pred(statement), witness, row, to)],
            do: {row, to, beyond}

      held = for {row, to, beyond} <- moves, beyond != [], do: {row, to}
      free = for {row, to, beyond} <- moves, beyond == [], do: {row, to}

      assert held != []
      assert {:error, _reason} = forged(uair, hd(held))
      assert Enum.all?(free, &match?({:ok, %Prover.Report{}, _id}, forged(uair, &1)))
      {name, held, free}
    end
  end

  ############################################################
  #                   Private Implementation                 #
  ############################################################

  # The traces the exemption reaches: some filling their cube, one padding.
  @spec traces() :: [{atom(), Statement.t()}]
  defp traces do
    [
      fib: EUser.fibonacci(),
      regs: EUser.registers(),
      mod: EUser.registers_mod(8),
      power: EUser.power()
    ]
  end

  # A move at x = 1: whether the predicate breaks under it at all, and where past x = 1.
  @spec broken(Ast.pred(), Interpretation.t(), pos_integer(), integer()) ::
          {boolean(), [pos_integer()]}
  defp broken(pred, witness, row, to) do
    moved =
      witness
      |> Interpretation.rows()
      |> List.update_at(row - 1, &List.replace_at(&1, 0, to))
      |> Interpretation.new()

    columns = for x <- 1..Interpretation.len(witness), not Semantics.holds?(pred, moved, x), do: x
    {columns != [], columns -- [1]}
  end

  # The same move written into the trace, on the cube's last row, which is x = 1.
  @spec forged(Uair.t(), {pos_integer(), integer()}) ::
          {:ok, Prover.Report.t(), pos_integer()} | {:error, Refusal.t()}
  defp forged(uair, {row, to}) do
    column = Enum.find_index(uair.rows, &(&1 == row))
    last = 2 ** Uair.num_vars(uair) - 1
    columns = List.update_at(uair.columns, column, &List.replace_at(&1, last, to))
    Prover.prove_uair(%{uair | columns: columns}, name: :last_row)
  end
end
