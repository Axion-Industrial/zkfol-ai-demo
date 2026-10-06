defmodule Examples.EGate do
  @moduledoc """
  I am the gate's evidence: a compliant output is released with a proof a stranger can
  check, a dash is withheld by the prover itself, and an edit or a tampered proof breaks the
  binding.
  """

  use ExExample

  import ExUnit.Assertions

  alias Zkfol.Harness.Bindings
  alias Zkfol.Harness.Context
  alias Zkfol.Harness.Gate
  alias Zkfol.Harness.Gate.Release
  alias Zkfol.Harness.Gate.Withheld
  alias Zkfol.Harness.Policy
  alias Zkfol.Harness.Statement
  alias Zkfol.Harness.Text
  alias Zkfol.Verifier
  alias Zkfol.Verifier.Request

  @doc "Every example writes files and starts a process, so none is cached."
  @spec rerun?(term()) :: boolean()
  def rerun?(_example), do: true

  @doc "A compliant output is released, with its proof, public inputs, pins and manifest."
  @spec compliant_output_is_released() :: Release.t()
  example compliant_output_is_released do
    prefix = prefix("released")
    raw = "The harvest was good, and the lanterns were well-kept."

    assert {:released, %Release{} = release} =
             Gate.release(Text.statement(raw, policy(), context()), prefix)

    for suffix <- ~w(.proof .public.json .pins.json .manifest.json .txt),
        do: assert(File.exists?(prefix <> suffix), suffix)

    assert release.accepted.bindings["policy"] == Bindings.hex(Bindings.words(policy().hash))
    assert File.read!(prefix <> ".txt") == raw
    release
  end

  @doc "A dash is withheld at the prover: it ran, failed, and left no proof."
  @spec dash_is_withheld_by_the_prover() :: Withheld.t()
  example dash_is_withheld_by_the_prover do
    prefix = prefix("withheld")
    raw = "The harvest was good #{<<0x2014::utf8>>} or so they said."

    assert {:withheld, %Withheld{stage: :prove, reason: {:verifier_rejected, _}} = withheld} =
             Gate.release(Text.statement(raw, policy(), context()), prefix)

    refute File.exists?(prefix <> ".proof")
    refute File.exists?(prefix <> ".txt")
    withheld
  end

  @doc "A text too long for any layout never reaches the prover."
  @spec oversized_text_is_withheld_before_proving() :: Withheld.t()
  example oversized_text_is_withheld_before_proving do
    raw = String.duplicate("a", 70_000)

    assert {:withheld, %Withheld{stage: :canonicalise} = withheld} =
             Gate.release(Text.statement(raw, policy(), context()), prefix("oversized"))

    withheld
  end

  @doc "An edited text has a different commitment, so the old proof does not belong to it."
  @spec edited_text_breaks_the_commitment() :: {String.t(), String.t()}
  example edited_text_breaks_the_commitment do
    %Release{accepted: accepted} = compliant_output_is_released()

    {:ok, statement} =
      Text.statement(
        "The harvest was good, and the lanterns were well kept.",
        policy(),
        context()
      )

    {:ok, edited} = Statement.commit(statement)

    assert edited != accepted.commitment
    {accepted.commitment, edited}
  end

  @doc "A proof pinned to the wrong value is rejected: the policy, the model, the nonce."
  @spec wrong_pin_is_rejected() :: [String.t()]
  example wrong_pin_is_rejected do
    %Release{request: request} = compliant_output_is_released()
    pins = request.pins |> File.read!() |> JSON.decode!()
    zero = String.duplicate("0", 64)

    for name <- ["policy", "canonicaliser", "model", "nonce", "commitment"] do
      pinned = Verifier.pin(Map.put(pins, name, zero), request.pins <> ".#{name}")

      assert {:error, {:verifier_rejected, %{said: said}}} =
               Verifier.verify(%{request | pins: pinned})

      assert said =~ name
      name
    end
    |> tap(fn _ -> assert {:ok, %Zkfol.Verifier.Accepted{}} = Verifier.verify(request) end)
  end

  @doc "A hand-edited proof file is rejected, and a proof moved to other public inputs is too."
  @spec tampered_files_are_rejected() :: [Request.t()]
  example tampered_files_are_rejected do
    %Release{request: request} = compliant_output_is_released()
    proof = File.read!(request.proof)
    <<head::binary-size(1000), byte, tail::binary>> = proof
    edited = request.proof <> ".edited"
    File.write!(edited, <<head::binary, Bitwise.bxor(byte, 255), tail::binary>>)

    assert {:error, {:verifier_rejected, _}} = Verifier.verify(%{request | proof: edited})

    # The same proof beside the public inputs of a different run.
    other = prefix("other")

    {:released, %Release{request: other_request}} =
      Gate.release(Text.statement("Another output.", policy(), context()), other)

    assert {:error, {:verifier_rejected, _}} =
             Verifier.verify(%{request | public: other_request.public})

    [request, other_request]
  end

  @spec policy() :: Policy.t()
  defp policy, do: Policy.load()

  @spec context() :: Context.t()
  defp context, do: Context.new("claude-opus-5-5", "Write plainly.", "Write about a harvest.")

  @spec prefix(String.t()) :: Path.t()
  defp prefix(name) do
    dir = Path.join(System.tmp_dir!(), "zkfol-gate-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    Path.join(dir, name)
  end
end
