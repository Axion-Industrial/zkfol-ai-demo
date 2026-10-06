//! The portable form of a proof: what a verifier on another machine receives.
//!
//! A proof travels as two files. `<prefix>.proof` is the protocol's own byte encoding of
//! the proof. `<prefix>.public.json` is a `Statement`: the circuit's spec, the tier and
//! the public columns, and nothing the prover kept private. The verifier needs no third
//! input, since the public parameters follow deterministically from `num_vars`.

use std::time::Instant;

use rustler::NifTaggedEnum;
use serde::{Deserialize, Serialize};
use zinc_protocol::Proof;
use zinc_transcript::traits::{GenTranscribable, Transcribable};

use crate::config::{setup_big_pp, setup_huge_pp, setup_pp, BigCfg, BigInt, Cfg, HugeCfg, HugeInt, F};
use crate::runtime::{self, Spec, SPEC};

/// The trace payload as Elixir tags it, one variant per cell width.
#[derive(NifTaggedEnum, Clone, Debug, Serialize, Deserialize)]
pub enum Payload {
    I64(Vec<Vec<i64>>),
    Big(Vec<Vec<Vec<u64>>>),
    Huge(Vec<Vec<Vec<u64>>>),
}

impl Payload {
    /// The first `n` columns: the public ones, which lead the trace.
    pub fn public(&self, n: usize) -> Payload {
        match self {
            Payload::I64(columns) => Payload::I64(columns[..n].to_vec()),
            Payload::Big(columns) => Payload::Big(columns[..n].to_vec()),
            Payload::Huge(columns) => Payload::Huge(columns[..n].to_vec()),
        }
    }
}

/// Everything a verifier is told besides the proof.
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Statement {
    pub num_vars: usize,
    pub spec: Spec,
    pub public: Payload,
}

/// The proof in the protocol's own little-endian, length-prefixed encoding.
pub fn encode_proof(proof: &Proof<F>) -> Vec<u8> {
    let mut bytes = vec![0u8; proof.get_num_bytes()];
    proof.write_transcription_bytes_exact(&mut bytes);
    bytes
}

/// Decode a proof, refusing bytes that do not round-trip to themselves. The decoder
/// panics on malformed input, so callers run this where a panic is a rejection.
fn decode_proof(bytes: &[u8]) -> Result<Proof<F>, String> {
    let proof = Proof::<F>::read_transcription_bytes_exact(bytes);
    match proof.get_num_bytes() == bytes.len() {
        true => Ok(proof),
        false => Err("proof bytes do not decode to a proof of their own length".to_string()),
    }
}

/// Write the proof and its public statement under `prefix`.
pub fn write_export(prefix: &str, statement: &Statement, proof: &[u8]) -> Result<(), String> {
    let public = serde_json::to_vec(statement).map_err(|e| format!("public inputs: {e}"))?;
    std::fs::write(format!("{prefix}.proof"), proof).map_err(|e| format!("proof file: {e}"))?;
    std::fs::write(format!("{prefix}.public.json"), public)
        .map_err(|e| format!("public inputs file: {e}"))
}

/// The one verify call, expanded per configuration like `prove_verify!`.
macro_rules! verify_proof {
    ($cfg:ty, $cell:ty, $pp:expr, $proof:expr, $public_trace:expr, $num_vars:expr) => {{
        let proj_ideal = |ideal: &zinc_uair::ideal_collector::IdealOrZero<
            <$crate::runtime::RuntimeUair<$cell> as zinc_uair::Uair>::Ideal,
        >,
                          field_cfg: &<$crate::config::F as crypto_primitives::PrimeField>::Config| {
            ideal.map(|i| zinc_uair::ideal::DegreeOneIdeal::from_with_cfg(i, field_cfg))
        };

        zinc_protocol::ZincPlusPiop::<
            $cfg,
            $crate::runtime::RuntimeUair<$cell>,
            $crate::config::F,
            { $crate::config::D },
        >::verify::<_, { $crate::config::PERFORM_CHECKS }>(
            &$pp,
            $proof,
            &$public_trace,
            $num_vars,
            zinc_protocol::project_scalar_fn,
            proj_ideal,
        )
        .map_err(|e| format!("verifier failed: {e:?}"))
    }};
}
pub(crate) use verify_proof;

/// Verify encoded proof bytes against a statement; the time taken, in milliseconds.
/// Panics on malformed input, so a caller must treat a panic as a rejection.
pub fn verify_statement(statement: Statement, proof: &[u8]) -> Result<f64, String> {
    let Statement { num_vars, spec, public } = statement;
    let proof = decode_proof(proof)?;
    *SPEC.lock().unwrap_or_else(|poisoned| poisoned.into_inner()) = Some(spec);

    let started = Instant::now();
    match public {
        Payload::I64(columns) => {
            let trace = runtime::trace(columns, num_vars);
            let pp = setup_pp(num_vars)?;
            verify_proof!(Cfg, i64, pp, proof, trace, num_vars)
        }
        Payload::Big(columns) => {
            let trace = runtime::limb_trace::<12>(columns, num_vars);
            let pp = setup_big_pp(num_vars)?;
            verify_proof!(BigCfg, BigInt, pp, proof, trace, num_vars)
        }
        Payload::Huge(columns) => {
            let trace = runtime::limb_trace::<110>(columns, num_vars);
            let pp = setup_huge_pp(num_vars)?;
            verify_proof!(HugeCfg, HugeInt, pp, proof, trace, num_vars)
        }
    }?;
    Ok(started.elapsed().as_secs_f64() * 1000.0)
}
