//! The standalone verifier: a proof file and a public inputs file in, a verdict out.
//!
//! It reads nothing else, so it cannot see the text a proof is about. Exit status 0 is
//! acceptance, 1 is rejection (including any panic while decoding a malformed proof), 2 is
//! a usage or unreadable-file error. One JSON line goes to stdout either way.

use std::panic::catch_unwind;
use std::process::ExitCode;

use zkfol_zinc_plus::wire::{verify_statement, Statement};

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let [proof_path, public_path] = args.as_slice() else {
        eprintln!("usage: zkfol_verify <proof file> <public inputs file>");
        return ExitCode::from(2);
    };

    let (Ok(proof), Ok(public)) = (std::fs::read(proof_path), std::fs::read(public_path)) else {
        println!(r#"{{"verdict":"error","reason":"unreadable input file"}}"#);
        return ExitCode::from(2);
    };

    // A decoder panic is a rejection, not a crash report.
    std::panic::set_hook(Box::new(|_| {}));
    let verdict = catch_unwind(|| {
        let statement: Statement =
            serde_json::from_slice(&public).map_err(|e| format!("public inputs: {e}"))?;
        verify_statement(statement, &proof)
    })
    .unwrap_or_else(|_| Err("malformed proof or public inputs".to_string()));

    match verdict {
        Ok(verify_ms) => {
            println!(r#"{{"verdict":"accept","verify_ms":{verify_ms:.3}}}"#);
            ExitCode::SUCCESS
        }
        Err(reason) => {
            println!("{}", serde_json::json!({ "verdict": "reject", "reason": reason }));
            ExitCode::from(1)
        }
    }
}
