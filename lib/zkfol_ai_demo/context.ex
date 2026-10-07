defmodule ZkfolAiDemo.Context do
  @moduledoc """
  I am what a proof says about where a text came from: the model, the two prompts and a
  nonce. Without these a proof says only that some text somewhere complies, so each is hashed
  into the proof's public inputs.

  ### Public API

  - `new/3` makes a context with a fresh nonce.
  - `public/1` is the values a proof binds, by name.
  """

  use TypedStruct

  alias ZkfolAiDemo.Bindings

  typedstruct enforce: true do
    field(:model, String.t())
    field(:system_prompt, String.t())
    field(:user_prompt, String.t())
    field(:nonce, binary())
  end

  @doc "I am a context for a model and its prompts, with a fresh 128-bit nonce."
  @spec new(String.t(), String.t(), String.t()) :: t()
  def new(model, system_prompt, user_prompt),
    do: %__MODULE__{
      model: model,
      system_prompt: system_prompt,
      user_prompt: user_prompt,
      nonce: :crypto.strong_rand_bytes(16)
    }

  @doc "I am the values a proof binds for this context: hashes of the model and prompts, and the nonce."
  @spec public(t()) :: [{String.t(), [non_neg_integer()]}]
  def public(%__MODULE__{} = context) do
    [
      {"model", context.model |> Bindings.hash() |> Bindings.words()},
      {"system_prompt", context.system_prompt |> Bindings.hash() |> Bindings.words()},
      {"user_prompt", context.user_prompt |> Bindings.hash() |> Bindings.words()},
      {"nonce", Bindings.words(context.nonce)}
    ]
  end
end
