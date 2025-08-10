# JSON-RPC API Implementation

## Overview

This document describes the JSON-RPC 2.0 API implementation for Mana-Ethereum, providing compatibility with standard Ethereum dApps and tools.

## Implementation Status

### ✅ Completed Methods

#### Core Methods
- **eth_gasPrice**: Returns current gas price (default: 20 Gwei)
- **eth_call**: Executes a message call without creating a transaction
- **eth_getLogs**: Returns logs matching filter criteria
- **eth_estimateGas**: Estimates gas for a transaction (existing)

#### Filter Methods
- **eth_newFilter**: Creates a new log filter
- **eth_newBlockFilter**: Creates a filter for new blocks
- **eth_newPendingTransactionFilter**: Creates a filter for pending transactions
- **eth_uninstallFilter**: Removes a filter
- **eth_getFilterChanges**: Returns changes since last poll
- **eth_getFilterLogs**: Returns all logs for a filter

#### Existing Methods (Already Implemented)
- **eth_getBalance**: Returns account balance
- **eth_getTransactionCount**: Returns transaction count (nonce)
- **eth_getCode**: Returns contract code
- **eth_getStorageAt**: Returns storage value at position
- **eth_blockNumber**: Returns current block number
- **eth_getBlockByHash**: Returns block by hash
- **eth_getBlockByNumber**: Returns block by number
- **eth_getTransactionByHash**: Returns transaction by hash
- **eth_getTransactionReceipt**: Returns transaction receipt

#### WebSocket Subscription Methods
- **eth_subscribe**: Creates a subscription for specific events
- **eth_unsubscribe**: Cancels an existing subscription

#### Transaction Methods
- **eth_sendRawTransaction**: Send pre-signed transaction to pool
- **eth_pendingTransactions**: Get all pending transactions
- **eth_sendTransaction**: Send transaction (requires wallet - not fully implemented)

## Architecture

### Components

1. **SpecHandler** (`lib/jsonrpc2/spec_handler.ex`)
   - Main request router
   - Implements JSON-RPC method dispatch
   - Integrates with Bridge.Sync for blockchain data
   - Supports WebSocket context for subscriptions

2. **SubscriptionManager** (`lib/jsonrpc2/subscription_manager.ex`)
   - Manages WebSocket subscriptions
   - Pushes real-time notifications to clients
   - Handles automatic cleanup on disconnect
   - Supports newHeads, logs, newPendingTransactions, and syncing

3. **EthCall** (`lib/jsonrpc2/spec_handler/eth_call.ex`)
   - Executes contract calls without creating transactions
   - Uses MessageCall for EVM execution
   - Returns call results or errors

4. **LogsFilter** (`lib/jsonrpc2/spec_handler/logs_filter.ex`)
   - Filters blockchain logs based on criteria
   - Supports address, topics, and block range filtering
   - Handles both single block and range queries

5. **FilterManager** (`lib/jsonrpc2/filter_manager.ex`)
   - GenServer managing filter state
   - Handles filter lifecycle (create, poll, delete)
   - Automatic cleanup of expired filters (5 minutes)
   - Supports log, block, and pending transaction filters

6. **TransactionPool** (`apps/blockchain/lib/blockchain/transaction_pool.ex`)
   - Manages pending transactions (mempool)
   - Transaction validation and gas price sorting
   - Automatic cleanup of old transactions
   - Integrates with SubscriptionManager for notifications

## Usage Examples

### eth_call

```javascript
// Call a contract method
const result = await web3.eth.call({
  from: '0x0000000000000000000000000000000000000000',
  to: '0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb3',
  data: '0x70a08231000000000000000000000000...',  // balanceOf(address)
  gas: '0x5208'
}, 'latest');
```

### eth_getLogs

```javascript
// Get logs for a specific address and topic
const logs = await web3.eth.getLogs({
  fromBlock: '0x0',
  toBlock: 'latest',
  address: '0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb3',
  topics: ['0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef'] // Transfer event
});
```

### Filter Management

```javascript
// Create a new filter
const filterId = await web3.eth.newFilter({
  fromBlock: 'latest',
  address: '0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb3'
});

// Get changes since last poll
const changes = await web3.eth.getFilterChanges(filterId);

// Remove filter when done
await web3.eth.uninstallFilter(filterId);
```

### WebSocket Subscriptions

Real-time event streaming via WebSocket connections:

```javascript
// Connect via WebSocket
const Web3 = require('web3');
const web3 = new Web3('ws://localhost:8546');

// Subscribe to new block headers
const subscription = await web3.eth.subscribe('newHeads');
subscription.on('data', (blockHeader) => {
  console.log('New block:', blockHeader);
});

// Subscribe to logs with filter
const logsSubscription = await web3.eth.subscribe('logs', {
  address: '0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb3',
  topics: ['0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef']
});

// Subscribe to pending transactions
const pendingTxSubscription = await web3.eth.subscribe('newPendingTransactions');

// Subscribe to sync status changes
const syncSubscription = await web3.eth.subscribe('syncing');

// Unsubscribe
await subscription.unsubscribe();
```

**Supported Subscription Types:**
- `newHeads`: New block headers
- `logs`: Event logs matching filter criteria
- `newPendingTransactions`: New pending transactions
- `syncing`: Sync status changes

### Transaction Pool

Sending and managing transactions:

```javascript
// Send a pre-signed transaction
const signedTx = '0xf86c0185...' // RLP-encoded signed transaction
const txHash = await web3.eth.sendRawTransaction(signedTx);

// Get pending transactions
const pendingTxs = await web3.eth.call({
  method: 'eth_pendingTransactions',
  params: []
});

// Get transaction count including pending
const nonce = await web3.eth.getTransactionCount(address, 'pending');
```

## Configuration

The JSON-RPC server can be configured in `config/config.exs`:

```elixir
config :jsonrpc2,
  ipc: [enabled: true, path: "/tmp/mana.ipc"],
  http: [enabled: true, port: 8545],
  ws: [enabled: true, port: 8546]
```

## Testing

Run the JSON-RPC tests:

```bash
mix test apps/jsonrpc2/test/jsonrpc2/rpc_methods_test.exs
```

## Performance Considerations

1. **Filter Management**: Filters are automatically cleaned up after 5 minutes of inactivity
2. **Log Filtering**: Large block ranges may be slow; consider pagination
3. **eth_call**: Complex contract calls may require gas limit adjustment

## Security Considerations

1. **Gas Limits**: Default gas limit for eth_call is 3,000,000
2. **Input Validation**: All inputs are validated before processing
3. **Filter Expiry**: Prevents memory exhaustion from abandoned filters

## Future Improvements

1. **Transaction Pool**: Support for eth_sendTransaction and pending transactions
2. **Gas Price Oracle**: Dynamic gas price based on network conditions
3. **Performance Optimization**: Caching for frequently accessed data
4. **Enhanced Logging**: Better error messages and debugging information
5. **Rate Limiting**: Per-connection rate limiting for public endpoints

## Compatibility

The implementation follows the Ethereum JSON-RPC specification and is compatible with:
- Web3.js
- Ethers.js
- MetaMask
- Truffle
- Hardhat
- Other standard Ethereum tools

## Known Limitations

1. **No Wallet Support**: eth_sendTransaction requires wallet functionality (private key management)
2. **No Mining Methods**: Mining-related methods return not_supported
3. **Basic Gas Price**: Uses fixed gas price instead of dynamic calculation
4. **Simplified Transaction Validation**: Full signature recovery not implemented

## Contributing

When adding new RPC methods:

1. Update `spec_handler.ex` with the method dispatch
2. Create handler module in `spec_handler/` if complex logic needed
3. Add tests in `test/jsonrpc2/`
4. Update this documentation
5. Ensure compatibility with Ethereum specification

## References

- [Ethereum JSON-RPC Specification](https://ethereum.org/en/developers/docs/apis/json-rpc/)
- [EIP-1474: Remote procedure call specification](https://eips.ethereum.org/EIPS/eip-1474)
- [Web3.js Documentation](https://web3js.readthedocs.io/)