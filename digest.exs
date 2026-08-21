alias Zkfol.{Statement, Lay, Interpretation}
mods = for {m, _, _} <- :code.all_available(), s = to_string(m), String.starts_with?(s, "Elixir.Examples.E"), do: String.to_atom(s)
rows =
  for m <- mods, Code.ensure_loaded?(m), {f, 0} <- m.__info__(:functions), not String.starts_with?(to_string(f), "__") do
    try do
      case apply(m, f, []) do
        %Statement{stage: %Statement.Solved{lay: lay, pred: pred}} ->
          [{"#{m}.#{f}", :erlang.phash2({Interpretation.rows(Lay.witness(lay)), lay.stands, pred})}]
        _ -> []
      end
    rescue _ -> []
    catch _, _ -> []
    end
  end
for {k, h} <- List.flatten(rows) |> Enum.sort(), do: IO.puts("#{k} #{h}")
