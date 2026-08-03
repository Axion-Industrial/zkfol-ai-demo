defmodule Zkfol.Face do
  @moduledoc """
  I am the system shaped for a viewer: plain maps and strings a GUI
  renders without interpreting. What I answer is what the views show,
  so the shape knowledge lives here, beside the structs it reads,
  rather than in strings on the drawing side of the bridge.

      Face.summary(statement)
      Face.text(statement)
      Face.grid(uair)
      Face.act(snap, ran)
      Face.emitted(ran)
  """

  use GtBridge.View

  alias GtBridge.Phlow.ColumnedList
  alias GtBridge.Phlow.Mondrian
  alias Zkfol.Interpretation
  alias Zkfol.Log
  alias Zkfol.Refusal
  alias Zkfol.Statement
  alias Zkfol.Statement.Solved
  alias Zkfol.Uair

  @doc "I am the statement's facts, one map: what a delta view compares."
  @spec summary(Statement.t()) :: %{atom() => term()}
  def summary(%Statement{} = statement) do
    pred = lowered_pred(statement)

    %{
      rels: length(statement.rels),
      branches: if(match?({:disj, _branches}, pred), do: pred |> elem(1) |> length()),
      arity: if(match?([_root | _rest], statement.rels), do: hd(statement.rels).arity),
      witness: rows_of(statement),
      claims: length(statement.claims),
      args: statement.args
    }
  end

  @doc "I am the statement as diffable text, pretty, bounded, the witness elided."
  @spec text(Statement.t()) :: String.t()
  def text(%Statement{stage: %Solved{} = solved} = statement) do
    inspected(%{statement | stage: %{solved | witness: :"…elided…"}})
  end

  def text(%Statement{} = statement), do: inspected(statement)

  @doc """
  I am the emitted UAIR settled for its grid: the committed columns
  un-reversed to trace order with their padding cut, every row's
  derived kind named, and the mode's reads and lookups lifted out.
  The grid draws; nothing on its side re-derives what I already know.
  """
  @spec grid(Uair.t()) :: %{atom() => term()}
  def grid(%Uair{} = uair) do
    columns = Enum.map(uair.columns, &(&1 |> Enum.take(uair.len) |> Enum.reverse()))
    {reads, lookups} = mode_feed(uair.mode)

    %{
      columns: columns,
      traces_order: true,
      num_vars: uair.columns |> hd() |> length() |> then(&round(:math.log2(&1))),
      num_public: uair.num_public,
      shifts: Enum.map(uair.shifts, &Tuple.to_list/1),
      reads: reads,
      lookups: lookups,
      kinds: kinds(columns, reads, lookups, uair.shifts),
      origins: Enum.map(uair.rows, &origin_text/1)
    }
  end

  # Where a committed column came from: a row of the interpretation by
  # its C number, or the index machinery the pinning added.
  @spec origin_text(pos_integer() | :x | :ones) :: String.t()
  defp origin_text(:x), do: "x"
  defp origin_text(:ones), do: "ones"
  defp origin_text(row), do: "C#{row}"

  @doc """
  I am the journaled act read off the log for its pipeline view: the
  route, one pass per piped verdict at display scale, the intent and
  what settled it, and the raw trail rendered line by line.
  """
  @spec act(Log.t(), Log.Ran.t()) :: %{atom() => term()}
  def act(snap, %Log.Ran{defined: defined}), do: act_at(snap, defined)

  @doc """
  I am the act read off the log alone, from its define's id: the same
  feed `act/2` answers, needing no receipt in hand, so a viewer can
  open any journaled run it finds.
  """
  @spec act_at(Log.t(), pos_integer()) :: %{atom() => term()}
  def act_at(snap, defined) do
    trail = Log.thread(snap, defined)
    feed = %{route: nil, passes: [], intent: nil, report: nil, failure: nil}

    Enum.reduce(trail, feed, fn %Log.Event{body: body}, feed -> read_event(body, feed) end)
    |> Map.put(
      :trail,
      Enum.map(trail, &%{id: &1.id, basedon: &1.basedon, body: inspect(&1.body)})
    )
  end

  @doc """
  I am the route as the static structure it is: each pass with its
  options, the contract it implements, and what it says it does in
  its own words. No statement, no verdicts: a plan things are run
  through, not a trace of anything run.
  """
  @spec route(Zkfol.Pipeline.t()) :: %{atom() => term()}
  def route(%Zkfol.Pipeline{passes: passes}) do
    %{
      passes:
        for {{pass, opts}, index} <- Enum.with_index(passes, 1) do
          Code.ensure_loaded(pass)

          %{
            index: index,
            name: pass |> Module.split() |> List.last(),
            module: pass,
            opts: if(opts == [], do: nil, else: inspect(opts)),
            says: first_sentence(pass),
            implements:
              for(
                {name, arity} <- Zkfol.Pipeline.behaviour_info(:callbacks),
                function_exported?(pass, name, arity),
                do: "#{name}/#{arity}"
              )
          }
        end
    }
  end

  @doc """
  I am a pass described by its record: every journaled run whose
  route carried it, each openable off its define. Any module answers;
  one that is no pass says only that, which is what lets a viewer
  attach me to every module and show me on few.
  """
  @spec pass(Log.t(), module()) :: %{atom() => term()}
  def pass(snap, module) do
    Code.ensure_loaded(module)

    implements =
      Zkfol.Pipeline in List.flatten(
        Keyword.get_values(module.module_info(:attributes), :behaviour)
      )

    %{implements: implements, acts: acts_of(snap, module)}
  end

  @doc """
  I re-emit the final stage's UAIR for the act's emit spawn: the
  struct itself so the inspector dresses it, or the refusal's prose.
  """
  @spec emitted(Log.Ran.t()) :: Uair.t() | {:refused, String.t()}
  def emitted(ran) do
    {:ok, final} = Log.stage(ran, length(ran.pipeline.passes))

    case Uair.emit(Statement.pred(final), Statement.witness(final), final.claims) do
      {:ok, uair} -> uair
      {:error, refusal} -> {:refused, Refusal.message(refusal)}
    end
  end

  # The route's views, declared on the structure itself: the flow as
  # a graph of its passes, and the passes as rows. A node and a row
  # both reach the module itself on click, not a picture of it.
  defview route_view(%Zkfol.Pipeline{passes: passes}, builder) do
    modules = Enum.map(passes, fn {pass, _opts} -> pass end)
    edges = modules |> Enum.zip(Enum.drop(modules, 1)) |> Map.new(fn {a, b} -> {a, [b]} end)

    builder.mondrian()
    |> Mondrian.title("Route")
    |> Mondrian.priority(4)
    |> Mondrian.nodes(modules)
    |> Mondrian.node_label(fn module -> module |> Module.split() |> List.last() end)
    |> Mondrian.edges(fn module -> Map.get(edges, module, []) end)
    |> Mondrian.layout(:tree)
  end

  defview passes_view(%Zkfol.Pipeline{passes: passes}, builder) do
    feed = route(%Zkfol.Pipeline{passes: passes})

    builder.columned_list()
    |> ColumnedList.title("Passes")
    |> ColumnedList.priority(5)
    |> ColumnedList.items(feed.passes)
    |> ColumnedList.column("#", &to_string(&1.index))
    |> ColumnedList.column("Pass", & &1.name)
    |> ColumnedList.column("Options", &(&1.opts || ""))
    |> ColumnedList.column("Implements", &Enum.join(&1.implements, ", "))
    |> ColumnedList.column("Says", &(&1.says || ""))
    |> ColumnedList.send(& &1.module)
  end

  @spec read_event(term(), map()) :: map()
  defp read_event({:define, name, _pipeline}, feed), do: %{feed | route: name}
  defp read_event({:prove_requested, name}, feed), do: %{feed | intent: name}
  defp read_event({:proved, report}, feed), do: %{feed | report: Map.from_struct(report)}
  defp read_event({:prove_failed, reason}, feed), do: %{feed | failure: inspect(reason)}

  defp read_event({:piped, verdicts}, feed) do
    passes =
      for {{pass, verdict}, index} <- Enum.with_index(verdicts, 1) do
        %{index: index, name: pass |> Module.split() |> List.last(), verdict: verdict}
      end

    %{feed | passes: passes}
  end

  defp read_event(_body, feed), do: feed

  @spec mode_feed(Uair.mode()) :: {[map()], [map()]}
  defp mode_feed(%Uair.Composed{reads: reads, lookups: lookups}), do: {reads, lookups}
  defp mode_feed(%Uair.Lookup{lookups: lookups}), do: {[], lookups}
  defp mode_feed(_plain), do: {[], []}

  @spec kinds([[integer()]], [map()], [map()], [tuple()]) :: [atom()]
  defp kinds(columns, reads, lookups, shifts) do
    bit = reads |> Enum.flat_map(& &1.bit_rows) |> MapSet.new()
    result = MapSet.new(reads, & &1.result_row)
    pointer = lookups |> Enum.map(& &1[:row]) |> Enum.reject(&is_nil/1) |> MapSet.new()
    scheduled = MapSet.new(shifts, &elem(&1, 0))
    index = index_row(columns)

    for i <- 0..(length(columns) - 1) do
      cond do
        i in bit -> :bit
        i in result -> :result
        i in pointer -> :pointer
        i in scheduled -> :scheduled
        i == index -> :index
        true -> :plain
      end
    end
  end

  # The emitter appends X last; in trace order it reads 1..len.
  @spec index_row([[integer()]]) :: non_neg_integer() | nil
  defp index_row(columns) do
    if List.last(columns) == Enum.to_list(1..length(List.last(columns))),
      do: length(columns) - 1
  end

  # Every journaled run whose route carries the pass: what the pass
  # answered there and how the act settled, each opening off its define.
  @spec acts_of(Log.t(), module()) :: [%{atom() => term()}]
  defp acts_of(snap, module) do
    for %Log.Event{id: defined, body: {:define, route, %Zkfol.Pipeline{passes: passes}}} <-
          snap.events,
        Enum.any?(passes, &match?({^module, _opts}, &1)) do
      thread = Log.thread(snap, defined)

      verdict =
        Enum.find_value(thread, fn
          %Log.Event{body: {:piped, verdicts}} ->
            Enum.find_value(verdicts, fn
              {^module, verdict} -> verdict_text(verdict)
              _other -> nil
            end)

          _event ->
            nil
        end)

      %{defined: defined, route: route, verdict: verdict, settled: settled_of(thread)}
    end
  end

  @spec verdict_text(term()) :: String.t()
  defp verdict_text({verdict, _extra}), do: to_string(verdict)
  defp verdict_text(verdict), do: to_string(verdict)

  @spec settled_of([Log.Event.t()]) :: String.t()
  defp settled_of(thread) do
    cond do
      Enum.any?(thread, &match?(%Log.Event{body: {:proved, _report}}, &1)) -> "proved"
      Enum.any?(thread, &match?(%Log.Event{body: {:prove_failed, _reason}}, &1)) -> "failed"
      Enum.any?(thread, &match?(%Log.Event{body: {:prove_requested, _name}}, &1)) -> "unsettled"
      Enum.any?(thread, &erred?/1) -> "erred"
      Enum.any?(thread, &match?(%Log.Event{body: {:piped, _verdicts}}, &1)) -> "emitted"
      true -> "halted"
    end
  end

  # A piped event whose verdicts carry a pass's observed error.
  @spec erred?(Log.Event.t()) :: boolean()
  defp erred?(%Log.Event{body: {:piped, verdicts}}),
    do: Enum.any?(verdicts, &match?({_pass, {:errors, _refusal}}, &1))

  defp erred?(_event), do: false

  @spec first_sentence(module()) :: String.t() | nil
  defp first_sentence(mod) do
    with {:docs_v1, _anno, _lang, _fmt, %{"en" => doc}, _meta, _docs} <- Code.fetch_docs(mod) do
      doc |> String.replace("\n", " ") |> String.split(~r/(?<=\.)\s/, parts: 2) |> hd()
    else
      _absent -> nil
    end
  end

  @spec lowered_pred(Statement.t()) :: Zkfol.Ast.pred() | nil
  defp lowered_pred(%Statement{stage: :raw}), do: nil
  defp lowered_pred(statement), do: Statement.pred(statement)

  @spec rows_of(Statement.t()) :: String.t() | nil
  defp rows_of(%Statement{stage: %Solved{witness: witness}}),
    do: "#{length(Interpretation.rows(witness))} rows"

  defp rows_of(_statement), do: nil

  @spec inspected(term()) :: String.t()
  defp inspected(term), do: inspect(term, pretty: true, limit: 100, printable_limit: 2048)
end
