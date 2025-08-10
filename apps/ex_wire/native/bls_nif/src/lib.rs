use blst::{
    min_pk::{AggregatePublicKey, AggregateSignature, PublicKey, SecretKey, Signature},
    BLST_ERROR,
};
use rustler::{Binary, Env, Error as RustlerError, NifResult, OwnedBinary};
use rand::Rng;

mod atoms {
    rustler::atoms! {
        ok,
        error,
        invalid_key,
        invalid_signature,
        verification_failed,
    }
}

#[rustler::nif]
fn generate_keypair(env: Env) -> NifResult<(Binary, Binary)> {
    let mut rng = rand::thread_rng();
    let mut ikm = [0u8; 32];
    rng.fill(&mut ikm);
    
    let sk = SecretKey::key_gen(&ikm, &[])
        .map_err(|_| RustlerError::Term(Box::new(atoms::invalid_key())))?;
    let pk = sk.sk_to_pk();
    
    let sk_bytes = sk.to_bytes();
    let pk_bytes = pk.to_bytes();
    
    let mut sk_binary = OwnedBinary::new(32).unwrap();
    sk_binary.as_mut_slice().copy_from_slice(&sk_bytes);
    
    let mut pk_binary = OwnedBinary::new(48).unwrap();
    pk_binary.as_mut_slice().copy_from_slice(&pk_bytes);
    
    Ok((sk_binary.release(env), pk_binary.release(env)))
}

#[rustler::nif]
fn privkey_to_pubkey<'a>(env: Env<'a>, privkey: Binary<'a>) -> NifResult<Binary<'a>> {
    let sk = SecretKey::from_bytes(&privkey)
        .map_err(|_| RustlerError::Term(Box::new(atoms::invalid_key())))?;
    let pk = sk.sk_to_pk();
    let pk_bytes = pk.to_bytes();
    
    let mut binary = OwnedBinary::new(48).unwrap();
    binary.as_mut_slice().copy_from_slice(&pk_bytes);
    Ok(binary.release(env))
}

#[rustler::nif]
fn sign<'a>(env: Env<'a>, privkey: Binary<'a>, message: Binary<'a>) -> NifResult<Binary<'a>> {
    let sk = SecretKey::from_bytes(&privkey)
        .map_err(|_| RustlerError::Term(Box::new(atoms::invalid_key())))?;
    
    let sig = sk.sign(&message, b"BLS_SIG_BLS12381G2_XMD:SHA-256_SSWU_RO_POP_", &[]);
    let sig_bytes = sig.to_bytes();
    
    let mut binary = OwnedBinary::new(96).unwrap();
    binary.as_mut_slice().copy_from_slice(&sig_bytes);
    Ok(binary.release(env))
}

#[rustler::nif]
fn verify<'a>(pubkey: Binary<'a>, message: Binary<'a>, signature: Binary<'a>) -> NifResult<bool> {
    let pk = PublicKey::from_bytes(&pubkey)
        .map_err(|_| RustlerError::Term(Box::new(atoms::invalid_key())))?;
    
    let sig = Signature::from_bytes(&signature)
        .map_err(|_| RustlerError::Term(Box::new(atoms::invalid_signature())))?;
    
    let result = sig.verify(
        true,  // Verify signature in group
        &message,
        b"BLS_SIG_BLS12381G2_XMD:SHA-256_SSWU_RO_POP_",
        &[],
        &pk,
        true,  // Verify public key in group
    );
    
    Ok(result == BLST_ERROR::BLST_SUCCESS)
}

#[rustler::nif]
fn aggregate_signatures<'a>(env: Env<'a>, signatures: Vec<Binary<'a>>) -> NifResult<Binary<'a>> {
    if signatures.is_empty() {
        return Err(RustlerError::Term(Box::new(atoms::invalid_signature())));
    }
    
    // Parse all signatures first
    let sigs: Result<Vec<Signature>, _> = signatures
        .iter()
        .map(|sig_bytes| Signature::from_bytes(sig_bytes))
        .collect();
    
    let sigs = sigs.map_err(|_| RustlerError::Term(Box::new(atoms::invalid_signature())))?;
    
    // Create aggregate signature starting with first signature, then add rest
    let mut agg_sig = AggregateSignature::from_signature(&sigs[0]);
    for sig in &sigs[1..] {
        match agg_sig.add_signature(sig, true) {
            Ok(()) => {},
            Err(_) => return Err(RustlerError::Term(Box::new(atoms::invalid_signature()))),
        }
    }
    
    let final_sig = agg_sig.to_signature();
    
    let agg_bytes = final_sig.to_bytes();
    let mut binary = OwnedBinary::new(96).unwrap();
    binary.as_mut_slice().copy_from_slice(&agg_bytes);
    Ok(binary.release(env))
}

#[rustler::nif]
fn aggregate_pubkeys<'a>(env: Env<'a>, pubkeys: Vec<Binary<'a>>) -> NifResult<Binary<'a>> {
    if pubkeys.is_empty() {
        return Err(RustlerError::Term(Box::new(atoms::invalid_key())));
    }
    
    // Parse all public keys first
    let pks: Result<Vec<PublicKey>, _> = pubkeys
        .iter()
        .map(|pk_bytes| PublicKey::from_bytes(pk_bytes))
        .collect();
    
    let pks = pks.map_err(|_| RustlerError::Term(Box::new(atoms::invalid_key())))?;
    
    // Create aggregate public key starting with first key, then add rest  
    let mut agg_pk = AggregatePublicKey::from_public_key(&pks[0]);
    for pk in &pks[1..] {
        match agg_pk.add_public_key(pk, true) {
            Ok(()) => {},
            Err(_) => return Err(RustlerError::Term(Box::new(atoms::invalid_key()))),
        }
    }
    
    let final_pk = agg_pk.to_public_key();
    
    let agg_bytes = final_pk.to_bytes();
    let mut binary = OwnedBinary::new(48).unwrap();
    binary.as_mut_slice().copy_from_slice(&agg_bytes);
    Ok(binary.release(env))
}

#[rustler::nif]
fn fast_aggregate_verify<'a>(
    pubkeys: Vec<Binary<'a>>,
    message: Binary<'a>,
    signature: Binary<'a>,
) -> NifResult<bool> {
    if pubkeys.is_empty() {
        return Ok(false);
    }
    
    let sig = Signature::from_bytes(&signature)
        .map_err(|_| RustlerError::Term(Box::new(atoms::invalid_signature())))?;
    
    // Parse all public keys
    let pks: Result<Vec<PublicKey>, _> = pubkeys
        .iter()
        .map(|pk_bytes| PublicKey::from_bytes(pk_bytes))
        .collect();
    
    let pks = pks.map_err(|_| RustlerError::Term(Box::new(atoms::invalid_key())))?;
    
    // Aggregate public keys starting with first key, then add rest
    let mut agg_pk = AggregatePublicKey::from_public_key(&pks[0]);
    for pk in &pks[1..] {
        match agg_pk.add_public_key(pk, true) {
            Ok(()) => {},
            Err(_) => return Err(RustlerError::Term(Box::new(atoms::invalid_key()))),
        }
    }
    
    let final_pk = agg_pk.to_public_key();
    
    // Verify against aggregated public key
    let result = sig.verify(
        true,
        &message,
        b"BLS_SIG_BLS12381G2_XMD:SHA-256_SSWU_RO_POP_",
        &[],
        &final_pk,
        true,
    );
    
    Ok(result == BLST_ERROR::BLST_SUCCESS)
}

#[rustler::nif]
fn aggregate_verify<'a>(
    pubkey_message_pairs: Vec<(Binary<'a>, Binary<'a>)>,
    signature: Binary<'a>,
) -> NifResult<bool> {
    if pubkey_message_pairs.is_empty() {
        return Ok(false);
    }
    
    let sig = Signature::from_bytes(&signature)
        .map_err(|_| RustlerError::Term(Box::new(atoms::invalid_signature())))?;
    
    let pks: Result<Vec<PublicKey>, _> = pubkey_message_pairs
        .iter()
        .map(|(pk_bytes, _)| PublicKey::from_bytes(pk_bytes))
        .collect();
    
    let pks = pks.map_err(|_| RustlerError::Term(Box::new(atoms::invalid_key())))?;
    
    let msgs: Vec<&[u8]> = pubkey_message_pairs
        .iter()
        .map(|(_, msg)| msg.as_slice())
        .collect();
    
    let pk_refs: Vec<&PublicKey> = pks.iter().collect();
    
    let dst = b"BLS_SIG_BLS12381G2_XMD:SHA-256_SSWU_RO_POP_";
    let result = sig.aggregate_verify(
        true,
        &msgs,
        dst,
        &pk_refs,
        true,
    );
    
    Ok(result == BLST_ERROR::BLST_SUCCESS)
}

rustler::init!(
    "Elixir.ExWire.Crypto.BLS",
    [
        generate_keypair,
        privkey_to_pubkey,
        sign,
        verify,
        aggregate_signatures,
        aggregate_pubkeys,
        fast_aggregate_verify,
        aggregate_verify,
    ]
);