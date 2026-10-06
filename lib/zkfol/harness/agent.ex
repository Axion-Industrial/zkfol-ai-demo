defmodule Zkfol.Harness.Agent do
  @moduledoc """
  I am the agent: it asks the model to write text, and nothing I produce is trusted. What I
  return is only ever raw output for the gate to judge.

  ### Public API

  - `generate/2` asks the model for text under a system prompt and a user prompt.
  """

  use TypedStruct

  alias Zkfol.Harness.Anthropic
  alias Zkfol.Harness.Context
  alias Zkfol.Refusal

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

  @spec declined(map()) :: :ok | {:error, Refusal.t()}
  defp declined(%{"stop_reason" => "refusal"}),
    do: {:error, {:model_error, %{said: "the model declined the request (stop_reason refusal)"}}}

  defp declined(_response), do: :ok
end
