defmodule Zkfol.Face do
  @moduledoc """
  I am the system shaped for a viewer: plain maps and strings a GUI
  renders without interpreting. What I answer is what the views show,
  so the shape knowledge lives here, beside the structs it reads,
  rather than in strings on the drawing side of the bridge.

      Face.summary(statement)
      Face.text(statement)
      Face.grid(uair)
      Face.pcs()
      Face.act(snap, ran)
      Face.emitted(ran)
  """

  use GtBridge.View

  alias GtBridge.Phlow.ColumnedList
  alias GtBridge.Phlow.Mondrian
  alias Zkfol.Ast
  alias Zkfol.Interpretation
  alias Zkfol.Lang
  alias Zkfol.Semantics
  alias Zkfol.Log
  alias Zkfol.Refusal
  alias Zkfol.Statement
  alias Zkfol.Statement.Solved
  alias Zkfol.Uair
  alias Zkfol.ZincPlus

  @doc "I am a relation shaped for its clauses view: each clause as the surface writes it."
  @spec rel(Lang.Rel.t()) :: %{atom() => term()}
  def rel(%Lang.Rel{name: name, arity: arity, clauses: clauses}) do
    %{arity: arity, clauses: for({head, body} <- clauses, do: clause_text(name, head, body))}
  end

  @doc """
  I am a relation's compiled shape summarized: its members, pointers,
  widths, and branch count. A shape that refuses says why, so a
  half-written relation still reads.
  """
  @spec shape(Lang.Rel.t()) :: %{atom() => term()}
  def shape(%Lang.Rel{} = rel) do
    case Lang.compile(rel) do
      {:ok, shape} ->
        %{
          members: shape.members,
          pointers: for({callee, at} <- shape.pointers, do: "#{callee} " <> term_text(at)),
          slack: shape.slack,
          quot: shape.quot,
          branches: length(Ast.branches(shape.pred))
        }

      {:error, refusal} ->
        %{refused: Refusal.message(refusal)}
    end
  end

  @doc "I am the statement's facts, one map: what a delta view compares."
  @spec summary(Statement.t()) :: %{atom() => term()}
  def summary(%Statement{} = statement) do
    pred = solved_pred(statement)

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
    elided = %{solved | witness: :"…elided…", lay: :"…elided…"}
    inspected(%{statement | stage: elided})
  end

  def text(%Statement{} = statement), do: inspected(statement)

  @doc """
  I am the derivation the statement carries, shaped for its view: one
  row per fact in laying order, what it consumed, and its fan-in. A
  fact rides as `[relation | tuple]`.
  """
  @spec derivation(Statement.t() | Zkfol.Derivation.t() | nil) :: %{atom() => term()}
  def derivation(%Statement{} = statement), do: derivation(Statement.derivation(statement))

  def derivation(%Zkfol.Derivation{} = d) do
    consumption = Zkfol.Derivation.consumption(d)
    fans = consumption |> Enum.flat_map(&elem(&1, 1)) |> Enum.frequencies()

    %{
      rows:
        for {fact, used} <- consumption do
          %{
            fact: fact_row(fact),
            consumes: Enum.map(used, &fact_row/1),
            fan_in: Map.get(fans, fact, 0)
          }
        end
    }
  end

  def derivation(nil), do: %{rows: []}

  @spec fact_row(Zkfol.Derivation.fact()) :: [term()]
  defp fact_row({name, tuple}), do: [name | tuple]

  @doc """
  I am the judgement as a table: one row per branch of the predicate,
  one column per witness column, each cell the branch's Figure 2 value
  there: zero is the branch answering for the column, anything else
  the size of its objection. The labels come off the relations
  themselves, in the order Lang emits their branches.
  """
  @judgement_keys ~w(labels evals terms trees sources rows regions arrows aims witness)a

  @spec judgement(Statement.t()) :: %{atom() => term()}
  def judgement(%Statement{stage: %Solved{witness: witness}} = statement) do
    branches =
      case Statement.pred(statement) do
        {:disj, branches} -> branches
        pred -> [pred]
      end

    len = Interpretation.len(witness)
    conjuncts = Enum.map(branches, &conjuncts_of/1)
    table = table_of(statement.rels)

    %{
      labels: labels(statement.rels, table, length(branches)),
      evals: for(b <- branches, do: for(x <- 1..len, do: Semantics.eval(b, witness, x))),
      terms: for(goals <- conjuncts, do: Enum.map(goals, &phi_text/1)),
      trees:
        for goals <- conjuncts do
          for x <- 1..len, do: for(g <- goals, do: tree(g, witness, x))
        end,
      sources: sources(statement.rels, table, length(branches)),
      rows: row_labels(statement.rels, table),
      regions: on_lay(statement, &Zkfol.Lay.regions/1),
      arrows: on_lay(statement, &Zkfol.Lay.arrows/1),
      aims: on_lay(statement, &Zkfol.Lay.aims/1),
      witness:
        for x <- 1..len do
          for i <- 1..length(Interpretation.rows(witness)), do: Interpretation.at(witness, i, x)
        end
    }
  end

  def judgement(%Statement{}), do: Map.new(@judgement_keys, &{&1, []})

  # A reading of the statement's lay, empty without one.
  @spec on_lay(Statement.t(), (Zkfol.Lay.t() -> [term()])) :: [term()]
  defp on_lay(%Statement{stage: %Solved{lay: %Zkfol.Lay{} = lay}}, reading), do: reading.(lay)
  defp on_lay(%Statement{}, _reading), do: []

  @doc """
  I am one lay for its grid: the row introductions off its own shape,
  the witness matrix by column, and the regions, arrows, and aims it
  already is. What the Lay views draw of a bridged `Zkfol.Lay`.
  """
  @spec lay(Zkfol.Lay.t()) :: %{atom() => term()}
  def lay(%Zkfol.Lay{} = lay) do
    witness =
      case Zkfol.Lay.witness(lay) do
        {:ok, witness} -> witness
        {:error, _reason} -> nil
      end

    %{
      rows: lay_labels(lay),
      regions: Zkfol.Lay.regions(lay),
      arrows: Zkfol.Lay.arrows(lay),
      aims: Zkfol.Lay.aims(lay),
      witness:
        if witness do
          for x <- 1..Interpretation.len(witness) do
            for i <- 1..length(Interpretation.rows(witness)),
                do: Interpretation.at(witness, i, x)
          end
        else
          []
        end
    }
  end

  # Row introductions from the shape alone: member and argument index,
  # pointers by callee and address, each led by its committed column.
  @spec lay_labels(Zkfol.Lay.t()) :: [String.t()]
  defp lay_labels(%Zkfol.Lay{shape: shape, alloc: alloc}) do
    named =
      for name <- shape.members,
          {r, i} <- Enum.with_index(Zkfol.Alloc.rows(alloc, name), 1),
          into: %{},
          do: {r, "#{name} #{i}"}

    numbered(Map.merge(named, derived_rows(shape, alloc)), alloc)
  end

  # The rows a shape names beyond its members: the tag row, the
  # pointers by callee and address, the slack cells its guards bind,
  # the quotients its reductions divide out.
  @spec derived_rows(Lang.shape(), Zkfol.Alloc.t()) :: %{pos_integer() => String.t()}
  defp derived_rows(shape, alloc) do
    tag = Map.new(region_rows(alloc, :tag), &{&1, "tag"})

    pointers =
      Map.new(Enum.zip(region_rows(alloc, :ptr), shape.pointers), fn
        {r, {callee, at}} -> {r, "ptr #{callee} " <> term_text(at)}
      end)

    tag
    |> Map.merge(pointers)
    |> Map.merge(counted(alloc, :slack))
    |> Map.merge(counted(alloc, :quot))
  end

  # A bank whose rows say only their place in a clause's sites.
  @spec counted(Zkfol.Alloc.t(), atom()) :: %{pos_integer() => String.t()}
  defp counted(alloc, sym) do
    Map.new(Enum.with_index(region_rows(alloc, sym), 1), fn {r, k} -> {r, "#{sym} #{k}"} end)
  end

  # A region's rows where the alloc has one, none where it does not.
  @spec region_rows(Zkfol.Alloc.t(), atom()) :: [pos_integer()]
  defp region_rows(%Zkfol.Alloc{regions: regions} = alloc, sym) do
    if List.keymember?(regions, sym, 0), do: Enum.to_list(Zkfol.Alloc.rows(alloc, sym)), else: []
  end

  # Every committed row by its number, the named ones saying what they are.
  @spec numbered(%{pos_integer() => String.t()}, Zkfol.Alloc.t()) :: [String.t()]
  defp numbered(named, alloc) do
    for r <- 1..Zkfol.Alloc.width(alloc) do
      case named do
        %{^r => label} -> "C#{r} · #{label}"
        _named -> "C#{r}"
      end
    end
  end

  @doc """
  I am the emitted UAIR settled for its grid: the committed columns
  un-reversed to trace order with their padding cut, every row's
  derived kind named, and the mode's reads lifted out.
  The grid draws; nothing on its side re-derives what I already know.
  """
  @spec grid(Uair.t()) :: %{atom() => term()}
  def grid(%Uair{} = uair) do
    columns = Enum.map(uair.columns, &(&1 |> Enum.take(uair.len) |> Enum.reverse()))
    reads = mode_feed(uair.mode)

    %{
      columns: uair.columns,
      len: uair.len,
      num_vars: uair.columns |> hd() |> length() |> then(&round(:math.log2(&1))),
      num_public: uair.num_public,
      shifts: Enum.map(uair.shifts, &Tuple.to_list/1),
      reads: reads,
      word_lookups: uair.word_lookups,
      kinds: kinds(columns, reads, uair.shifts, uair.word_lookups),
      origins: Enum.map(uair.rows, &origin_text/1)
    }
  end

  @doc """
  I am the pinned code's parameters, asked of the backend rather than
  quoted: a committed column of `2^num_vars` cells encodes to `rep_factor`
  times that many, and an opening reveals `column_openings` of the
  codeword's positions. A cost view reads me so it cannot go stale when
  the pin moves.
  """
  @spec pcs() :: ZincPlus.pcs_params()
  def pcs, do: ZincPlus.pcs_params()

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

  @doc "I am the AL program the act ran, on the run's own branch; nil where none is alive."
  @spec program(Log.t(), Log.Ran.t() | pos_integer()) :: AL.Object.t() | nil
  def program(snap, %Log.Ran{defined: defined}), do: program(snap, defined)

  def program(snap, defined) do
    Enum.find_value(Log.thread(snap, defined), fn
      %Log.Event{body: {:al_solved, %{branch: branch}}} -> alive(branch)
      %Log.Event{} -> nil
    end)
  end

  @spec alive(atom()) :: AL.Object.t() | nil
  defp alive(:main), do: Zkfol.Al.program(:main)

  defp alive(branch) do
    if Enum.any?(AL.Branch.list(), &(&1.id == branch)), do: Zkfol.Al.program(branch)
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
    {:ok, final} = Log.Ran.stage(ran, length(ran.pipeline.passes))

    case Uair.emit(Statement.pred(final), Statement.witness(final), final.claims) do
      {:ok, uair} -> uair
      {:error, refusal} -> {:refused, Refusal.message(refusal)}
    end
  end

  # The route's views, declared on the structure itself: the flow as
  # a graph of its passes, and the passes as rows. A node and a row
  # both reach the module itself on click, not a picture of it.
  defview derivation_view(statement = %Statement{}, builder) do
    feed = derivation(statement)

    builder
    |> ColumnedList.title("Derivation")
    |> ColumnedList.priority(6)
    |> ColumnedList.items(feed.rows)
    |> ColumnedList.column("Fact", &fact_label(&1.fact))
    |> ColumnedList.column(
      "Consumes",
      &Enum.map_join(&1.consumes, "   ", fn f -> fact_label(f) end)
    )
    |> ColumnedList.column("Fan-in", &to_string(&1.fan_in))
  end

  @spec fact_label([term()]) :: String.t()
  defp fact_label([name | tuple]), do: "#{name}(#{Enum.join(tuple, ", ")})"

  defview regions_view(alloc = %Zkfol.Alloc{}, builder) do
    builder.columned_list()
    |> ColumnedList.title("Regions")
    |> ColumnedList.priority(4)
    |> ColumnedList.items(alloc.regions)
    |> ColumnedList.column("Region", fn {name, _width} -> to_string(name) end)
    |> ColumnedList.column("Rows", fn {name, _width} ->
      rows = Zkfol.Alloc.rows(alloc, name)
      "#{rows.first}..#{rows.last}"
    end)
  end

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
        %{index: index, name: pass |> Module.split() |> List.last(), verdict: word(verdict)}
      end

    failure =
      Enum.find_value(verdicts, feed.failure, fn
        {_pass, {:errors, refusal}} -> Refusal.message(refusal)
        {_pass, _verdict} -> nil
      end)

    %{feed | passes: passes, failure: failure}
  end

  defp read_event(_body, feed), do: feed

  # A verdict's word alone: the erred pass's refusal rides the feed's
  # failure, not the chip.
  @spec word(Zkfol.Pipeline.verdict()) :: atom()
  defp word({:errors, _refusal}), do: :errors
  defp word(verdict), do: verdict

  @spec mode_feed(Uair.mode()) :: [map()]
  defp mode_feed(%Uair.Composed{reads: reads}), do: reads
  defp mode_feed(_plain), do: []

  @spec kinds([[integer()]], [map()], [tuple()], [tuple()]) :: [atom()]
  defp kinds(columns, reads, shifts, word_lookups) do
    bit = reads |> Enum.flat_map(& &1.bit_rows) |> MapSet.new()
    result = MapSet.new(reads, & &1.result_row)
    pointer = MapSet.new(reads, & &1.row)
    scheduled = MapSet.new(shifts, &elem(&1, 0))
    ranged = MapSet.new(word_lookups, &elem(&1, 0))
    index = index_row(columns)

    for i <- 0..(length(columns) - 1) do
      cond do
        i in bit -> :bit
        i in result -> :result
        i in pointer -> :pointer
        i in scheduled -> :scheduled
        i == index -> :index
        i in ranged -> :ranged
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

  @spec solved_pred(Statement.t()) :: Zkfol.Ast.pred() | nil
  defp solved_pred(%Statement{stage: %Solved{}} = statement), do: Statement.pred(statement)
  defp solved_pred(%Statement{}), do: nil

  @spec rows_of(Statement.t()) :: String.t() | nil
  defp rows_of(%Statement{stage: %Solved{witness: witness}}),
    do: "#{length(Interpretation.rows(witness))} rows"

  defp rows_of(_statement), do: nil

  # A node of the computation: its text, its value here, and the parts
  # it is computed from, down to the witness cells themselves. A
  # composed cell's child is the pointer it reads through.
  @spec tree(Ast.pred() | Ast.term_t(), Interpretation.t(), pos_integer()) ::
          %{atom() => term()}
  defp tree({:eq, t, u} = g, w, x),
    do: %{
      text: phi_text(g),
      value: Semantics.eval(g, w, x),
      children: [
        Map.put(tree(t, w, x), :role, "left"),
        Map.put(tree(u, w, x), :role, "right")
      ]
    }

  defp tree({:natural, t} = g, w, x),
    do: %{
      text: phi_text(g),
      value: Semantics.eval(g, w, x),
      children: [tree(t, w, x)]
    }

  defp tree({:conj, goals} = g, w, x),
    do: %{
      text: phi_text(g),
      value: Semantics.eval(g, w, x),
      children: Enum.map(goals, &tree(&1, w, x))
    }

  defp tree({:disj, goals} = g, w, x),
    do: %{
      text: phi_text(g),
      value: Semantics.eval(g, w, x),
      children: Enum.map(goals, &tree(&1, w, x))
    }

  # A literal operand says itself in the text; a node for it is noise.
  defp tree({:add, t, u} = q, w, x),
    do: %{
      text: term_text(q),
      value: Semantics.eval(q, w, x),
      children: for(part <- [t, u], not is_integer(part), do: tree(part, w, x))
    }

  defp tree({:mul, t, u} = q, w, x),
    do: %{
      text: term_text(q),
      value: Semantics.eval(q, w, x),
      children: for(part <- [t, u], not is_integer(part), do: tree(part, w, x))
    }

  defp tree({:cell, _i, j} = q, w, x),
    do: %{
      text: term_text(q),
      value: Semantics.eval(q, w, x),
      at: Interpretation.at(w, j, x),
      children: [Map.put(tree({:cell, j}, w, x), :role, "pointer")]
    }

  defp tree({:cell, _i} = q, w, x),
    do: %{text: term_text(q), value: Semantics.eval(q, w, x), at: x, children: []}

  defp tree({:reify, phi}, w, x), do: tree(phi, w, x)

  defp tree(leaf, w, x),
    do: %{text: term_text(leaf), value: Semantics.eval(leaf, w, x), children: []}

  # Each branch's clause as the surface wrote it: why the equations
  # are what they are, the lowering's own receipt.
  @spec sources([Lang.Rel.t()], map() | nil, non_neg_integer()) :: [String.t()]
  defp sources(_rels, nil, _n), do: []

  defp sources(rels, table, n) do
    written =
      for %Lang.Rel{name: name, clauses: clauses} <- ordered(rels, table.tags),
          {head, body} <- clauses,
          do: clause_text(name, head, body)

    if length(written) == n, do: written, else: []
  end

  @spec clause_text(atom(), [term()], [term()]) :: String.t()
  defp clause_text(name, head, []), do: call_text(name, head)

  defp clause_text(name, head, body),
    do: call_text(name, head) <> " do " <> Enum.map_join(body, "; ", &goal_text/1) <> " end"

  @spec call_text(atom(), [term()]) :: String.t()
  defp call_text(name, args), do: "#{name}(#{Enum.map_join(args, ", ", &surface_text/1)})"

  @spec goal_text(term()) :: String.t()
  defp goal_text({:call, name, args}), do: call_text(name, args)
  defp goal_text({:eq, t, u}), do: surface_text(t) <> " = " <> surface_text(u)
  defp goal_text({:cmp, op, t, u}), do: surface_text(t) <> " #{op} " <> surface_text(u)

  defp goal_text({:mod, r, e, m}),
    do: surface_text(r) <> " = mod(" <> surface_text(e) <> ", " <> surface_text(m) <> ")"

  @spec surface_text(term()) :: String.t()
  defp surface_text(q) when is_integer(q), do: Integer.to_string(q)
  defp surface_text({:var, name}), do: to_string(name)
  defp surface_text(:len), do: "len"

  defp surface_text({:add, t, q}) when is_integer(q) and q < 0,
    do: surface_text(t) <> " - " <> Integer.to_string(-q)

  defp surface_text({:add, t, u}), do: surface_text(t) <> " + " <> surface_text(u)
  defp surface_text({:mul, t, u}), do: surface_text(t) <> "*" <> surface_text(u)
  defp surface_text({:reify, goal}), do: "reify(" <> goal_text(goal) <> ")"
  defp surface_text(_pinned), do: "^"

  # Every row of the interpretation named: a member's rows by its head
  # variables, the tag row as itself, a pointer row by its target, a
  # slack row by its place in a clause's guards.
  @spec row_labels([Lang.Rel.t()], map() | nil) :: [String.t()]
  defp row_labels(_rels, nil), do: []

  defp row_labels(rels, shape) do
    scope = Map.new(rels, &{&1.name, &1})
    alloc = Zkfol.Alloc.assign(shape)

    named =
      for name <- shape.members,
          {r, i} <- Enum.with_index(Zkfol.Alloc.rows(alloc, name), 1),
          into: %{},
          do: {r, member_row(scope[name], name, i)}

    numbered(Map.merge(named, derived_rows(shape, alloc)), alloc)
  end

  @spec member_row(Lang.Rel.t(), atom(), pos_integer()) :: String.t()
  defp member_row(%Lang.Rel{clauses: clauses}, name, i) do
    vars =
      Enum.find_value(clauses, fn {head, _body} ->
        if Enum.all?(head, &match?({:var, _}, &1)), do: head
      end)

    case vars do
      nil -> "#{name} #{i}"
      head -> with({:var, nm} <- Enum.at(head, i - 1), do: "#{name} #{nm}")
    end
  end

  @spec conjuncts_of(Ast.pred()) :: [Ast.pred()]
  defp conjuncts_of({:conj, goals}), do: goals
  defp conjuncts_of(pred), do: [pred]

  # The predicate as the paper writes it, for a reader.
  @spec phi_text(Ast.pred()) :: String.t()
  defp phi_text({:eq, t, u}), do: term_text(t) <> " = " <> term_text(u)
  defp phi_text({:conj, goals}), do: Enum.map_join(goals, " and ", &phi_text/1)
  defp phi_text({:disj, goals}), do: Enum.map_join(goals, " or ", &phi_text/1)
  defp phi_text({:natural, t}), do: "natural(" <> term_text(t) <> ")"

  @spec term_text(Ast.term_t()) :: String.t()
  defp term_text(q) when is_integer(q), do: Integer.to_string(q)
  defp term_text(:x), do: "X"
  defp term_text(:len), do: "len"
  defp term_text({:len, sym}), do: "len(#{sym})"
  defp term_text({:cell, i}), do: "#{ref_text(i)}(X)"
  defp term_text({:cell, i, j}), do: "#{ref_text(i)}(#{ref_text(j)}(X))"

  defp term_text({:add, t, q}) when is_integer(q) and q < 0,
    do: term_text(t) <> " - " <> Integer.to_string(-q)

  defp term_text({:add, t, u}), do: term_text(t) <> " + " <> term_text(u)

  defp term_text({:mul, t, u}), do: factor(t) <> "*" <> factor(u)
  defp term_text({:reify, phi}), do: "[" <> phi_text(phi) <> "]"

  @spec ref_text(Ast.row_ref()) :: String.t()
  defp ref_text({sym, i}), do: "#{sym}.#{i}"
  defp ref_text(i), do: "C#{i}"

  @spec factor(Ast.term_t()) :: String.t()
  defp factor({:add, _t, _u} = t), do: "(" <> term_text(t) <> ")"
  defp factor(t), do: term_text(t)

  # One compile feeds every derivation below; nil when there is
  # nothing to walk or the closure refuses.
  @spec table_of([Lang.Rel.t()]) :: map() | nil
  defp table_of([]), do: nil

  defp table_of([root | _rest] = rels) do
    with {:ok, table} <- Lang.compile(root, rels), do: table
  end

  # Branch labels in emission order: members by their tag, a fact by
  # its head, a rule by its name.
  @spec labels([Lang.Rel.t()], map() | nil, non_neg_integer()) :: [String.t()]
  defp labels(_rels, nil, n), do: for(i <- 1..n//1, do: "branch #{i}")

  defp labels(rels, table, n) do
    named = rels |> ordered(table.tags) |> Enum.flat_map(&clause_labels/1)
    if length(named) == n, do: named, else: labels(rels, nil, n)
  end

  @spec ordered([Lang.Rel.t()], %{atom() => pos_integer()}) :: [Lang.Rel.t()]
  defp ordered(rels, tags) when map_size(tags) == 0, do: Enum.take(rels, 1)

  defp ordered(rels, tags) do
    scope = Map.new(rels, &{&1.name, &1})
    tags |> Enum.sort_by(&elem(&1, 1)) |> Enum.map(fn {name, _k} -> scope[name] end)
  end

  @spec clause_labels(Lang.Rel.t()) :: [String.t()]
  defp clause_labels(%Lang.Rel{name: name, clauses: clauses}) do
    for {head, body} <- clauses do
      case body do
        [] -> "#{name}(#{head |> Enum.map(&surface_text/1) |> Enum.join(",")})"
        _rule -> "#{name} rule"
      end
    end
  end

  @spec inspected(term()) :: String.t()
  defp inspected(term), do: inspect(term, pretty: true, limit: 100, printable_limit: 2048)
end
