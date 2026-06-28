# Paper guide for the zkFOL reference implementation

This file maps the definitions in `paper/fol-zinc.pdf` to the reference source tree.  It is intended for readers who want to audit that the executable examples follow the paper rather than merely printing canned output.

| Paper item | Meaning | Source location |
| --- | --- | --- |
| Figure 1 | FOL terms, predicates, range checks, enriched-polynomial syntax | `src/zkfol/ast.py` |
| Definition 2.2 | least-significant-bit-first `b2int` and bit expansion | `src/zkfol/bits.py` |
| Figure 2 | map terms/predicates to enriched polynomials: equality as square, conjunction as sum, disjunction as product | `src/zkfol/ast.py`, `src/zkfol/compiler.py` |
| Figure 3 / Theorem 2.19 | zero-is-true integer semantics | `src/zkfol/ast.py` evaluation methods |
| Definition 3.1 / 3.7 | pointer rows must be range-checked | `src/zkfol/witness.py`, example `pointer_rows` |
| Definition 3.5 / Figure 4 | `mkQ_x^F` over `B` variables (uniform bitwise encoding) | `src/zkfol/compiler.py` |
| Definition 3.6 | `beta_F` substitution of witness bits, with out-of-range composed pointers mapping to zero | `src/zkfol/compiler.py`, `src/zkfol/fast_beta.py` |
| Theorem 3.8 | `beta(mkQ(<phi>))` equals direct integer semantics when range checks hold | CLI comparison in `src/zkfol/cli.py`; tests in `tests/` |
| Section 4 optimisation (the "design space of optimal syntactic forms" remark) | `num`/`ptr` type system: only rows used as a pointer `C_j` need a bitwise representation, the rest are plain integers | `src/zkfol/types.py` |
| Section 4 optimisation, cont. | typed `mkQ`/`beta`: each cell becomes a single integer value symbol `V_{i,j,x}` instead of `b2int(B...)`, proven equal to the bitwise route and to the direct semantics | `src/zkfol/typed_compiler.py`; `tests/test_typed_compiler.py` |
| Section 5 power example | standard recursive power predicate and witness | `src/zkfol/examples.py`, `src/zkfol/witnesses.py` |
| Section 5 SK example | SK reduction using shifted Cantor pairing and arity-8 witness matrix | `src/zkfol/sk.py` |
| Appendix A | implementation of the FOL-to-`mkQ` transform and `beta_F` evaluation for examples | this reference tree plus the adapter package |

The adapter in `../zkfol_zinc_adapter/` starts from these reference examples and exports signed integer CCS/R1CS JSON for the current Zinc Rust proof-of-concept.
