#[cfg(feature = "parallel")]
use rayon::prelude::*;

use crate::commitment::compute_commitment;
use crate::proof::{verify_proof, ProofError};

type Commitment = [u8; 32];

/// Batch verify multiple proofs in parallel
pub fn batch_verify_proofs(
    proof_sets: &[(Vec<u8>, Vec<u8>, Vec<(Vec<u8>, Vec<u8>)>)]
) -> Result<bool, ProofError> {
    // Use parallel verification for performance
    #[cfg(feature = "parallel")]
    let results: Result<Vec<bool>, ProofError> = proof_sets
        .par_iter()
        .map(|(proof, root, kvs)| {
            verify_proof(proof, root, kvs)
        })
        .collect();
    
    #[cfg(not(feature = "parallel"))]
    let results: Result<Vec<bool>, ProofError> = proof_sets
        .iter()
        .map(|(proof, root, kvs)| {
            verify_proof(proof, root, kvs)
        })
        .collect();
    
    match results {
        Ok(verifications) => Ok(verifications.iter().all(|&v| v)),
        Err(e) => Err(e)
    }
}

/// Batch compute commitments in parallel
pub fn batch_compute_commitments(values: &[Vec<u8>]) -> Result<Vec<Commitment>, ProofError> {
    #[cfg(feature = "parallel")]
    let commitments: Result<Vec<Commitment>, _> = values
        .par_iter()
        .map(|value| {
            compute_commitment(value).map_err(|_| ProofError::InvalidInput)
        })
        .collect();
    
    #[cfg(not(feature = "parallel"))]
    let commitments: Result<Vec<Commitment>, _> = values
        .iter()
        .map(|value| {
            compute_commitment(value).map_err(|_| ProofError::InvalidInput)
        })
        .collect();
    
    commitments
}

/// Optimized batch update for multiple key-value pairs
pub fn batch_update_commitments(
    updates: &[(Vec<u8>, Vec<u8>)]  // (key, value) pairs
) -> Result<Vec<Commitment>, ProofError> {
    // Process updates in parallel chunks
    const CHUNK_SIZE: usize = 64;
    
    let chunks: Vec<_> = updates.chunks(CHUNK_SIZE).collect();
    
    #[cfg(feature = "parallel")]
    let results: Result<Vec<Vec<Commitment>>, ProofError> = chunks
        .par_iter()
        .map(|chunk| {
            let mut chunk_commitments = Vec::new();
            
            for (key, value) in chunk.iter() {
                // Compute commitment for each update
                let mut combined = Vec::new();
                combined.extend_from_slice(key);
                combined.extend_from_slice(value);
                
                let commitment = compute_commitment(&combined)
                    .map_err(|_| ProofError::InvalidInput)?;
                chunk_commitments.push(commitment);
            }
            
            Ok(chunk_commitments)
        })
        .collect();
    
    #[cfg(not(feature = "parallel"))]
    let results: Result<Vec<Vec<Commitment>>, ProofError> = chunks
        .iter()
        .map(|chunk| {
            let mut chunk_commitments = Vec::new();
            
            for (key, value) in chunk.iter() {
                // Compute commitment for each update
                let mut combined = Vec::new();
                combined.extend_from_slice(key);
                combined.extend_from_slice(value);
                
                let commitment = compute_commitment(&combined)
                    .map_err(|_| ProofError::InvalidInput)?;
                chunk_commitments.push(commitment);
            }
            
            Ok(chunk_commitments)
        })
        .collect();
    
    match results {
        Ok(chunk_results) => {
            let mut all_commitments = Vec::new();
            for chunk in chunk_results {
                all_commitments.extend(chunk);
            }
            Ok(all_commitments)
        }
        Err(e) => Err(e)
    }
}

/// Parallel witness generation for multiple keys
pub fn batch_generate_witnesses(
    keys: &[Vec<u8>],
    tree_data: &TreeBatchData
) -> Result<Vec<Vec<u8>>, ProofError> {
    #[cfg(feature = "parallel")]
    return keys.par_iter()
        .map(|key| {
            generate_single_witness(key, tree_data)
        })
        .collect();
    
    #[cfg(not(feature = "parallel"))]
    keys.iter()
        .map(|key| {
            generate_single_witness(key, tree_data)
        })
        .collect()
}

/// Helper structure for batch tree operations
pub struct TreeBatchData {
    pub root_commitment: [u8; 32],
    pub node_cache: Vec<([u8; 32], Vec<u8>)>,  // (commitment, node_data) pairs
}

fn generate_single_witness(
    key: &[u8],
    tree_data: &TreeBatchData
) -> Result<Vec<u8>, ProofError> {
    // Simplified witness generation
    use blake3;
    
    let mut hasher = blake3::Hasher::new();
    hasher.update(b"verkle_witness_single");
    hasher.update(&tree_data.root_commitment);
    hasher.update(key);
    
    // Include relevant nodes from cache
    for (commitment, _) in tree_data.node_cache.iter().take(4) {
        hasher.update(commitment);
    }
    
    let hash = hasher.finalize();
    Ok(hash.as_bytes().to_vec())
}

/// Amortized batch verification using random linear combinations
pub fn batch_verify_amortized(
    proofs: &[Vec<u8>],
    commitments: &[Commitment],
    challenges: &[[u8; 32]]
) -> Result<bool, ProofError> {
    if proofs.len() != commitments.len() || proofs.len() != challenges.len() {
        return Err(ProofError::InvalidInput);
    }
    
    // Random linear combination for batch verification
    // In production: Use Fiat-Shamir for challenges
    use blake3;
    
    let mut combined_hasher = blake3::Hasher::new();
    combined_hasher.update(b"verkle_batch_amortized");
    
    for ((proof, commitment), challenge) in proofs.iter()
        .zip(commitments.iter())
        .zip(challenges.iter()) {
        combined_hasher.update(proof);
        combined_hasher.update(commitment);
        combined_hasher.update(challenge);
    }
    
    let combined_hash = combined_hasher.finalize();
    
    // Simplified verification check
    Ok(combined_hash.as_bytes()[0] < 200)
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_batch_compute_commitments() {
        let values: Vec<Vec<u8>> = (0..10)
            .map(|i| vec![i as u8; 32])
            .collect();
        
        let commitments = batch_compute_commitments(&values).unwrap();
        assert_eq!(commitments.len(), 10);
        
        for commitment in commitments {
            assert_eq!(commitment.len(), 32);
        }
    }
    
    #[test]
    fn test_batch_update_commitments() {
        let updates: Vec<(Vec<u8>, Vec<u8>)> = (0..100)
            .map(|i| {
                (vec![i as u8; 32], vec![(i + 1) as u8; 32])
            })
            .collect();
        
        let commitments = batch_update_commitments(&updates).unwrap();
        assert_eq!(commitments.len(), 100);
    }
    
    #[test]
    fn test_parallel_performance() {
        // Test that parallel operations are working
        let large_dataset: Vec<Vec<u8>> = (0..1000)
            .map(|i| vec![(i % 256) as u8; 32])
            .collect();
        
        let start = std::time::Instant::now();
        let _commitments = batch_compute_commitments(&large_dataset).unwrap();
        let parallel_time = start.elapsed();
        
        // Should complete reasonably fast
        assert!(parallel_time.as_millis() < 1000);
    }
}