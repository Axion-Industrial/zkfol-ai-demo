//! The interpreted UAIR: signature and constraint fed from Elixir terms.
//!
//! zinc-plus's Uair trait is static (no self), so the spec lives in a
//! module global whose only writer is the prover thread: one statement
//! owns it from dequeue until its verdict.

use std::sync::Mutex;

use zinc_poly::{mle::DenseMultilinearExtension, univariate::dense::DensePolynomial};
use zinc_uair::{
    ideal::{DegreeOneIdeal, ImpossibleIdeal},
    ConstraintBuilder, PublicColumnLayout, ShiftSpec, TotalColumnLayout, TraceRow, Uair,
    UairSignature, UairTrace,
};

use crate::config::{D, FIELD_LIMBS};
use crypto_primitives::crypto_bigint_uint::Uint;

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
    pub shifts: Vec<(usize, usize)>,
    pub program: Vec<Op>,
}

pub static SPEC: Mutex<Option<Spec>> = Mutex::new(None);

fn spec() -> Spec {
    SPEC.lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
        .clone()
        .expect("runtime uair spec unset")
}

#[derive(Clone, Debug)]
pub struct RuntimeUair<I>(std::marker::PhantomData<I>);

impl<I> Uair for RuntimeUair<I>
where
    I: crypto_primitives::ConstIntSemiring + From<i64> + 'static,
{
    type Ideal = DegreeOneIdeal<I>;
    type FqIdeal = ImpossibleIdeal;
    type Scalar = DensePolynomial<I, D>;
    type Prime = Uint<FIELD_LIMBS>;

    fn signature() -> UairSignature<Self::Prime> {
        let spec = spec();
        let total = TotalColumnLayout::new(0, 0, spec.num_cols);
        let public = PublicColumnLayout::new(0, 0, spec.num_public);
        let shifts = spec
            .shifts
            .iter()
            .map(|&(col, amount)| ShiftSpec::new(col, amount))
            .collect();
        UairSignature::new(total, public, shifts, vec![])
    }

    fn constrain_general<B, FromR, MBS, IFromR, IFqFromR>(
        b: &mut B,
        up: TraceRow<B::Expr>,
        down: TraceRow<B::Expr>,
        from_ref: FromR,
        _mbs: MBS,
        _ideal_from_ref: IFromR,
        _fq_ideal_from_ref: IFqFromR,
    ) where
        B: ConstraintBuilder,
        FromR: Fn(&Self::Scalar) -> B::Expr,
        MBS: Fn(&B::Expr, &Self::Scalar) -> Option<B::Expr>,
        IFromR: Fn(&Self::Ideal) -> B::Ideal,
        IFqFromR: Fn(&Self::FqIdeal) -> B::FqIdeal,
    {
        let spec = spec();
        let mut stack: Vec<B::Expr> = Vec::new();

        for op in &spec.program {
            match op {
                Op::Up(col) => stack.push(up.int[*col].clone()),
                Op::Down(idx) => stack.push(down.int[*idx].clone()),
                Op::Const(k) => stack.push(from_ref(&DensePolynomial::new([I::from(*k)]))),
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

/// Build the int-only trace from evaluation columns, each already padded
/// to 2^num_vars rows.
pub fn trace(columns: Vec<Vec<i64>>, num_vars: usize) -> UairTrace<'static, i64, i64, D, D> {
    let int = columns
        .into_iter()
        .map(|evals| DenseMultilinearExtension::from_evaluations_vec(num_vars, evals, 0i64))
        .collect::<Vec<_>>();

    UairTrace {
        binary_poly: std::borrow::Cow::Owned(vec![]),
        arbitrary_poly: std::borrow::Cow::Owned(vec![]),
        int: std::borrow::Cow::Owned(int),
    }
}

/// A wide trace from sign-free u64 limb lists, at any cell width.
pub fn limb_trace<const N: usize>(
    columns: Vec<Vec<Vec<u64>>>,
    num_vars: usize,
) -> UairTrace<
    'static,
    crypto_primitives::crypto_bigint_int::Int<N>,
    crypto_primitives::crypto_bigint_int::Int<N>,
    D,
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
        binary_poly: std::borrow::Cow::Owned(vec![]),
        arbitrary_poly: std::borrow::Cow::Owned(vec![]),
        int: std::borrow::Cow::Owned(int),
    }
}
