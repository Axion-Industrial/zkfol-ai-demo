# Running zkFOL

From this directory, run:

```bash
./run
```

This validates all bundled examples.  The same command is available as:

```bash
python3 run.py
python3 -m zkfol        # after installation or with src on PYTHONPATH
```

## Useful commands

```bash
./run --help
./run --quiet
./run --json
./run --example power --power-base 5 --power-exponent 4
./run --example efficient --efficient-base 3 --efficient-exponent 10
./run --example factorial --factorial-n 7
./run --example fibonacci --fibonacci-n 12
./run --example sk
./run --symbolic
./run tests
make test
```

The `--symbolic` option constructs explicit SymPy `mkQ` polynomials for the
arithmetic examples.  The full SK predicate is large, so the CLI keeps that path
on the fast evaluator; `tests/test_sk.py` contains checks for the displayed Sred
branch and separate fast/direct checks for the full SK predicate.

## Changing what gets tested

The help text points to the edit locations directly:

```bash
./run --help
```

For broader automated sweeps, edit the constants in
`tests/test_parameter_grid.py`.  For intentionally invalid cases, edit
`tests/test_negative_controls.py` and the negative SK tests in `tests/test_sk.py`.
