# Ethereum 2.0 Implementation Plan for Mana-Ethereum

## Overview
This document outlines the implementation of Ethereum 2.0 (Consensus Layer) features in Mana-Ethereum, transforming it into a full Ethereum node capable of participating in Proof-of-Stake consensus.

## Architecture Overview

### Core Components

1. **Beacon Chain Client**
   - Manages the Proof-of-Stake blockchain
   - Processes blocks and attestations
   - Maintains validator registry
   - Handles fork choice (LMD-GHOST + Casper FFG)

2. **Validator Client**
   - Proposes blocks when selected
   - Creates and broadcasts attestations
   - Participates in sync committees
   - Manages validator keys and duties

3. **Execution Engine Integration**
   - Engine API for consensus-execution communication
   - Payload building and validation
   - State transition verification

4. **Networking Layer**
   - LibP2P for consensus layer networking
   - Gossipsub for message propagation
   - Discovery v5 for peer discovery
   - Request/Response protocols

## Implementation Phases

### Phase 1: Core Consensus (Week 1)
- [ ] Beacon state management
- [ ] Fork choice implementation (LMD-GHOST)
- [ ] Finality gadget (Casper FFG)
- [ ] Epoch and slot processing
- [ ] Validator registry management

### Phase 2: Validator Operations (Week 2)
- [ ] Block proposal logic
- [ ] Attestation creation and aggregation
- [ ] Sync committee participation
- [ ] Validator duty scheduling
- [ ] BLS signature verification

### Phase 3: Networking & Sync (Week 3)
- [ ] LibP2P integration
- [ ] Gossipsub topics and message handling
- [ ] Initial sync (checkpoint sync)
- [ ] Optimistic sync
- [ ] Peer management

### Phase 4: Advanced Features (Week 4)
- [ ] MEV-Boost integration
- [ ] Distributed validator technology (DVT)
- [ ] Light client support
- [ ] Slashing protection database
- [ ] Withdrawal processing

## Key Specifications to Implement

### Consensus Specifications
1. **Phase 0** - The Beacon Chain
   - SLOTS_PER_EPOCH = 32
   - SECONDS_PER_SLOT = 12
   - MIN_VALIDATOR_WITHDRAWABILITY_DELAY = 256 epochs
   - SHARD_COMMITTEE_PERIOD = 256 epochs

2. **Altair** - Light client support
   - Sync committees (512 validators)
   - Improved rewards and penalties
   - Light client data in blocks

3. **Bellatrix** - The Merge
   - Execution payload in beacon blocks
   - Engine API communication
   - Terminal total difficulty handling

4. **Capella** - Withdrawals
   - Validator withdrawals (EIP-4895)
   - BLS to execution address changes
   - Historical roots accumulator

5. **Deneb** - Proto-Danksharding
   - Blob transactions (EIP-4844)
   - KZG commitments
   - Blob sidecar handling

## Data Structures

### Beacon State
```elixir
defmodule BeaconState do
  defstruct [
    # Versioning
    :genesis_time,
    :genesis_validators_root,
    :slot,
    :fork,
    
    # History
    :latest_block_header,
    :block_roots,
    :state_roots,
    :historical_roots,
    
    # Eth1
    :eth1_data,
    :eth1_data_votes,
    :eth1_deposit_index,
    
    # Registry
    :validators,
    :balances,
    
    # Randomness
    :randao_mixes,
    
    # Slashings
    :slashings,
    
    # Participation
    :previous_epoch_participation,
    :current_epoch_participation,
    
    # Finality
    :justification_bits,
    :previous_justified_checkpoint,
    :current_justified_checkpoint,
    :finalized_checkpoint,
    
    # Sync
    :current_sync_committee,
    :next_sync_committee,
    
    # Execution
    :latest_execution_payload_header,
    
    # Withdrawals
    :next_withdrawal_index,
    :next_withdrawal_validator_index
  ]
end
```

### Validator
```elixir
defmodule Validator do
  defstruct [
    :pubkey,
    :withdrawal_credentials,
    :effective_balance,
    :slashed,
    :activation_eligibility_epoch,
    :activation_epoch,
    :exit_epoch,
    :withdrawable_epoch
  ]
end
```

### BeaconBlock
```elixir
defmodule BeaconBlock do
  defstruct [
    :slot,
    :proposer_index,
    :parent_root,
    :state_root,
    :body
  ]
end

defmodule BeaconBlockBody do
  defstruct [
    :randao_reveal,
    :eth1_data,
    :graffiti,
    :proposer_slashings,
    :attester_slashings,
    :attestations,
    :deposits,
    :voluntary_exits,
    :sync_aggregate,
    :execution_payload,
    :bls_to_execution_changes,
    :blob_kzg_commitments
  ]
end
```

## Consensus Algorithms

### Fork Choice (LMD-GHOST)
- Latest Message Driven GHOST
- Greedily selects the branch with most attestation weight
- Considers only the latest attestation from each validator

### Finality (Casper FFG)
- Checkpoints every epoch (32 slots)
- Supermajority links (2/3+ stake)
- Justification and finalization rules

### Proposer Selection
- RANDAO-based randomness
- Proposer boost for fork choice
- Committee shuffling algorithm

## Networking Protocols

### LibP2P Topics
- `/eth2/beacon_block/ssz_snappy`
- `/eth2/beacon_attestation_{subnet_id}/ssz_snappy`
- `/eth2/beacon_aggregate_and_proof/ssz_snappy`
- `/eth2/voluntary_exit/ssz_snappy`
- `/eth2/proposer_slashing/ssz_snappy`
- `/eth2/attester_slashing/ssz_snappy`
- `/eth2/sync_committee_{subnet_id}/ssz_snappy`

### Request/Response Protocols
- Status exchange
- BeaconBlocksByRange
- BeaconBlocksByRoot
- BlobSidecarsByRange
- BlobSidecarsByRoot

## Validator Duties

### Per-Epoch Duties
1. Update duties for next epoch
2. Prepare sync committee if selected
3. Check for withdrawals

### Per-Slot Duties
1. **Attestation** (every slot)
   - Wait for 1/3 into slot
   - Create and sign attestation
   - Broadcast to subnet

2. **Block Proposal** (when selected)
   - Build execution payload via Engine API
   - Create beacon block body
   - Sign and broadcast block

3. **Aggregation** (when selected)
   - Aggregate attestations from subnet
   - Create aggregate and proof
   - Broadcast to global topic

4. **Sync Committee** (when selected)
   - Sign block root
   - Broadcast to sync subnet

## Engine API Integration

### Methods to Implement
- `engine_newPayloadV3` - Validate execution payload
- `engine_forkchoiceUpdatedV3` - Update fork choice state
- `engine_getPayloadV3` - Build execution payload
- `engine_exchangeCapabilities` - Capability negotiation

## Security Considerations

### Slashing Protection
- Double vote detection
- Surround vote detection
- Slashing database with interchange format

### Key Management
- BLS12-381 key generation
- HD wallet derivation (EIP-2333)
- Remote signer support
- Key splitting for DVT

### DOS Protection
- Rate limiting for P2P messages
- Peer scoring and banning
- Resource limits for state transitions

## Performance Targets

- Block processing: < 1 second
- Attestation processing: < 100ms
- State transition: < 4 seconds
- Fork choice update: < 500ms
- Sync speed: > 1000 blocks/second

## Testing Strategy

### Consensus Tests
- Official consensus spec tests
- Fork choice tests
- State transition tests
- SSZ serialization tests

### Integration Tests
- Mainnet shadow fork testing
- Multi-client testing (Hive)
- MEV-Boost integration tests

### Performance Tests
- Large validator set (1M validators)
- High attestation volume
- Reorg resistance
- Sync performance

## Migration Path

1. **Dual-Stack Operation**
   - Run alongside existing execution client
   - Gradual migration of validators

2. **Checkpoint Sync**
   - Start from recent finalized checkpoint
   - Avoid syncing from genesis

3. **Validator Migration**
   - Import existing validator keys
   - Preserve slashing protection history

## Success Metrics

- [ ] Pass all consensus spec tests
- [ ] Successfully validate on mainnet
- [ ] Achieve 99.9% attestation effectiveness
- [ ] Maintain < 5% missed blocks
- [ ] Support 10,000+ validators per node

## Next Steps

1. Set up development environment for consensus layer
2. Implement core beacon chain state management
3. Build fork choice and finality gadget
4. Integrate with existing execution layer
5. Implement validator client functionality
6. Add networking and peer discovery
7. Comprehensive testing and optimization

---

*This implementation will make Mana-Ethereum the first Elixir-based Ethereum consensus client, leveraging OTP's Actor model for superior concurrency and fault tolerance in validator operations.*