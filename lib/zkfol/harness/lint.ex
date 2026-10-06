defmodule Zkfol.Harness.Lint do
  @moduledoc """
  I check the demo against its own policy: no file the demo branch adds or changes, and no
  commit message on it, holds a dash character.

  The canonicaliser's own examples spell dashes as escapes, so a clean run means the source
  never contains one literally.

  ### Public API

  - `run/0` scans the branch and prints each offence.
  """

  alias Zkfol.Harness.Show
  alias Zkfol.Refusal

  @dash ~r/[\x{2012}-\x{2015}\x{2E3A}\x{2E3B}\x{2E40}]/u
  @base "base"

  @doc "I scan every file changed against `base`, and every commit message since it."
  @spec run() :: :ok | {:error, Refusal.t()}
  def run do
    files =
      lines(~w(diff --name-only --diff-filter=AM #{@base})) ++
        lines(~w(ls-files -o --exclude-standard))

    offences = Enum.flat_map(files, &in_file/1) ++ in_commits()

    for {where, line} <- offences, do: Show.bad("#{where}: #{String.trim(line)}")

    case offences do
      [] ->
        Show.good("no dash characters in #{length(files)} files or in the commit messages")

      _ ->
        {:error, {:dashes_found, %{count: length(offences)}}}
    end
  end

  @spec in_file(Path.t()) :: [{String.t(), String.t()}]
  defp in_file(path) do
    with {:ok, bytes} <- File.read(path),
         true <- String.valid?(bytes) do
      for {line, n} <- Enum.with_index(String.split(bytes, "\n"), 1),
          Regex.match?(@dash, line),
          do: {"#{path}:#{n}", line}
    else
      _ -> []
    end
  end

  @spec in_commits() :: [{String.t(), String.t()}]
  defp in_commits do
    for sha <- lines(~w(log --format=%H #{@base}..HEAD)),
        message = git(~w(log -1 --format=%B #{sha})),
        line <- String.split(message, "\n"),
        Regex.match?(@dash, line),
        do: {"commit #{String.slice(sha, 0, 8)}", line}
  end

  @spec lines([String.t()]) :: [String.t()]
  defp lines(args), do: args |> git() |> String.split("\n", trim: true)

  @spec git([String.t()]) :: String.t()
  defp git(args) do
    {out, _status} = System.cmd("git", args, stderr_to_stdout: true)
    out
  end
end
