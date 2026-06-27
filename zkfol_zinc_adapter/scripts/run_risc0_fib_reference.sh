#!/usr/bin/env bash
set -euo pipefail

cat <<'EOF'
Run this inside a checked-out RISC Zero repository, using the RISC Zero version
and hardware you want to compare against:

  cargo bench --bench fib

The official RISC Zero docs state that this benchmark computes the 100th,
1000th, and 10000th Fibonacci numbers modulo 2^64 ten times each, with separate
execution and proving statistics. Copy the resulting numbers into
benchmark_inputs/risc0_fib_exact/risc0_fibonacci_reference_notes.csv or docs/zkvm_result_template.csv.

This script does not clone or modify a RISC Zero checkout automatically.
EOF
