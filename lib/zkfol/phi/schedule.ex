defmodule Zkfol.Phi.Schedule do
  @moduledoc """
  I schedule clause goals, retrying an equation when a binding it needs changes.

  Identical goals are scheduled once, keeping their first source position.
  Ready goals run in source order. Awakened goals run after the current ready list,
  also in source order. `blocked` records each goal's dependencies; `waiting`
  indexes those same dependencies by name so unrelated goals need no revisiting.

  ### Public API

  - `new/1`, `next/1`: start a clause and take its next goal.
  - `run/3`: interpret goals, retrying those whose dependencies change.
  - `wait/3`: retain the bindings a goal needs.
  - `wake/2`: schedule the goals waiting for changed bindings.
  """

  use TypedStruct

  alias Zkfol.Lang.Term
  alias Zkfol.Phi.{Expression, Walk}

  typedstruct do
    field(:goals, tuple(), enforce: true)
    field(:ready, [{term(), non_neg_integer()}], default: [])
    field(:awakened, MapSet.t(non_neg_integer()), default: MapSet.new())
    field(:blocked, %{non_neg_integer() => [Expression.name()]}, default: %{})
    field(:waiting, %{Expression.name() => MapSet.t(non_neg_integer())}, default: %{})
  end

  @doc "I schedule each distinct goal at its first source position."
  @spec new([term()]) :: t()
  def new(goals) do
    ready = Enum.uniq_by(Enum.with_index(goals), &elem(&1, 0))
    %__MODULE__{goals: List.to_tuple(goals), ready: ready}
  end

  @doc "I run a clause with the given goal interpreter; unresolved dependencies cause a refusal."
  @spec run(t(), Walk.t(), (term(), non_neg_integer(), Walk.t() ->
                              Walk.t() | :dead | Expression.waiting())) :: Walk.t() | :dead
  def run(schedule, walk, interpret) do
    case next(schedule) do
      :done ->
        walk

      {:blocked, goals} ->
        throw({:refused, {:unbound_variable, %{goals: goals}}})

      {:ok, goal, k, schedule} ->
        case interpret.(goal, k, walk) do
          :dead ->
            :dead

          {:waiting, names} ->
            run(wait(schedule, k, names), walk, interpret)

          more = %Walk{} when map_size(schedule.blocked) == 0 ->
            run(schedule, more, interpret)

          more = %Walk{} ->
            # A goal can bind a name behind an alias without replacing the alias itself.
            dependencies =
              for name <- Term.names(goal),
                  dependency <- [name | Term.names(Expression.substitute({:var, name}, walk))],
                  uniq: true,
                  do: dependency

            changed =
              for name <- dependencies,
                  Map.get(walk.env, name, :fresh) != Map.get(more.env, name, :fresh),
                  do: name

            run(wake(schedule, changed), more, interpret)
        end
    end
  end

  @doc "I take the next goal, finish, or return the goals whose dependencies remain unmet."
  @spec next(t()) :: {:ok, term(), non_neg_integer(), t()} | :done | {:blocked, [term()]}
  def next(schedule = %__MODULE__{ready: [{goal, k} | rest]}),
    do: {:ok, goal, k, %{schedule | ready: rest}}

  def next(schedule = %__MODULE__{ready: []}) do
    cond do
      MapSet.size(schedule.awakened) > 0 ->
        ready = for k <- Enum.sort(schedule.awakened), do: {elem(schedule.goals, k), k}
        next(%{schedule | ready: ready, awakened: MapSet.new()})

      map_size(schedule.blocked) == 0 ->
        :done

      true ->
        {:blocked, for(k <- Enum.sort(Map.keys(schedule.blocked)), do: elem(schedule.goals, k))}
    end
  end

  @doc "I suspend a goal until one of the named bindings changes."
  @spec wait(t(), non_neg_integer(), [Expression.name()]) :: t()
  def wait(schedule, k, names) do
    waiting =
      Enum.reduce(names, schedule.waiting, fn name, waiting ->
        Map.update(waiting, name, MapSet.new([k]), &MapSet.put(&1, k))
      end)

    %{schedule | waiting: waiting, blocked: Map.put(schedule.blocked, k, names)}
  end

  @doc "I awaken dependent goals and remove their old subscriptions before they run again."
  @spec wake(t(), [Expression.name()]) :: t()
  def wake(schedule, names) do
    {groups, waiting} =
      Enum.map_reduce(names, schedule.waiting, &Map.pop(&2, &1, MapSet.new()))

    awakened = Enum.reduce(groups, MapSet.new(), &MapSet.union/2)
    {released, blocked} = Map.split(schedule.blocked, MapSet.to_list(awakened))
    subscriptions = for {k, dependencies} <- released, name <- dependencies, do: {name, k}

    waiting =
      Enum.reduce(subscriptions, waiting, fn {name, k}, waiting ->
        Map.update(waiting, name, MapSet.new(), &MapSet.delete(&1, k))
      end)

    %{
      schedule
      | waiting: waiting,
        blocked: blocked,
        awakened: MapSet.union(schedule.awakened, awakened)
    }
  end
end
