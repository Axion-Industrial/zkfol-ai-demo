defmodule ZkfolAiDemo.Derivation do
  @moduledoc """
  I run a policy relation through zkFOL's own pipeline: AL derives the witness, and the
  pipeline lowers the relation to the predicate the prover is given. A policy is its
  relation and nothing else; I add no rule of my own.

  A relation that does not hold of its arguments has no derivation, and I say so as
  `:no_answer`. `ZkfolAiDemo.Statement` still hands such a statement to the real prover:
  `forged/3` puts the cells the relation does not hold of into the row of a derivation made
  for the nearest arguments it does hold of, which is how a false statement reaches the
  circuit.

  A parameter can be opened: its cells become public claims, so a verifier is shown what the
  relation was run against. `holds?/2` asks the relation alone, without lowering it.

  ### Public API

  - `run/3` derives a relation at arguments, opening one parameter as public if asked.
  - `holds?/2` is whether a relation holds of arguments, which is cheaper than `run/3`.
  - `forged/3` puts other cells into the row of a parameter.
  - `pinned/1` is what a verifier is asked to hold the opened cells to.
  """

  use TypedStruct

  alias Zkfol.Interpretation
  alias Zkfol.Lang.Rel
  alias Zkfol.Lay
  alias Zkfol.Pipeline
  alias Zkfol.Refusal
  alias ZkfolAiDemo.Bindings

  typedstruct enforce: true do
    @typedoc """
    A relation derived at arguments: the predicate it lowers to, the witness `rows` that
    satisfy it, and the `lay` that says which row holds what. `opened` names the parameter
    made public, and `claims` are its cells.
    """
    field(:pred, Zkfol.Ast.pred())
    field(:rows, [[integer()]])
    field(:lay, Lay.t())
    field(:opened, String.t() | nil)
    field(:claims, [Interpretation.claim()])
  end

  @doc """
  I derive `relation` at `args`, and open the parameter named `opened` as public. A relation
  that does not hold of `args` is `:no_answer`.
  """
  @spec run(Rel.t(), [term()], atom() | nil) :: {:ok, t()} | :no_answer | {:error, Refusal.t()}
  def run(relation, args, opened \\ nil) do
    case Pipeline.run(Pipeline.default(), Zkfol.Statement.of(relation, args: args)) do
      {:ok, solved, _trace} -> open(solved, opened)
      {:error, _pass, {:no_answer, _detail}, _trace} -> :no_answer
      {:error, _pass, refusal, _trace} -> {:error, refusal}
    end
  end

  @doc "I am whether `relation` holds of `args`: AL's own answer, with nothing lowered."
  @spec holds?(Rel.t(), [term()]) :: boolean()
  def holds?(relation, args) do
    case Zkfol.eval(relation, args) do
      {:ok, query} -> Zkfol.Query.close(query) == :ok
      {:error, {:no_answer, _detail}} -> false
    end
  end

  @doc """
  I am the witness rows with the row of the parameter bank `bank` holding `cells` instead, laid
  the way the derivation lays a list: a leading zero, then the cells from the last to the first.
  """
  @spec forged(t(), atom(), [integer()]) :: [[integer()]]
  def forged(%__MODULE__{rows: rows, lay: lay}, bank, cells) do
    %{first: row} = Enum.find(Lay.regions(lay), &(&1.kind == :bank and &1.name == bank))
    laid = [0 | Enum.reverse(cells)]
    List.replace_at(rows, row - 1, laid ++ List.duplicate(0, length(hd(rows)) - length(laid)))
  end

  @doc """
  I am the value a verifier is asked to hold the opened cells to, as hex by the parameter's
  name, and nothing when none was opened.
  """
  @spec pinned(t()) :: %{String.t() => String.t()}
  def pinned(%__MODULE__{opened: nil}), do: %{}

  def pinned(%__MODULE__{opened: name, rows: rows, claims: claims}),
    do: %{name => Bindings.hex(for({_label, row, x} <- claims, do: cell(rows, row, x)))}

  @spec cell([[integer()]], pos_integer(), pos_integer()) :: integer()
  defp cell(rows, row, x), do: rows |> Enum.at(row - 1) |> Enum.at(x - 1)

  @spec open(Zkfol.Statement.t(), atom() | nil) :: {:ok, t()} | {:error, Refusal.t()}
  defp open(solved, opened) do
    with {:ok, %Zkfol.Statement{stage: %{lay: lay}} = statement} <-
           Zkfol.Statement.opened(solved, List.wrap(opened)) do
      {:ok,
       %__MODULE__{
         pred: Zkfol.Statement.pred(statement),
         rows: statement |> Zkfol.Statement.witness() |> Interpretation.rows(),
         lay: lay,
         opened: opened && Atom.to_string(opened),
         claims: Zkfol.Statement.claims(statement)
       }}
    end
  end
end
