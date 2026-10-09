defmodule ZkfolAiDemo.Bench do
  @moduledoc """
  I measure each predicate and write the numbers to `RESULTS.md`. Nothing is extrapolated:
  every figure is one the prover and the standalone verifier produced on this machine, in
  this run, and each cell is the median of several runs.

  Cells run strictly one at a time. The load average is read as each cell starts and CPU
  steal is read across the whole run, so the stamp says how contended the machine was.

  ### Public API

  - `run/1` measures every cell and writes the results file.
  """

  use TypedStruct

  alias ZkfolAiDemo.Allowlist
  alias ZkfolAiDemo.Context
  alias ZkfolAiDemo.Grounding
  alias ZkfolAiDemo.Show
  alias ZkfolAiDemo.Statement
  alias ZkfolAiDemo.Text
  alias ZkfolAiDemo.Trace
  alias ZkfolAiDemo.Trace.Event
  alias Zkfol.Verifier
  alias Zkfol.Verifier.Request

  @results Path.expand("../../RESULTS.md", __DIR__)
  @root Path.expand("../..", __DIR__)
  @zkfol Path.join(@root, "deps/zkfol")
  @crate Path.join(@zkfol, "native/zkfol_zinc_plus")

  typedstruct module: Sample, enforce: true do
    @typedoc "One measured run of one cell. A refused statement has no proof, so no size or verify time."
    field(:prove_ms, float())
    field(:verify_ms, float() | nil)
    field(:proof_bytes, non_neg_integer() | nil)
    field(:rss_delta_mb, integer())
    field(:load1, float())
  end

  typedstruct module: Cell, enforce: true do
    @typedoc "A predicate at one input size, and what its runs measured."
    field(:predicate, String.t())
    field(:label, String.t())
    field(:shape, String.t())
    field(:outcome, :proved | :refused)
    field(:samples, [ZkfolAiDemo.Bench.Sample.t()])
  end

  @doc "I measure every cell `runs` times each, write `RESULTS.md`, and return the cells."
  @spec run(pos_integer()) :: [Cell.t()]
  def run(runs \\ 5) do
    stamp = stamp()
    steal_before = steal()
    Show.title("Benchmarks: #{runs} runs per cell, one cell at a time")

    cells =
      for {predicate, label, build, outcome} <- plan() do
        Show.step("#{predicate}: #{label}")
        {statement, shape} = build.()
        samples = for _run <- 1..runs, do: sample(statement)

        cell = %Cell{
          predicate: predicate,
          label: label,
          shape: shape,
          outcome: outcome,
          samples: samples
        }

        Show.note(summary(cell))
        cell
      end

    File.write!(@results, report(cells, stamp, steal_fraction(steal_before, steal()), runs))
    Show.note("wrote #{@results}")
    cells
  end

  ############################################################
  #                         The plan                         #
  ############################################################

  # Text at 100, 500 and 999 characters, the most the compiler derives; the grounded figures at
  # 10, 25 and 50 against as many sources; the trace at 10, 50 and 200 events, and the same
  # traces with one forbidden mail at the end.
  @spec plan() :: [{String.t(), String.t(), (-> {Statement.t(), String.t()}), :proved | :refused}]
  defp plan do
    text =
      for chars <- [100, 500, Text.capacity()],
          do: {"text (no em dash)", "#{chars} characters", fn -> text(chars) end, :proved}

    grounding =
      for figures <- [10, 25, 50],
          do: {"grounding", "#{figures} figures", fn -> grounding(figures) end, :proved}

    trace =
      for n <- [10, 50, 200],
          do: {"trace", "#{n} events", fn -> trace(n, :compliant) end, :proved}

    injected =
      for n <- [10, 50, 200],
          do:
            {"trace with exfiltration", "#{n} events", fn -> trace(n, :exfiltration) end,
             :refused}

    text ++ grounding ++ trace ++ injected
  end

  @spec text(pos_integer()) :: {Statement.t(), String.t()}
  defp text(chars) do
    {:ok, statement} = Text.statement(String.slice(prose(chars), 0, chars), context())
    {statement, "#{statement.manifest.cells} cells"}
  end

  # Every figure of the output is among the sources, which hold as many figures as it does.
  @spec grounding(pos_integer()) :: {Statement.t(), String.t()}
  defp grounding(count) do
    figures = for i <- 1..count, do: "#{1000 + i * 37}"
    {:ok, statement} = Grounding.statement(Enum.join(figures, " "), figures, context())

    {statement,
     "#{statement.manifest.figures} figures, #{statement.manifest.source_figures} source figures"}
  end

  @spec trace(pos_integer(), :compliant | :exfiltration) :: {Statement.t(), String.t()}
  defp trace(n, kind) do
    {:ok, allowlist} = Allowlist.load()
    base = for i <- 1..n, do: event(i)

    events =
      if kind == :exfiltration,
        do: List.replace_at(base, n - 1, %Event{kind: :mail, dest: "exfil@evil.example", doc: 1}),
        else: base

    {:ok, statement} = Trace.statement(events, allowlist, context())
    {statement, "#{n} events in #{statement.derivation.rows |> hd() |> length()} columns"}
  end

  # A compliant mix: reads, approvals, an approved write, and mail to an allowed destination.
  @spec event(pos_integer()) :: Event.t()
  defp event(i) do
    case rem(i, 5) do
      1 -> %Event{kind: :retrieve, doc: rem(i, 6) + 1}
      2 -> %Event{kind: :approve, approved: true}
      3 -> %Event{kind: :write, dest: "status@corp.example"}
      4 -> %Event{kind: :mail, dest: "reports@corp.example", doc: rem(i, 6) + 1}
      0 -> %Event{kind: :mail, dest: "status@corp.example"}
    end
  end

  @words ~w(harvest lantern meadow copper river station window garden pencil orchard
            ladder market bridge candle valley ribbon harbour quarry thistle compass
            blanket furnace timber pebble anchor meadowlark saddle cobbler fennel)

  @spec prose(pos_integer()) :: String.t()
  defp prose(words),
    do: Enum.map_join(1..words, " ", &Enum.at(@words, rem(&1 * 7, length(@words))))

  @spec context() :: Context.t()
  defp context, do: Context.new("claude-opus-5-5", "Benchmark.", "Benchmark.")

  ############################################################
  #                       One measurement                    #
  ############################################################

  @spec sample(Statement.t()) :: Sample.t()
  defp sample(statement) do
    prefix = Path.join(System.tmp_dir!(), "zkfol-bench-#{System.unique_integer([:positive])}")
    load = load1()
    baseline = reset_peak_rss()
    started = System.monotonic_time(:microsecond)
    proved = Statement.prove(statement, prefix)
    wall = (System.monotonic_time(:microsecond) - started) / 1000
    delta = max(peak_rss() - baseline, 0)

    case proved do
      {:ok, report} ->
        {:ok, accepted} =
          Verifier.verify(%Request{proof: prefix <> ".proof", public: prefix <> ".public.json"})

        sample = %Sample{
          prove_ms: report.prove_ms,
          verify_ms: accepted.verify_ms,
          proof_bytes: File.stat!(prefix <> ".proof").size,
          rss_delta_mb: delta,
          load1: load
        }

        File.rm(prefix <> ".proof")
        File.rm(prefix <> ".public.json")
        sample

      {:error, _refusal} ->
        %Sample{
          prove_ms: wall,
          verify_ms: nil,
          proof_bytes: nil,
          rss_delta_mb: delta,
          load1: load
        }
    end
  end

  @spec reset_peak_rss() :: non_neg_integer()
  defp reset_peak_rss do
    :erlang.garbage_collect()
    if linux?(), do: File.write!("/proc/self/clear_refs", "5")
    rss()
  end

  @spec rss() :: non_neg_integer()
  defp rss, do: if(linux?(), do: proc_status("VmRSS:"), else: ps_rss())

  @spec peak_rss() :: non_neg_integer()
  defp peak_rss, do: if(linux?(), do: proc_status("VmHWM:"), else: ps_rss())

  @spec linux?() :: boolean()
  defp linux?, do: :os.type() == {:unix, :linux}

  @spec ps_rss() :: non_neg_integer()
  defp ps_rss do
    {out, 0} = System.cmd("ps", ["-o", "rss=", "-p", System.pid()])
    out |> String.trim() |> String.to_integer() |> div(1024)
  end

  @spec proc_status(String.t()) :: non_neg_integer()
  defp proc_status(key) do
    [kb] =
      Regex.run(~r/^#{key}\s+(\d+) kB/m, File.read!("/proc/self/status"), capture: :all_but_first)

    div(String.to_integer(kb), 1024)
  end

  @spec load1() :: float()
  defp load1 do
    case File.read("/proc/loadavg") do
      {:ok, text} -> text |> String.split() |> hd() |> String.to_float()
      {:error, _} -> 0.0
    end
  end

  # CPU time stolen by the hypervisor, as ticks of the whole, from /proc/stat.
  @spec steal() :: {non_neg_integer(), non_neg_integer()}
  defp steal do
    case File.read("/proc/stat") do
      {:ok, text} ->
        [_cpu | fields] = text |> String.split("\n") |> hd() |> String.split()
        ticks = Enum.map(fields, &String.to_integer/1)
        {Enum.at(ticks, 7, 0), Enum.sum(Enum.take(ticks, 8))}

      {:error, _} ->
        {0, 1}
    end
  end

  @spec steal_fraction(
          {non_neg_integer(), non_neg_integer()},
          {non_neg_integer(), non_neg_integer()}
        ) :: float()
  defp steal_fraction({steal_a, total_a}, {steal_b, total_b}),
    do: (steal_b - steal_a) / max(total_b - total_a, 1)

  ############################################################
  #                         The report                       #
  ############################################################

  @spec summary(Cell.t()) :: String.t()
  defp summary(%Cell{outcome: :proved, samples: samples}),
    do:
      "prove #{fmt(median(for s <- samples, do: s.prove_ms))} ms, verify #{fmt(median(for s <- samples, do: s.verify_ms))} ms, proof #{kb(median(for s <- samples, do: s.proof_bytes))} KB"

  defp summary(%Cell{outcome: :refused, samples: samples}),
    do: "refused after #{fmt(median(for s <- samples, do: s.prove_ms))} ms, no proof"

  @spec report([Cell.t()], map(), float(), pos_integer()) :: String.t()
  defp report(cells, stamp, steal, runs) do
    """
    # Results

    Every figure below was measured in one run of `bin/harness bench`. Nothing is extrapolated.
    Each cell is the median of #{runs} runs, with the range beside it. The box is a cloud VM
    ("sandbox") and not the stage machine: re-run `bin/harness bench` on the machine that
    will be used, and the file is rewritten with its own stamp.

    ## Stamp

    | | |
    |---|---|
    | Demo commit | `#{stamp.demo}` |
    | zkFOL commit | `#{stamp.zkfol}` |
    | Zinc+ commit | `#{stamp.zinc}` (the `Cargo.lock` revision of `zinc-protocol`) |
    | CPU | #{stamp.cpu}, #{stamp.cores} cores |
    | Memory | #{stamp.memory} |
    | OS | #{stamp.os} |
    | Erlang / Elixir / Rust | #{stamp.erlang} / #{stamp.elixir} / #{stamp.rust} |
    | Date | #{stamp.date} |
    | Run order | cells run strictly one at a time, in the order below |
    | Load average at cell starts (1 minute) | #{stamp_load(cells)} |
    | CPU steal over the whole run | #{Float.round(steal * 100, 2)} % |

    "Uncontended" here means what those two rows say: the runner starts one cell at a time,
    and the load average and steal time above are what the machine reported. The load average
    covers the last minute, so it includes the runner's own proving in the cells before: it
    is an upper bound on what else was running. Steal is time the hypervisor took from this
    machine, and a value above zero means the machine was shared. Neither is a guarantee
    about anything outside the run.

    ## What the columns are

    - **Prove**: Zinc+ proving time, from the prover itself, in milliseconds.
    - **Verify**: the standalone verifier's own time, including its parameter setup, with no
      process start-up and no file reads. It never sees the plaintext.
    - **Proof**: the proof file the verifier is given, in kilobytes.
    - **RSS delta**: the process's peak resident memory during the prove, minus its resident
      memory before it, in whole megabytes (never below 0). The peak counter is reset first,
      as `Examples.EBench` does.
    - A **refused** cell is a statement the prover cannot prove. Its time is how long the
      prover ran before the statement failed to verify, and it has no proof.

    #{tables(cells)}

    ## Limits found while measuring

    - **Unroll budget.** The compiler unrolls a relation at every step of its derivation and
      stops at 3,000 sites, which is 999 codepoints for the no-dash rule. A longer text is
      refused before anything is derived.
    - **32-bit words.** The compiled program's lookup check works in 32-bit words: an
      allowlist of two entries wider than a word failed to prove (`Lookup(FinalEvaluationMismatch)`),
      so a destination is four words, the first 128 bits of the hash of its address.
    - **2^56.** An honest proof of a column holding a value above about 2^56 beside small
      ones is rejected, so every cell stays under it. Figures encode under 2^54, and the
      grounding sentinel is 2^55.
    """
  end

  @spec tables([Cell.t()]) :: String.t()
  defp tables(cells) do
    cells
    |> Enum.chunk_by(& &1.predicate)
    |> Enum.map_join("\n", fn [%Cell{predicate: predicate} | _] = group ->
      rows =
        Enum.map_join(group, "\n", fn %Cell{} = cell ->
          s = cell.samples

          case cell.outcome do
            :proved ->
              "| #{cell.label} | #{cell.shape} | #{span(s, & &1.prove_ms)} | #{span(s, & &1.verify_ms)} | #{span(s, fn sample -> sample.proof_bytes / 1024 end)} KB | #{span(s, & &1.rss_delta_mb)} MB |"

            :refused ->
              "| #{cell.label} | #{cell.shape} | refused after #{span(s, & &1.prove_ms)} | none | none | #{span(s, & &1.rss_delta_mb)} MB |"
          end
        end)

      "## #{predicate}\n\n| Input | Shape | Prove (ms) | Verify (ms) | Proof | RSS delta |\n|---|---|---|---|---|---|\n#{rows}\n"
    end)
  end

  @spec span([Sample.t()], (Sample.t() -> number())) :: String.t()
  defp span(samples, field) do
    values = Enum.map(samples, field)
    "#{fmt(median(values))} (#{fmt(Enum.min(values))} to #{fmt(Enum.max(values))})"
  end

  @spec stamp_load([Cell.t()]) :: String.t()
  defp stamp_load(cells) do
    loads = for cell <- cells, sample <- cell.samples, do: sample.load1
    "#{Float.round(Enum.min(loads), 2)} to #{Float.round(Enum.max(loads), 2)}"
  end

  @spec median([number()]) :: number()
  defp median(values) do
    sorted = Enum.sort(values)
    Enum.at(sorted, div(length(sorted), 2))
  end

  @spec fmt(number()) :: String.t()
  defp fmt(value) when is_integer(value), do: Integer.to_string(value)
  defp fmt(value) when value >= 100, do: Integer.to_string(round(value))
  defp fmt(value), do: :erlang.float_to_binary(value * 1.0, decimals: 1)

  @spec kb(number()) :: String.t()
  defp kb(bytes), do: fmt(bytes / 1024)

  @spec stamp() :: map()
  defp stamp do
    %{
      demo: commit(@root),
      zkfol: commit(@zkfol),
      zinc: zinc(),
      cpu: cpu(),
      cores: System.schedulers_online(),
      memory: memory(),
      os: os(),
      erlang:
        to_string(:erlang.system_info(:otp_release)) <>
          " (erts " <> to_string(:erlang.system_info(:version)) <> ")",
      elixir: System.version(),
      rust: command("rustc", ["--version"], @crate),
      date: Date.utc_today() |> Date.to_iso8601()
    }
  end

  @spec commit(Path.t()) :: String.t()
  defp commit(dir) do
    sha = command("git", ["rev-parse", "HEAD"], dir)

    dirty =
      if command("git", ["status", "--porcelain", "--", ".", ":!RESULTS.md"], dir) == "",
        do: "",
        else: " (with uncommitted changes)"

    sha <> dirty
  end

  @spec zinc() :: String.t()
  defp zinc do
    lock = File.read!(Path.join(@crate, "Cargo.lock"))

    case Regex.run(
           ~r/name = "zinc-protocol"\nversion = "[^"]+"\nsource = "git\+[^#]+#([0-9a-f]{40})"/,
           lock
         ) do
      [_, sha] -> sha
      nil -> "unknown"
    end
  end

  @spec cpu() :: String.t()
  defp cpu do
    case File.read("/proc/cpuinfo") do
      {:ok, text} ->
        (Regex.run(~r/model name\s*:\s*(.+)/, text) || [nil, "unknown"])
        |> List.last()
        |> String.trim()

      {:error, _} ->
        command("sysctl", ["-n", "machdep.cpu.brand_string"], @root)
    end
  end

  @spec memory() :: String.t()
  defp memory do
    case File.read("/proc/meminfo") do
      {:ok, text} ->
        [kb] = Regex.run(~r/MemTotal:\s+(\d+) kB/, text, capture: :all_but_first)
        "#{Float.round(String.to_integer(kb) / 1024 / 1024, 1)} GB"

      {:error, _} ->
        "unknown"
    end
  end

  @spec os() :: String.t()
  defp os do
    case File.read("/etc/os-release") do
      {:ok, text} ->
        (Regex.run(~r/PRETTY_NAME="([^"]+)"/, text) || [nil, "unknown"]) |> List.last()

      {:error, _} ->
        command("uname", ["-sr"], @root)
    end
  end

  @spec command(String.t(), [String.t()], Path.t()) :: String.t()
  defp command(program, args, dir) do
    case System.cmd(program, args, cd: dir, stderr_to_stdout: true) do
      {out, 0} -> String.trim(out)
      {_out, _status} -> "unknown"
    end
  rescue
    _ -> "unknown"
  end
end
