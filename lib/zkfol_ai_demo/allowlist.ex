defmodule ZkfolAiDemo.Allowlist do
  @moduledoc """
  I am the signed allowlist: the destinations an agent's actions may reach, and which of them
  may receive documents.

  The file is signed with an Ed25519 key that is never in this process. Signing is a separate
  operator command (`bin/harness sign-allowlist`) that reads the private key from outside the
  repository, and the process that runs an agent holds only the public key and the signature.
  I refuse an allowlist whose signature does not verify, so a changed file is a stopped run.

  A destination is identified by the first 128 bits of the SHA-256 of its normalised address,
  as four 32-bit words: wide enough that nobody can search for an address that collides with an
  allowed one, and each word within the 32 bits the compiled program's lookup check works in.

  ### Public API

  - `load/0` and `load/1` read and verify the published allowlist, or one in another directory.
  - `id/1` is a destination's identifier.
  - `keygen/0` and `sign/0` are the operator's half.
  """

  use TypedStruct

  alias Zkfol.Refusal

  @dir Path.expand("../../harness", __DIR__)
  @file_path Path.join(@dir, "allowlist.json")
  @sig_path Path.join(@dir, "allowlist.sig")
  @pub_path Path.join(@dir, "allowlist.pub")

  typedstruct module: Entry, enforce: true do
    @typedoc "One allowed destination, its identifier, and whether it may receive documents."
    field(:address, String.t())
    field(:id, [non_neg_integer()])
    field(:documents, boolean())
  end

  typedstruct enforce: true do
    @typedoc """
    A verified allowlist, the SHA-256 of the file it was read from, and the SHA-256 of the
    public key that verified it.
    """
    field(:entries, [ZkfolAiDemo.Allowlist.Entry.t()])
    field(:hash, binary())
    field(:signer, binary())
  end

  @doc """
  I read the allowlist in `dir` (the published one by default) and refuse it unless its
  signature verifies against the public key beside it.
  """
  @spec load(Path.t()) :: {:ok, t()} | {:error, Refusal.t()}
  def load(dir \\ @dir) do
    bytes = File.read!(Path.join(dir, "allowlist.json"))

    with {:ok, public} <- public_key(dir),
         true <- verified?(bytes, public, dir) do
      entries =
        for %{"address" => address, "documents" => documents} <- JSON.decode!(bytes)["entries"] do
          %Entry{address: normalise(address), id: id(address), documents: documents}
        end

      {:ok,
       %__MODULE__{
         entries: entries,
         hash: :crypto.hash(:sha256, bytes),
         signer: :crypto.hash(:sha256, public)
       }}
    else
      _ -> {:error, {:allowlist_unsigned, %{}}}
    end
  end

  @doc "I am a destination's identifier: 128 bits of the hash of its normalised address, as words."
  @spec id(String.t()) :: [non_neg_integer()]
  def id(address) do
    <<id::binary-size(16), _rest::binary>> = :crypto.hash(:sha256, normalise(address))
    ZkfolAiDemo.Bindings.words(id)
  end

  @doc "I am an address as the allowlist reads it: trimmed and lowercased, without a display name."
  @spec normalise(String.t()) :: String.t()
  def normalise(address) do
    case Regex.run(~r/<([^<>]+)>/, address) do
      [_whole, inner] -> inner
      nil -> address
    end
    |> String.trim()
    |> String.downcase()
  end

  @doc "I make the operator's signing key, outside the repository, and publish its public half."
  @spec keygen() :: {:ok, Path.t()} | {:error, Refusal.t()}
  def keygen do
    path = key_path()

    if File.exists?(path) do
      {:error, {:signing_key_exists, %{path: path}}}
    else
      {public, private} = :crypto.generate_key(:eddsa, :ed25519)
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, Base.encode16(private, case: :lower), [:exclusive])
      File.chmod!(path, 0o600)
      File.write!(@pub_path, Base.encode16(public, case: :lower) <> "\n")
      {:ok, path}
    end
  end

  @doc "I sign the allowlist file with the operator's key and publish the signature."
  @spec sign() :: :ok | {:error, Refusal.t()}
  def sign do
    case File.read(key_path()) do
      {:ok, hex} ->
        private = Base.decode16!(String.trim(hex), case: :lower)
        signature = :crypto.sign(:eddsa, :none, File.read!(@file_path), [private, :ed25519])
        File.write!(@sig_path, Base.encode16(signature, case: :lower) <> "\n")

      {:error, _} ->
        {:error, {:signing_key_missing, %{path: key_path()}}}
    end
  end

  @spec public_key(Path.t()) :: {:ok, binary()} | :error
  defp public_key(dir) do
    with {:ok, hex} <- File.read(Path.join(dir, "allowlist.pub")),
         {:ok, public} <- Base.decode16(String.trim(hex), case: :lower),
         do: {:ok, public},
         else: (_ -> :error)
  end

  @spec verified?(binary(), binary(), Path.t()) :: boolean()
  defp verified?(bytes, public, dir) do
    with {:ok, hex} <- File.read(Path.join(dir, "allowlist.sig")),
         {:ok, signature} <- Base.decode16(String.trim(hex), case: :lower) do
      :crypto.verify(:eddsa, :none, bytes, signature, [public, :ed25519])
    else
      _ -> false
    end
  end

  @spec key_path() :: Path.t()
  defp key_path,
    do: System.get_env("ZKFOL_SIGNING_KEY") || Path.expand("~/.zkfol-demo/allowlist.key")
end
