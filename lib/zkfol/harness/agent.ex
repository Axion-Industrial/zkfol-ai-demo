defmodule Zkfol.Harness.Agent do
  @moduledoc """
  I am the agent: it asks the model to write text, and nothing I produce is trusted. What I
  return is only ever raw output for the gate to judge.

  ### Public API

  - `generate/2` asks the model for text under a system prompt and a user prompt.
  - `run/4` runs a tool-using agent: the model asks for tools and the gate decides their effects.
  """

  use TypedStruct

  alias Zkfol.Harness.Anthropic
  alias Zkfol.Harness.Context
  alias Zkfol.Harness.Run
  alias Zkfol.Harness.Tools
  alias Zkfol.Refusal

  @max_turns 10

  @typedoc "What a run reports as it goes, for whoever is watching."
  @type notice ::
          {:text, String.t()}
          | {:tool_call, String.t(), map()}
          | {:tool_result, String.t(), String.t(), boolean()}
          | :refused

  typedstruct module: Generation, enforce: true do
    @typedoc "Raw model output, and the context a proof about it would bind."
    field(:text, String.t())
    field(:context, Zkfol.Harness.Context.t())
    field(:ms, non_neg_integer())
  end

  @doc "I ask the model for text. The context records the model the API says answered."
  @spec generate(String.t(), String.t()) :: {:ok, Generation.t()} | {:error, Refusal.t()}
  def generate(system, user) do
    request = %{
      "model" => Anthropic.model(),
      "max_tokens" => 8000,
      "system" => system,
      "messages" => [%{"role" => "user", "content" => user}]
    }

    started = System.monotonic_time(:millisecond)

    with {:ok, response} <- Anthropic.message(request),
         :ok <- declined(response) do
      {:ok,
       %Generation{
         text: Anthropic.text(response),
         context: Context.new(response["model"], system, user),
         ms: System.monotonic_time(:millisecond) - started
       }}
    end
  end

  @doc """
  I run the agent: the model is shown the tools and answers with calls, each call runs
  through `Tools.call/3` (so a send is gated), and the results go back to the model, until it
  stops asking. `notify` is told what happens.
  """
  @spec run(String.t(), String.t(), Run.t(), (notice() -> any())) ::
          {:ok, Run.t()} | {:error, Refusal.t()}
  def run(system, user, %Run{} = run, notify),
    do: loop([%{"role" => "user", "content" => user}], system, user, run, notify, @max_turns)

  @spec loop([map()], String.t(), String.t(), Run.t(), (notice() -> any()), non_neg_integer()) ::
          {:ok, Run.t()} | {:error, Refusal.t()}
  defp loop(_messages, _system, _user, run, _notify, 0), do: {:ok, run}

  defp loop(messages, system, user, run, notify, turns) do
    request = %{
      "model" => Anthropic.model(),
      "max_tokens" => 4096,
      "system" => system,
      "tools" => Tools.specs(),
      "messages" => messages
    }

    with {:ok, response} <- Anthropic.message(request) do
      run = run |> with_context(response, system, user)
      notify.({:text, Anthropic.text(response)})

      case {response["stop_reason"],
            for(%{"type" => "tool_use"} = call <- response["content"], do: call)} do
        {"refusal", _} ->
          notify.(:refused)
          {:ok, run}

        {_, []} ->
          {:ok, run}

        {_, calls} ->
          {results, run} = Enum.map_reduce(calls, run, &call(&1, &2, notify))

          reply = [
            %{"role" => "assistant", "content" => response["content"]},
            %{"role" => "user", "content" => results}
          ]

          loop(messages ++ reply, system, user, run, notify, turns - 1)
      end
    end
  end

  @spec call(map(), Run.t(), (notice() -> any())) :: {map(), Run.t()}
  defp call(%{"id" => id, "name" => name, "input" => input}, run, notify) do
    notify.({:tool_call, name, input})
    {text, error?, run} = Tools.call(name, input, run)
    notify.({:tool_result, name, text, error?})

    {%{"type" => "tool_result", "tool_use_id" => id, "content" => text, "is_error" => error?},
     run}
  end

  # The context names the model the API says answered, so it waits for the first response.
  @spec with_context(Run.t(), map(), String.t(), String.t()) :: Run.t()
  defp with_context(%Run{context: nil} = run, response, system, user),
    do: %{run | context: Context.new(response["model"], system, user)}

  defp with_context(run, _response, _system, _user), do: run

  @spec declined(map()) :: :ok | {:error, Refusal.t()}
  defp declined(%{"stop_reason" => "refusal"}),
    do: {:error, {:model_error, %{said: "the model declined the request (stop_reason refusal)"}}}

  defp declined(_response), do: :ok
end
