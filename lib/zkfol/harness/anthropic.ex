defmodule Zkfol.Harness.Anthropic do
  @moduledoc """
  I am the Messages API over HTTPS: one request in, one response out. Elixir has no
  official SDK, so I speak the documented REST shape directly.

  The key is read from `ANTHROPIC_API_KEY` on every call and goes nowhere else. The model
  is `ZKFOL_MODEL` if set, and `claude-opus-5-5` otherwise.

  ### Public API

  - `message/1` sends one Messages API request.
  - `model/0` is the model a run uses.
  - `text/1` is the text blocks of a response, joined.
  """

  alias Zkfol.Refusal

  @url ~c"https://api.anthropic.com/v1/messages"
  @version "2023-06-01"
  @default_model "claude-opus-5-5"

  @doc "I am the model a run uses: `ZKFOL_MODEL`, or the default."
  @spec model() :: String.t()
  def model, do: System.get_env("ZKFOL_MODEL", @default_model)

  @doc """
  I send `request` (the body of a Messages API call, with string keys) and return the
  decoded response. A refusal here is a transport refusal: the call itself failed.
  """
  @spec message(map()) :: {:ok, map()} | {:error, Refusal.t()}
  def message(request) do
    with {:ok, key} <- key(),
         {:ok, status, body} <- post(key, JSON.encode!(request)) do
      respond(status, body)
    end
  end

  @doc "I am the text of a response: its text blocks, in order."
  @spec text(map()) :: String.t()
  def text(%{"content" => content}),
    do: content |> Enum.filter(&(&1["type"] == "text")) |> Enum.map_join("\n", & &1["text"])

  @spec key() :: {:ok, String.t()} | {:error, Refusal.t()}
  defp key do
    case System.get_env("ANTHROPIC_API_KEY") do
      key when key in [nil, ""] -> {:error, {:no_api_key, %{}}}
      key -> {:ok, key}
    end
  end

  @spec post(String.t(), String.t()) ::
          {:ok, non_neg_integer(), binary()} | {:error, Refusal.t()}
  defp post(key, body) do
    headers = [
      {~c"x-api-key", String.to_charlist(key)},
      {~c"anthropic-version", String.to_charlist(@version)}
    ]

    case :httpc.request(
           :post,
           {@url, headers, ~c"application/json", body},
           [timeout: 300_000, connect_timeout: 15_000, ssl: ssl()],
           body_format: :binary
         ) do
      {:ok, {{_version, status, _reason}, _headers, response}} -> {:ok, status, response}
      {:error, reason} -> {:error, {:model_error, %{said: "request failed: #{inspect(reason)}"}}}
    end
  end

  # Verify the server against the system trust store, or the bundle SSL_CERT_FILE names.
  @spec ssl() :: keyword()
  defp ssl do
    trust =
      case System.get_env("SSL_CERT_FILE") do
        nil -> [cacerts: :public_key.cacerts_get()]
        path -> [cacertfile: String.to_charlist(path)]
      end

    [
      verify: :verify_peer,
      customize_hostname_check: [match_fun: :public_key.pkix_verify_hostname_match_fun(:https)]
    ] ++ trust
  end

  @spec respond(non_neg_integer(), binary()) :: {:ok, map()} | {:error, Refusal.t()}
  defp respond(200, body), do: {:ok, JSON.decode!(body)}

  defp respond(status, body) do
    said =
      case JSON.decode(body) do
        {:ok, %{"error" => %{"type" => type, "message" => message}}} -> "#{type}: #{message}"
        _other -> String.slice(body, 0, 200)
      end

    {:error, {:model_error, %{said: "HTTP #{status}: #{said}"}}}
  end
end
