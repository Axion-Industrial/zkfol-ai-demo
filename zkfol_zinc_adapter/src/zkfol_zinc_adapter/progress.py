"""Progress-aware subprocess helpers for long Cargo/Zinc runs.

The Zinc proof-of-concept does not expose fine-grained callbacks while a proof
is being produced.  The Rust runner therefore emits coarse phase markers on
stderr when called with ``--progress``.  This module wraps the process, parses
those markers, and prints a periodic heartbeat with elapsed time, coarse
percentage, ETA estimate, and approximate process-tree CPU and memory usage.
"""

from __future__ import annotations

import json
import os
import queue
import shlex
import subprocess
import sys
import threading
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Sequence

from .constraint_summary import compute_constraint_summary
from .resources import estimate_zinc_resources, format_bytes as format_resource_bytes

PROGRESS_PREFIX = "FOLZINC_PROGRESS "


@dataclass
class ProcessResult:
    """Return value from :func:`run_with_progress`."""

    returncode: int
    stdout: str
    stderr: str


@dataclass
class MemorySnapshot:
    """Approximate live resource snapshot for a process tree.

    Values are Linux ``/proc`` snapshots.  ``rss_bytes`` is current resident
    memory for the root process and descendants visible at the instant of the
    snapshot.  ``hwm_bytes`` sums the current processes' VmHWM values, which is
    useful but not an exact all-time tree high-water mark.  The heartbeat keeps
    its own max-over-snapshots value and labels it as an approximate peak.
    """

    rss_bytes: int
    hwm_bytes: int
    process_count: int
    top_processes: list[tuple[str, int]] = field(default_factory=list)


@dataclass
class ProgressState:
    """Mutable state used by the heartbeat formatter."""

    input_path: Path | None
    repeat: int
    check_only: bool
    started_at: float = field(default_factory=time.monotonic)
    current_phase: str = "cargo"
    current_message: str = "starting Cargo / Zinc runner"
    current_iteration: int | None = None
    current_repeat: int | None = None
    completed_units: int = 0
    total_units: int = 1
    seen_runner_marker: bool = False
    last_event: dict[str, Any] | None = None
    case_name: str | None = None
    constraints: int | None = None
    witness_vars: int | None = None
    int_bits: int | None = None
    scalar_variables: int | None = None
    ccs_degree: int | None = None
    simplified_degree: int | None = None
    bit_bound_delta: int | None = None
    estimated_dense_bytes: int | None = None
    estimated_padded_dim: int | None = None
    phase_durations_ms: dict[str, list[float]] = field(default_factory=dict)
    last_rss_bytes: int | None = None
    peak_rss_bytes: int | None = None
    last_process_count: int | None = None
    last_top_processes: list[tuple[str, int]] = field(default_factory=list)

    @classmethod
    def from_input(cls, input_path: Path | None, repeat: int, check_only: bool, int_limbs: str | int | None = None) -> "ProgressState":
        total_units = 1 if check_only else 1 + 4 * max(1, repeat)
        state = cls(input_path=input_path, repeat=repeat, check_only=check_only, total_units=total_units)
        if input_path is not None:
            try:
                with Path(input_path).open("r", encoding="utf-8") as f:
                    data = json.load(f)
                state.case_name = data.get("benchmark_case", {}).get("stem") or data.get("name") or Path(input_path).stem
                dims = data.get("dimensions", {})
                stats = data.get("stats", {})
                state.constraints = _maybe_int(dims.get("constraints"))
                state.witness_vars = _maybe_int(dims.get("witness_variables"))
                state.int_bits = _maybe_int(stats.get("max_abs_value_bit_length"))
                try:
                    shape = compute_constraint_summary(data)
                    state.scalar_variables = _maybe_int(shape.get("scalar_variables_unpadded"))
                    state.ccs_degree = _maybe_int(shape.get("ccs_declared_degree"))
                    state.simplified_degree = _maybe_int(shape.get("max_simplified_degree_over_private_witness"))
                    state.bit_bound_delta = _maybe_int(shape.get("bit_bound_delta"))
                except Exception:
                    pass
                try:
                    estimate = estimate_zinc_resources(Path(input_path), int_limbs=int_limbs)
                    state.estimated_dense_bytes = estimate.largest_dense_allocation_bytes
                    state.estimated_padded_dim = estimate.estimated_padded_dim
                except Exception:
                    pass
            except Exception:
                state.case_name = Path(input_path).stem
        return state

    def handle_event(self, event: dict[str, Any]) -> None:
        self.seen_runner_marker = True
        self.last_event = event
        phase = str(event.get("phase", self.current_phase))
        kind = str(event.get("event", ""))
        self.current_phase = phase
        self.current_message = str(event.get("message") or _phase_label(phase))
        self.current_iteration = _maybe_int(event.get("iteration"))
        self.current_repeat = _maybe_int(event.get("repeat")) or self.current_repeat
        elapsed_ms = _maybe_float(event.get("elapsed_ms"))
        if elapsed_ms is not None:
            self.phase_durations_ms.setdefault(phase, []).append(elapsed_ms)
        if kind == "end" and phase in {"relation_check", "build_ccs", "field_setup", "random_field_setup", "field_relation_check", "prove", "verify"}:
            self.completed_units = min(self.total_units, self.completed_units + 1)
        elif kind == "finish":
            self.completed_units = self.total_units
            self.current_message = str(event.get("message") or "runner finished")

    def update_memory(self, memory: MemorySnapshot | None) -> None:
        if memory is None:
            return
        self.last_rss_bytes = memory.rss_bytes
        self.last_process_count = memory.process_count
        self.last_top_processes = memory.top_processes[:3]
        candidates = [memory.rss_bytes]
        if memory.hwm_bytes > 0:
            candidates.append(memory.hwm_bytes)
        observed_peak = max(candidates)
        if self.peak_rss_bytes is None or observed_peak > self.peak_rss_bytes:
            self.peak_rss_bytes = observed_peak

    def heartbeat(self, *, cpu_percent: float | None, memory: MemorySnapshot | None = None) -> str:
        self.update_memory(memory)
        now = time.monotonic()
        elapsed = now - self.started_at
        pct = 100.0 * self.completed_units / max(1, self.total_units)
        stage = _phase_label(self.current_phase)
        if self.current_iteration is not None and self.current_repeat:
            stage = f"{stage} {self.current_iteration}/{self.current_repeat}"
        case = f"case={self.case_name} | " if self.case_name else ""
        size = []
        if self.constraints is not None:
            size.append(f"constraints={self.constraints:,}")
        if self.witness_vars is not None:
            size.append(f"witness_vars={self.witness_vars:,}")
        if self.scalar_variables is not None:
            size.append(f"variables={self.scalar_variables:,}")
        if self.ccs_degree is not None:
            degree = f"degree={self.ccs_degree}"
            if self.simplified_degree is not None and self.simplified_degree != self.ccs_degree:
                degree += f"/simp≤{self.simplified_degree}"
            size.append(degree)
        if self.bit_bound_delta is not None:
            size.append(f"bit_bound={self.bit_bound_delta:,}")
        elif self.int_bits is not None:
            size.append(f"int_bits={self.int_bits:,}")
        if self.estimated_dense_bytes is not None:
            if self.estimated_padded_dim is not None:
                size.append(f"est_dense={format_resource_bytes(self.estimated_dense_bytes)}@{self.estimated_padded_dim:,}^2")
            else:
                size.append(f"est_dense={format_resource_bytes(self.estimated_dense_bytes)}")
        size_text = " | ".join(size)
        if size_text:
            size_text = " | " + size_text
        eta = self._eta_text(elapsed)
        cpu = "CPU n/a" if cpu_percent is None else f"CPU {cpu_percent:5.1f}%"
        memory_text = self._memory_text(current_snapshot=memory is not None)
        exactness = "coarse progress" if self.seen_runner_marker else "waiting for runner markers"
        return (
            f"[folzinc progress] {case}elapsed {format_duration(elapsed)} | "
            f"{stage} | {self.current_message} | "
            f"{self.completed_units}/{self.total_units} units ({pct:5.1f}%) | "
            f"ETA {eta} | {cpu} | {memory_text} | {exactness}{size_text}"
        )

    def _memory_text(self, *, current_snapshot: bool) -> str:
        if self.last_rss_bytes is None:
            return "RSS n/a"
        label = "RSS" if current_snapshot else "RSS last"
        parts = [f"{label} {format_bytes(self.last_rss_bytes)}"]
        if self.peak_rss_bytes is not None:
            parts.append(f"peak RSS {format_bytes(self.peak_rss_bytes)}")
        if self.last_process_count is not None:
            parts.append(f"procs {self.last_process_count}")
        if self.last_top_processes:
            top = ", ".join(f"{name}:{format_bytes(rss)}" for name, rss in self.last_top_processes if rss > 0)
            if top:
                parts.append(f"top {top}")
        return " | ".join(parts)

    def _eta_text(self, elapsed: float) -> str:
        remaining = self.total_units - self.completed_units
        if remaining <= 0:
            return "00:00"
        if self.completed_units <= 0:
            return "estimating"
        avg = elapsed / self.completed_units
        return "~" + format_duration(avg * remaining)


def run_with_progress(
    cmd: Sequence[str],
    *,
    input_path: Path | None = None,
    repeat: int = 1,
    check_only: bool = False,
    quiet: bool = False,
    progress: bool = True,
    interval: float = 5.0,
    capture_stdout: bool = False,
    int_limbs: str | int | None = None,
) -> ProcessResult:
    """Run ``cmd`` and optionally print a progress heartbeat.

    Progress is intentionally coarse.  Zinc itself does not tell us how far it is
    through a single ``prove`` call, so the percentage is based on completed
    top-level units: local relation check, sampled random-field setup,
    sampled-field relation check, each prove run, and each verify run.  CPU and memory are approximate Linux
    process-tree snapshots rooted at the Cargo/Zinc process.
    """
    cmd_list = [str(c) for c in cmd]
    if not quiet:
        print("$ " + shlex.join(cmd_list))
    if quiet or not progress:
        proc = subprocess.run(
            cmd_list,
            text=True,
            stdout=subprocess.PIPE if capture_stdout else None,
            stderr=subprocess.PIPE if capture_stdout else None,
        )
        return ProcessResult(proc.returncode, proc.stdout or "", proc.stderr or "")

    interval = max(1.0, float(interval))
    state = ProgressState.from_input(input_path, repeat=repeat, check_only=check_only, int_limbs=int_limbs)
    if input_path is not None:
        intro = state.heartbeat(cpu_percent=None, memory=None)
        print(intro, file=sys.stderr, flush=True)
        print(
            "[folzinc progress] Note: percentage is coarse. Inside a single Zinc prove call, "
            "elapsed time, CPU, and RSS continue to update but exact sub-progress is not available.",
            file=sys.stderr,
            flush=True,
        )

    proc = subprocess.Popen(
        cmd_list,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        bufsize=1,
    )
    assert proc.stdout is not None
    assert proc.stderr is not None

    # Capture an initial memory sample so even short successful runs often end
    # with a useful "RSS last" value.
    state.update_memory(read_process_tree_memory_snapshot(proc.pid))

    output_queue: "queue.Queue[tuple[str, str]]" = queue.Queue()
    stdout_parts: list[str] = []
    stderr_parts: list[str] = []

    def reader(name: str, stream: Any) -> None:
        try:
            for line in stream:
                output_queue.put((name, line))
        finally:
            output_queue.put((name, ""))

    threads = [
        threading.Thread(target=reader, args=("stdout", proc.stdout), daemon=True),
        threading.Thread(target=reader, args=("stderr", proc.stderr), daemon=True),
    ]
    for thread in threads:
        thread.start()

    alive_streams = {"stdout", "stderr"}
    last_heartbeat = time.monotonic()
    last_cpu_time = read_process_tree_cpu_seconds(proc.pid)
    last_cpu_wall = last_heartbeat

    while alive_streams:
        now = time.monotonic()
        timeout = max(0.1, min(0.5, interval - (now - last_heartbeat)))
        try:
            name, line = output_queue.get(timeout=timeout)
        except queue.Empty:
            line = None
            name = ""
        if line is None:
            pass
        elif line == "":
            alive_streams.discard(name)
        elif name == "stdout":
            stdout_parts.append(line)
            if not capture_stdout:
                sys.stdout.write(line)
                sys.stdout.flush()
        else:
            if line.startswith(PROGRESS_PREFIX):
                try:
                    event = json.loads(line[len(PROGRESS_PREFIX) :])
                    state.handle_event(event)
                except Exception:
                    stderr_parts.append(line)
                    sys.stderr.write(line)
                    sys.stderr.flush()
            else:
                stderr_parts.append(line)
                sys.stderr.write(line)
                sys.stderr.flush()

        now = time.monotonic()
        if now - last_heartbeat >= interval:
            cpu_time = read_process_tree_cpu_seconds(proc.pid)
            cpu_percent = None
            if cpu_time is not None and last_cpu_time is not None:
                wall_delta = max(1e-9, now - last_cpu_wall)
                cpu_percent = max(0.0, 100.0 * (cpu_time - last_cpu_time) / wall_delta)
            memory = read_process_tree_memory_snapshot(proc.pid)
            last_cpu_time = cpu_time
            last_cpu_wall = now
            last_heartbeat = now
            print(state.heartbeat(cpu_percent=cpu_percent, memory=memory), file=sys.stderr, flush=True)

    returncode = proc.wait()
    for thread in threads:
        thread.join(timeout=0.2)

    if returncode == 0:
        state.completed_units = state.total_units
    print(state.heartbeat(cpu_percent=None, memory=None), file=sys.stderr, flush=True)
    return ProcessResult(returncode, "".join(stdout_parts), "".join(stderr_parts))


def format_duration(seconds: float) -> str:
    seconds_i = max(0, int(round(seconds)))
    hours, rem = divmod(seconds_i, 3600)
    minutes, secs = divmod(rem, 60)
    if hours:
        return f"{hours:d}:{minutes:02d}:{secs:02d}"
    return f"{minutes:02d}:{secs:02d}"


def format_bytes(num_bytes: int | float | None) -> str:
    if num_bytes is None:
        return "n/a"
    value = float(max(0.0, num_bytes))
    units = ["B", "KiB", "MiB", "GiB", "TiB"]
    unit = units[0]
    for unit in units:
        if value < 1024.0 or unit == units[-1]:
            break
        value /= 1024.0
    if unit == "B":
        return f"{int(value)} {unit}"
    return f"{value:.1f} {unit}"


def read_process_tree_cpu_seconds(root_pid: int) -> float | None:
    """Approximate total CPU seconds for ``root_pid`` and current descendants.

    Linux-only.  Returns ``None`` when /proc is unavailable.  The value is a
    snapshot: CPU used by very short-lived child processes that have already
    exited may not be counted, which is acceptable for a live heartbeat.
    """
    proc_dir = Path("/proc")
    if not proc_dir.exists():
        return None
    try:
        ticks_per_second = os.sysconf(os.sysconf_names["SC_CLK_TCK"])
    except Exception:
        return None
    stats: dict[int, tuple[int, float]] = {}
    for entry in proc_dir.iterdir():
        if not entry.name.isdigit():
            continue
        pid = int(entry.name)
        try:
            raw = (entry / "stat").read_text(encoding="utf-8")
        except Exception:
            continue
        parsed = _parse_proc_stat(raw, ticks_per_second)
        if parsed is not None:
            stats[pid] = parsed
    if root_pid not in stats:
        return None
    descendants = _descendants(root_pid, {pid: ppid for pid, (ppid, _cpu) in stats.items()})
    return sum(stats[pid][1] for pid in descendants if pid in stats)


def read_process_tree_memory_snapshot(root_pid: int) -> MemorySnapshot | None:
    """Approximate RSS for ``root_pid`` and current descendants.

    Linux-only.  The result is intentionally best-effort: processes can exit
    while /proc is being scanned, and short-lived children may be missed.
    """
    proc_dir = Path("/proc")
    if not proc_dir.exists():
        return None
    entries: dict[int, dict[str, Any]] = {}
    for entry in proc_dir.iterdir():
        if not entry.name.isdigit():
            continue
        pid = int(entry.name)
        try:
            status = (entry / "status").read_text(encoding="utf-8", errors="replace")
        except Exception:
            continue
        info = _parse_proc_status(status)
        if info is None:
            continue
        try:
            comm = (entry / "comm").read_text(encoding="utf-8", errors="replace").strip()
        except Exception:
            comm = info.get("name") or str(pid)
        info["name"] = _short_process_name(comm or info.get("name") or str(pid))
        entries[pid] = info
    if root_pid not in entries:
        return None
    parent_map = {pid: int(info.get("ppid", -1)) for pid, info in entries.items()}
    descendants = _descendants(root_pid, parent_map)
    rss_total = 0
    hwm_total = 0
    process_rows: list[tuple[str, int]] = []
    for pid in descendants:
        info = entries.get(pid)
        if info is None:
            continue
        rss = int(info.get("rss_bytes", 0) or 0)
        hwm = int(info.get("hwm_bytes", 0) or 0)
        rss_total += rss
        hwm_total += hwm
        process_rows.append((str(info.get("name") or pid), rss))
    process_rows.sort(key=lambda item: item[1], reverse=True)
    return MemorySnapshot(
        rss_bytes=rss_total,
        hwm_bytes=hwm_total,
        process_count=len(descendants),
        top_processes=process_rows[:3],
    )


def _descendants(root_pid: int, parent_map: dict[int, int]) -> set[int]:
    descendants = {root_pid}
    changed = True
    while changed:
        changed = False
        for pid, ppid in parent_map.items():
            if ppid in descendants and pid not in descendants:
                descendants.add(pid)
                changed = True
    return descendants


def _parse_proc_stat(raw: str, ticks_per_second: int) -> tuple[int, float] | None:
    try:
        rparen = raw.rfind(")")
        if rparen < 0:
            return None
        parts = raw[rparen + 2 :].split()
        ppid = int(parts[1])
        utime = int(parts[11])
        stime = int(parts[12])
        return ppid, (utime + stime) / float(ticks_per_second)
    except Exception:
        return None


def _parse_proc_status(status: str) -> dict[str, Any] | None:
    out: dict[str, Any] = {}
    for line in status.splitlines():
        if line.startswith("Name:"):
            out["name"] = line.split(":", 1)[1].strip()
        elif line.startswith("PPid:"):
            try:
                out["ppid"] = int(line.split(":", 1)[1].strip())
            except Exception:
                return None
        elif line.startswith("VmRSS:"):
            out["rss_bytes"] = _status_kb_to_bytes(line)
        elif line.startswith("VmHWM:"):
            out["hwm_bytes"] = _status_kb_to_bytes(line)
    if "ppid" not in out:
        return None
    out.setdefault("rss_bytes", 0)
    out.setdefault("hwm_bytes", out["rss_bytes"])
    return out


def _status_kb_to_bytes(line: str) -> int:
    try:
        # Lines are of the form "VmRSS:\t  12345 kB".
        return int(line.split(":", 1)[1].strip().split()[0]) * 1024
    except Exception:
        return 0


def _short_process_name(name: str, limit: int = 18) -> str:
    cleaned = "".join(ch if ch.isalnum() or ch in "._+-" else "_" for ch in name.strip())
    if len(cleaned) <= limit:
        return cleaned
    return cleaned[: limit - 1] + "..."


def _phase_label(phase: str) -> str:
    labels = {
        "cargo": "Cargo/build/launch",
        "load": "Load input",
        "relation_check": "Local relation check",
        "build_ccs": "Local relation check",
        "field_setup": "Zinc random-prime setup",
        "field_relation_check": "Sampled-field relation check",
        "random_field_setup": "Sampled random-field setup",
        "prove": "Zinc prove",
        "verify": "Zinc verify",
        "finish": "Finish",
    }
    return labels.get(phase, phase.replace("_", " "))


def _maybe_int(value: Any) -> int | None:
    try:
        if value is None or value == "":
            return None
        return int(value)
    except Exception:
        return None


def _maybe_float(value: Any) -> float | None:
    try:
        if value is None or value == "":
            return None
        return float(value)
    except Exception:
        return None
