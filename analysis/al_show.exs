# Render an emitted AL program as readable source-ish lines.
defmodule AlShow do
  def show(goals), do: goals |> Enum.map(&line(&1, 0)) |> Enum.join("\n") |> IO.puts()

  defp line(%AL.Goal.SetClass{} = g, d), do: pad(d) <> "class #{inspect(g |> Map.from_struct() |> Map.values() |> hd())}"
  defp line(%AL.Goal.Forall{} = _g, d), do: pad(d) <> "retract old clauses"

  defp line(%AL.Goal.OApply{method_id: :defmethod, args: [_class, name, params, body]}, d) do
    head = "#{name}(#{Enum.map_join(params, ", ", &term/1)})"
    case body do
      [] -> pad(d) <> head <> "."
      goals -> pad(d) <> head <> " :-\n" <> Enum.map_join(goals, ",\n", &line(&1, d + 1)) <> "."
    end
  end

  defp line(%AL.Goal.OApply{method_id: m, args: args}, d), do: pad(d) <> "#{m}(#{Enum.map_join(args, ", ", &term/1)})"
  defp line(%AL.Goal.Send{method: m, object: o, args: args}, d), do: pad(d) <> "#{term(o)}.#{m}(#{Enum.map_join(args, ", ", &term/1)})"
  defp line(%AL.Goal.Freeze{} = g, d) do
    m = Map.from_struct(g)
    v = Map.get(m, :var, :unknown)
    goals = Map.get(m, :goals, [])
    pad(d) <> "freeze #{term(v)} ->\n" <> Enum.map_join(goals, ",\n", &line(&1, d + 1))
  end
  defp line(%AL.Goal.Compare{op: op, a: a, b: b}, d), do: pad(d) <> "#{term(a)} #{op} #{term(b)}"
  defp line(%AL.Goal.Unify{a: a, b: b}, d), do: pad(d) <> "#{term(a)} = #{term(b)}"
  defp line(other, d), do: pad(d) <> (other |> AL.Trace.pretty() |> inspect(width: 80))

  defp term(%AL.Goal.OApply{method_id: op, args: [a, b]}) when op in [:+, :-, :*, :is], do: "(#{term(a)} #{op} #{term(b)})"
  defp term(%{} = s), do: s |> AL.Trace.pretty() |> inspect()
  defp term(a) when is_atom(a) do
    s = Atom.to_string(a)
    if String.starts_with?(s, "$"), do: String.upcase(String.trim_leading(s, "$")), else: s
  end
  defp term(x), do: inspect(x)

  defp pad(d), do: String.duplicate("  ", d)
end

{:ok, question} = Zkfol.Al.question(Examples.EUser.fib())
IO.puts("== the question program (plain clauses) ==")
AlShow.show(question)
IO.puts("\n== the traced program (witness-carrying) ==")
{:ok, traced} = Zkfol.Al.translate(Examples.EUser.fib())
AlShow.show(Enum.take(traced, 4))
