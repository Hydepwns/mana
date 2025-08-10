# Fast Sync Implementation

## Overview

Fast Sync is a synchronization method that allows Ethereum clients to quickly catch up to the network head without executing all transactions from genesis. Instead of processing every transaction, Fast Sync downloads the state at a recent "pivot" block and then downloads recent block headers, bodies, and receipts.

## Benefits

- **Speed**: Reduces sync time from weeks/days to hours
- **Bandwidth**: Downloads only necessary data (state + recent blocks)
- **Storage**: Avoids storing intermediate states
- **Security**: Validates all downloaded data against known block headers

## Architecture

### Components

1. **FastSync** (`apps/ex_wire/lib/ex_wire/sync/fast_sync.ex`)
   - Main coordinator for the fast sync process
   - Manages pivot block selection and sync phases
   - Orchestrates state, header, body, and receipt downloads

2. **StateDownloader** (`apps/ex_wire/lib/ex_wire/sync/state_downloader.ex`)
   - Downloads the complete state trie at the pivot block
   - Implements breadth-first traversal of the state tree
   - Features state healing to recover missing nodes

3. **ReceiptDownloader** (`apps/ex_wire/lib/ex_wire/sync/receipt_downloader.ex`)
   - Downloads transaction receipts for recent blocks
   - Validates receipts against block headers
   - Handles batch downloading with retry logic

## Fast Sync Process

### Phase 1: Pivot Block Selection

1. **Peer Consensus**: Query connected peers for their best block numbers
2. **Pivot Calculation**: Select a block that's ~128 blocks behind the median highest block
3. **Validation**: Request the pivot block header from multiple peers for consensus
4. **Confirmation**: Ensure the pivot block is well-confirmed and stable

```elixir
# Example: If network head is at block 15,000,000
# Pivot block would be around 15,000,000 - 128 = 14,999,872
pivot_number = median_highest - 128
```

### Phase 2: State Download

1. **Root Queuing**: Start with the state root from the pivot block header
2. **Node Discovery**: Parse downloaded nodes to discover child node references
3. **Parallel Download**: Download state nodes in batches using `eth_getNodeData`
4. **Validation**: Verify each node's hash matches its content
5. **Storage**: Store validated nodes in the local state trie

```elixir
# State download process
StateDownloader.start_link(trie, pivot_header.state_root)
# Downloads entire state trie recursively
# Handles ~10M+ nodes for mainnet
```

### Phase 3: Header Download

1. **Range Planning**: Download headers from genesis to pivot block
2. **Batch Requests**: Request headers in batches of 192 using `eth_getBlockHeaders`
3. **Validation**: Validate header chain integrity (parent hashes)
4. **Storage**: Store validated headers in the block tree

### Phase 4: Recent Block Download

1. **Body Download**: Download block bodies for blocks after pivot using `eth_getBlockBodies`
2. **Receipt Download**: Download receipts for recent blocks using `eth_getReceipts`
3. **Validation**: Validate bodies and receipts against their headers
4. **Storage**: Store complete blocks in the blockchain

### Phase 5: State Healing

1. **Missing Node Detection**: Traverse the state trie to find missing references
2. **Targeted Healing**: Download only the missing nodes
3. **Verification**: Ensure the state trie is complete and consistent
4. **Completion**: Mark state sync as complete

## Configuration

### Constants

```elixir
@pivot_distance 128              # Blocks behind head for pivot
@header_batch_size 192           # Headers per request
@body_batch_size 32             # Bodies per request  
@receipt_batch_size 32          # Receipts per request
@state_batch_size 384           # State nodes per request
@max_concurrent_requests 16     # Maximum parallel requests
@request_timeout 10_000         # Request timeout in ms
```

### Tuning Parameters

- **Batch Sizes**: Larger batches reduce request overhead but increase timeout risk
- **Concurrency**: More concurrent requests increase speed but may overwhelm peers
- **Timeout Values**: Longer timeouts reduce failures but slow error recovery
- **Pivot Distance**: Larger distances increase safety but may download more data

## Usage

### Starting Fast Sync

```elixir
# Create chain and trie
chain = Chain.load_chain(:foundation)
{:ok, db} = DB.init(:rocksdb)
trie = Trie.new(db)

# Start fast sync
{:ok, fast_sync_pid} = ExWire.Sync.FastSync.start_link({chain, trie})

# Monitor progress
progress = FastSync.get_progress(fast_sync_pid)
```

### Monitoring Progress

```elixir
# Get current status
status = FastSync.get_status(fast_sync_pid)
#=> %{
#     mode: :fast,
#     pivot_block: 14_999_872,
#     highest_block: 15_000_000,
#     headers_complete: false,
#     bodies_complete: false,
#     receipts_complete: false,
#     state_complete: false
#   }

# Get detailed progress
progress = FastSync.get_progress(fast_sync_pid)
#=> %{
#     headers: %{downloaded: 125000, progress: 85.2},
#     bodies: %{downloaded: 950},
#     receipts: %{downloaded: 950}, 
#     state: %{nodes_downloaded: 8_500_000, queue_size: 1_200_000},
#     elapsed_time: 7200  # 2 hours
#   }
```

### Switching Sync Modes

```elixir
# Switch to full sync once fast sync completes
FastSync.switch_mode(fast_sync_pid, :full)

# Or switch to snap sync for even faster syncing
FastSync.switch_mode(fast_sync_pid, :snap)
```

## Performance Characteristics

### Expected Performance

- **Mainnet Sync Time**: 2-8 hours (depending on hardware and network)
- **State Download**: ~8-12 GB of state data
- **Header Download**: ~200 MB of header data  
- **Recent Blocks**: ~500 MB of bodies + receipts

### Bottlenecks

1. **Network I/O**: Limited by peer connection speed and availability
2. **Disk I/O**: State trie writes can be disk-intensive
3. **CPU**: RLP decoding and hash verification
4. **Memory**: Node queues and request tracking

### Optimizations

1. **Parallel Downloads**: Multiple concurrent requests across different peers
2. **Intelligent Batching**: Optimal batch sizes for different data types
3. **Request Pipelining**: Queue new requests before previous ones complete
4. **Peer Selection**: Prefer faster, more reliable peers
5. **State Healing**: Minimize redundant downloads

## Error Handling

### Peer Failures

- **Timeout Handling**: Retry failed requests with different peers
- **Peer Rotation**: Switch peers for persistent failures
- **Backoff Strategy**: Exponential backoff for repeated failures

### Data Validation Failures

- **Hash Mismatches**: Re-request corrupted data
- **Chain Validation**: Verify header chain integrity
- **State Consistency**: Heal missing state nodes

### Network Partitions

- **Pivot Re-selection**: Choose new pivot if current one becomes stale
- **Graceful Degradation**: Fall back to full sync if fast sync fails
- **Resume Capability**: Continue from last good state after restart

## Integration

### With Existing Sync

Fast Sync integrates with the existing sync system in `ExWire.Sync`:

```elixir
# In ExWire.Sync
case sync_mode do
  :fast -> 
    FastSync.start_link({chain, trie})
  :full -> 
    # Existing full sync logic
  :snap ->
    # Future snap sync implementation
end
```

### With P2P Layer

Fast Sync uses the existing P2P infrastructure:

- **Peer Discovery**: Uses `ExWire.PeerSupervisor` for peer management
- **Packet Handling**: Integrates with `ExWire.Packet` system
- **Protocol Support**: Works with eth/66 and eth/67 protocols

### With Storage Layer

- **State Storage**: Uses `MerklePatriciaTree` for state management
- **Block Storage**: Integrates with `Blockchain.Blocktree`
- **Database Backend**: Works with ETS, RocksDB, and AntidoteDB

## Testing

### Unit Tests

```bash
# Run fast sync tests
mix test apps/ex_wire/test/ex_wire/sync/

# Run specific component tests
mix test apps/ex_wire/test/ex_wire/sync/state_downloader_test.exs
mix test apps/ex_wire/test/ex_wire/sync/receipt_downloader_test.exs
```

### Integration Tests

```elixir
# Test with mainnet data
{:ok, pid} = FastSync.start_link({Chain.load_chain(:foundation), trie})

# Verify state consistency
assert StateDownloader.verify_state_consistency(state_root)

# Check block validation
assert ReceiptDownloader.validate_all_receipts(receipts, headers)
```

### Performance Testing

```bash
# Benchmark sync performance
mix run scripts/benchmark_fast_sync.exs

# Profile memory usage
mix profile.fprof --callers scripts/fast_sync_profile.exs
```

## Future Improvements

### Snap Sync Integration

- **Snap Protocol**: Implement eth/snap protocol for even faster syncing
- **Account Ranges**: Download state in account ranges rather than nodes
- **Storage Ranges**: Parallel storage slot downloading
- **Code Downloads**: Separate contract code downloading

### Advanced Optimizations

- **Bloom Filters**: Skip unnecessary node downloads
- **Compression**: Compress state data during transfer
- **Delta Sync**: Download only state changes since last sync
- **Checkpoint Sync**: Start from trusted checkpoints

### Reliability Improvements

- **Better Healing**: More intelligent missing node detection
- **Peer Scoring**: Rank peers by reliability and speed
- **Adaptive Timeouts**: Adjust timeouts based on peer performance
- **Resume Support**: Save and restore sync state across restarts

## Troubleshooting

### Common Issues

1. **Slow State Download**
   - Check peer connectivity and count
   - Verify disk I/O performance
   - Increase concurrent request limit

2. **Pivot Block Rejections**  
   - Ensure sufficient connected peers (>3)
   - Check for network partitions
   - Verify peer consensus on chain head

3. **State Healing Failures**
   - Check for corrupted state nodes
   - Verify trie database integrity
   - Re-run healing with forced mode

### Debug Commands

```bash
# Check fast sync status
iex> FastSync.get_status(pid)

# Force state healing
iex> StateDownloader.force_heal(state_downloader_pid)

# Get detailed statistics
iex> FastSync.get_progress(pid)
```

### Monitoring

Fast Sync provides detailed logging and progress reporting:

```elixir
# Progress reports every 10 seconds
2023-08-09 16:54:37 [info] Fast Sync Progress:
  Headers:  125,000 (85.2%)
  Bodies:   950
  Receipts: 950  
  State:    8,500,000 nodes (1,200,000 queued)
  Time:     2h 15m 30s
```

## Conclusion

Fast Sync provides a production-ready implementation for quickly synchronizing with the Ethereum network. It offers significant performance improvements over full sync while maintaining security through comprehensive validation of all downloaded data.

The modular architecture allows for easy extension and optimization, with clear separation of concerns between state downloading, receipt validation, and sync coordination.