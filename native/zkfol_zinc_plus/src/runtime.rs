//! The interpreted UAIR: signature and constraint fed from Elixir terms.
//!
//! zinc-plus's Uair trait is static (no self), so the spec lives in a
//! module global whose only writer is the prover thread: one statement
//! owns it from dequeue until its verdict.

use std::any::{Any, TypeId};
use std::collections::BTreeMap;
use std::sync::Mutex;

use zinc_poly::{
    mle::DenseMultilinearExtension,
    univariate::{binary::BinaryPoly, dense::DensePolynomial},
};
use zinc_uair::{
    ideal::DegreeOneIdeal, ConstraintBuilder, LookupColumnSpec, LookupTableType,
    PublicColumnLayout, ShiftSpec, TotalColumnLayout, TraceRow, Uair, UairSignature, UairTrace,
};

use crate::config::D;

/// One postfix op of the constraint program.
#[derive(Clone, Debug)]
pub enum Op {
    Up(usize),
    Down(usize),
    Const(i64),
    Add,
    Mul,
}

#[derive(Clone, Debug, Default)]
pub struct Spec {
    pub num_cols: usize,
    pub num_public: usize,
    pub bin_cols: usize,
    pub shifts: Vec<(usize, usize)>,
    pub program: Vec<Op>,
    /// BitPoly lookups: (binary column, table width, chunk width).
    pub lookups: Vec<(usize, usize, usize)>,
}

pub static SPEC: Mutex<Option<Spec>> = Mutex::new(None);

fn spec() -> Spec {
    SPEC.lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
        .clone()
        .expect("runtime uair spec unset")
}

/// Constant scalars at leaked stable addresses, one per (cell type, value).
/// zinc's projection cache keys scalars by raw pointer, so stack temporaries
/// alias each other and resolve as the wrong constant.
static CONSTS: Mutex<BTreeMap<(TypeId, i64), &'static (dyn Any + Send + Sync)>> =
    Mutex::new(BTreeMap::new());

/// The stable home of constant `k` at cell type `I`, allocated once for the process.
fn const_scalar<I>(k: i64) -> &'static DensePolynomial<I, D>
where
    I: crypto_primitives::ConstIntSemiring + From<i64> + 'static,
{
    let mut consts = CONSTS
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    let entry: &'static (dyn Any + Send + Sync) = *consts
        .entry((TypeId::of::<I>(), k))
        .or_insert_with(|| Box::leak(Box::new(DensePolynomial::<I, D>::new([I::from(k)]))));
    entry
        .downcast_ref()
        .expect("const table entry matches its TypeId key")
}

#[derive(Clone, Debug)]
pub struct RuntimeUair<I>(std::marker::PhantomData<I>);

impl<I> Uair for RuntimeUair<I>
where
    I: crypto_primitives::ConstIntSemiring + From<i64> + 'static,
{
    type Ideal = DegreeOneIdeal<I>;
    type Scalar = DensePolynomial<I, D>;

    fn signature() -> UairSignature {
        let spec = spec();
        let total = TotalColumnLayout::new(spec.bin_cols, 0, spec.num_cols);
        let public = PublicColumnLayout::new(0, 0, spec.num_public);
        // Shift sources are flat-indexed (binary_poly || arbitrary_poly ||
        // int), so int shifts move past the binary section.
        let shifts = spec
            .shifts
            .iter()
            .map(|&(col, amount)| ShiftSpec::new(spec.bin_cols + col, amount))
            .collect();
        let lookups = spec
            .lookups
            .iter()
            .map(|&(col, width, chunk)| LookupColumnSpec {
                column_index: col,
                table_type: LookupTableType::BitPoly {
                    width,
                    chunk_width: Some(chunk),
                },
            })
            .collect();
        UairSignature::new(total, public, shifts, lookups, vec![])
    }

    fn constrain_general<B, FromR, MBS, IFromR>(
        b: &mut B,
        up: TraceRow<B::Expr>,
        down: TraceRow<B::Expr>,
        from_ref: FromR,
        _mbs: MBS,
        _ideal_from_ref: IFromR,
    ) where
        B: ConstraintBuilder,
        FromR: Fn(&Self::Scalar) -> B::Expr,
        MBS: Fn(&B::Expr, &Self::Scalar) -> Option<B::Expr>,
        IFromR: Fn(&Self::Ideal) -> B::Ideal,
    {
        let spec = spec();
        let mut stack: Vec<B::Expr> = Vec::new();

        for op in &spec.program {
            match op {
                Op::Up(col) => stack.push(up.int[*col].clone()),
                Op::Down(idx) => stack.push(down.int[*idx].clone()),
                Op::Const(k) => stack.push(from_ref(const_scalar::<I>(*k))),
                Op::Add => {
                    let rhs = stack.pop().expect("add rhs");
                    let lhs = stack.pop().expect("add lhs");
                    stack.push(lhs + &rhs);
                }
                Op::Mul => {
                    let rhs = stack.pop().expect("mul rhs");
                    let lhs = stack.pop().expect("mul lhs");
                    stack.push(lhs * &rhs);
                }
            }
        }

        let root = stack.pop().expect("program leaves one root");
        assert!(stack.is_empty(), "program leaves exactly one root");
        b.assert_zero(root);
    }
}

/// Binary columns from u32 bit patterns, one BinaryPoly cell per row.
pub fn bin_columns(
    bins: Vec<Vec<u32>>,
    num_vars: usize,
) -> Vec<DenseMultilinearExtension<BinaryPoly<D>>> {
    bins.into_iter()
        .map(|patterns| {
            let evals = patterns.into_iter().map(BinaryPoly::<D>::from).collect();
            DenseMultilinearExtension::from_evaluations_vec(num_vars, evals, BinaryPoly::from(0u32))
        })
        .collect()
}

/// Build the trace from evaluation columns, each already padded to
/// 2^num_vars rows, plus any binary shadow columns.
pub fn trace(
    columns: Vec<Vec<i64>>,
    bins: Vec<Vec<u32>>,
    num_vars: usize,
) -> UairTrace<'static, i64, i64, D> {
    let int = columns
        .into_iter()
        .map(|evals| DenseMultilinearExtension::from_evaluations_vec(num_vars, evals, 0i64))
        .collect::<Vec<_>>();

    UairTrace {
        binary_poly: std::borrow::Cow::Owned(bin_columns(bins, num_vars)),
        arbitrary_poly: std::borrow::Cow::Owned(vec![]),
        int: std::borrow::Cow::Owned(int),
    }
}

/// A wide trace from sign-free u64 limb lists, at any cell width.
pub fn limb_trace<const N: usize>(
    columns: Vec<Vec<Vec<u64>>>,
    bins: Vec<Vec<u32>>,
    num_vars: usize,
) -> UairTrace<
    'static,
    crypto_primitives::crypto_bigint_int::Int<N>,
    crypto_primitives::crypto_bigint_int::Int<N>,
    D,
> {
    type Cell<const N: usize> = crypto_primitives::crypto_bigint_int::Int<N>;
    let int = columns
        .into_iter()
        .map(|col| {
            let evals = col
                .into_iter()
                .map(|limbs| {
                    let mut words = [0u64; N];
                    words[..limbs.len()].copy_from_slice(&limbs);
                    Cell::<N>::from_words(words)
                })
                .collect::<Vec<_>>();
            DenseMultilinearExtension::from_evaluations_vec(num_vars, evals, Cell::<N>::from(0i64))
        })
        .collect::<Vec<_>>();

    UairTrace {
        binary_poly: std::borrow::Cow::Owned(bin_columns(bins, num_vars)),
        arbitrary_poly: std::borrow::Cow::Owned(vec![]),
        int: std::borrow::Cow::Owned(int),
    }
}
