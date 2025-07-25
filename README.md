# Mana-Ethereum

[![GitHub Actions](https://github.com/mana-ethereum/mana/workflows/CI/badge.svg)](https://github.com/mana-ethereum/mana/actions) [![CodeQL](https://github.com/mana-ethereum/mana/workflows/CodeQL/badge.svg)](https://github.com/mana-ethereum/mana/security/code-scanning)

Mana-Ethereum is an open-source Ethereum blockchain client built using [Elixir]. Elixir runs on the Erlang Virtual Machine, which is used for distributed systems and offers massive scalability and high visibility. These properties make Elixir a perfect candidate for blockchain network development.

In the current Ethereum ecosystem, a majority of active nodes on the network are Geth or Parity nodes. Mana-Ethereum provides an additional open-source alternative. Our aim is to create an open, well-documented implementation that closely matches the protocols described in the [Ethereum yellow paper].

**🚀 Now featuring modern Elixir 1.18 and AntidoteDB distributed storage!**

Mana-Ethereum is currently in active development. See the [Project Status] and [Project FAQs] for more information.

[Elixir]: https://elixir-lang.org/
[Ethereum yellow paper]: https://ethereum.github.io/yellowpaper/paper.pdf
[Project Status]: #project-status
[Project FAQs]: https://github.com/mana-ethereum/mana/wiki/FAQ

## 🆕 What's New

### Modern Technology Stack

- **Elixir 1.18** - Latest stable version with modern features
- **Erlang 27.2** - Latest OTP release for maximum performance
- **AntidoteDB** - Distributed transactional database for blockchain storage
- **Modern CI/CD** - GitHub Actions with security scanning and automated testing

### Distributed Storage Innovation

Mana-Ethereum is the **first Ethereum client** to integrate AntidoteDB, providing:

- **Distributed Transactions** - Full ACID compliance for blockchain operations
- **CRDT Support** - Concurrent updates with automatic conflict resolution
- **High Availability** - Fault-tolerant distributed storage
- **Blockchain Optimized** - Perfect for Ethereum state management

### Enhanced Development Experience

- **NixOS Development Environment** - Reproducible builds across all platforms
- **Automated Security Scanning** - CodeQL integration for vulnerability detection
- **Dependency Management** - Automated updates with Dependabot
- **Quality Assurance** - Credo, Dialyzer, and comprehensive testing

# Dependencies

- **Elixir ~> 1.18** (upgraded from 1.8)
- **Erlang ~> 27.2** (upgraded from 21.1)
- **AntidoteDB** - Distributed transactional database

# Installation

## Quick Start with NixOS (Recommended)

If you're using NixOS or have Nix installed:

```bash
# Clone the repository
git clone --recurse-submodules https://github.com/mana-ethereum/mana.git
cd mana

# Enter the development environment
nix-shell

# Install dependencies and compile
mix deps.get
mix compile
```

## Traditional Installation

- Clone repo with submodules (to access the [Ethereum common tests])

   ```
   git clone --recurse-submodules https://github.com/mana-ethereum/mana.git
   ```

- Go to the mana subdirectory `cd mana`

- Ensure you have Elixir 1.18+ and Erlang 27.2+ installed

- Run `mix deps.get && mix compile`

# Running a node

Peer-to-peer communication is currently in development. A [command-line interface] is available for chain syncing.

## Sync From RPC Client

To sync a chain from an RPC Client (e.g. Infura) or a local client,
run the following command:

```bash
mix sync --chain ropsten
```

You can sign up for an [Infura API key here]. This will ensure your requests are not throttled.

```bash
mix sync --chain ropsten --provider-url https://ropsten.infura.io/v3/<api_key>
```

Alternatively, you can sync via IPC to a local node (like Parity or Geth running locally):

```bash
mix sync --chain ropsten --provider-url ipc://~/Library/Application\ Support/io.parity.ethereum/jsonrpc.ipc
```

Once syncing begins you will see a timestamp and a running list of verified blocks.

[command-line interface]: https://github.com/mana-ethereum/mana/tree/master/apps/cli
[Infura API key here]: https://infura.io/register

### Releases

To build a release, run: `mix release`, which will build a release in `_build/dev/rel/mana/bin/mana`.

Then you can run:

`_build/dev/rel/mana/bin/mana run --no-discovery --bootnodes enode://...`

which will start a DevP2P sync with a local peer.

### Known Sync Issues

_Updated Dec-5-2018_

- We've restarted mainnet syncing and are at block ~ [2,470,630]. We are currently investigating performance and storage issues [#622], [#623], and [#624].
- Ropsten sync is in progress as we've reached the Constantinople fork. Current block is ~ [4,253,000] - Oct-18-2018

[2,470,630]: https://etherscan.io/block/2470630
[4,253,000]: https://ropsten.etherscan.io/block/4253000
[#622]: https://github.com/mana-ethereum/mana/issues/622
[#623]: https://github.com/mana-ethereum/mana/issues/623
[#624]: https://github.com/mana-ethereum/mana/issues/624

### Helpful debugging tools

When debugging block verification failures, we have found [etherscan] tools extrememly helpful. Take block `177610` for example:

We can look at the [block information], and dive into the [transaction
information]. From that page, the "Tools & Utilities" dropdown provides useful debugging tools. Two of the most valuable are [Geth DebugTrace] and
[Remix Debugger].

- `Geth DebugTrace` allows us to compare each operation and its gas consumption
  against our implementation.

- `Remix Debugger` allows us to compare the stack against our implementation's
  stack for each cycle of the virtual machine.

NOTE: for the `Remix Debugger`, you may want to add the block number at the top
before pressing the play button.

To log the operation, gas consumption, and stack in our application, please see
the EVM README [example setup].

[etherscan]: https://etherscan.io/
[block information]: https://etherscan.io/block/177610
[transaction information]: https://etherscan.io/tx/0x7f79a541615694029d845e31f2f362484679c1b9a3fd8588822a33a0e13383f4
[geth debugtrace]: https://etherscan.io/vmtrace?txhash=0x7f79a541615694029d845e31f2f362484679c1b9a3fd8588822a33a0e13383f4
[remix debugger]: http://etherscan.io/remix?txhash=0x7f79a541615694029d845e31f2f362484679c1b9a3fd8588822a33a0e13383f4
[example setup]: https://github.com/mana-ethereum/mana/tree/master/apps/evm#example-setup

# Testing

Run:

```
mix test --exclude network
```

Tests tagged with network integrate with other nodes and cannot run unless another node is running in parallel. Use the `--exclude network` flag to exclude these tests.

## AntidoteDB Integration Tests

To test the new distributed storage implementation:

```bash
mix test apps/merkle_patricia_tree/test/merkle_patricia_tree/db/antidote_test.exs
```

This runs 17 comprehensive tests covering all AntidoteDB functionality.

If you want to only run [Ethereum common tests], we currently have:

```
# Ethereum Virtual Machine tests
cd apps/evm && mix test test/evm_test.exs

# Ethereum Blockchain tests
cd apps/blockchain && mix test test/blockchain_test.exs

# Ethereum General State tests
cd apps/blockchain && mix test test/blockchain/state_test.exs

# Ethereum Transaction tests
cd apps/blockchain && mix test test/blockchain/transaction_test.exs
```

## Test Status

Ethereum common tests are created for all clients to test against. See the [common test documentation] for more information.

[VMTests] = 100% passing

| Hardfork          | [BlockchainTests] passing | [GeneralStateTests] passing | Complete? |
| ----------------- | ------------------------- | --------------------------- | --------- |
| Frontier          | 100% (1328/1328)          | 100% (1041/1041)            | ✓         |
| Homestead         | 100% (2211/2211)          | 100% (2069/2069)            | ✓         |
| HomesteadToDaoAt5 | 100% (4/4)                | N/A                         | ✓         |
| TangerineWhistle  | 100% (1270/1270)          | 100% (1120/1120)            | ✓         |
| SpuriousDragon    | 100% (1201/1201)          | 100% (1193/1193)            | ✓         |
| Byzantium         | 100% (4954/4954)          | 100% (4813/4813)            | ✓         |
| Constantinople    | 100% (10627/10627)        | 100% (10588/10588)          | ✓         |

View the community [Constantinople Project Tracker](https://github.com/ethereum/pm/issues/53).

[Ethereum common tests]: https://github.com/ethereum/tests
[common test documentation]: http://ethereum-tests.readthedocs.io/en/latest/index.html
[VMTests]: https://github.com/ethereum/tests/tree/develop/VMTests/vmTests
[blockchaintests]: https://github.com/ethereum/tests/tree/develop/BlockchainTests
[generalstatetests]: https://github.com/ethereum/tests/tree/develop/GeneralStateTests

## Updating Common Tests

The Ethereum common tests are in a submodule. To update:

```bash
% cd ethereum_common_tests
% git checkout develop
% git pull
```

# Project Status

| Functionality                                                                       | Status                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| ----------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Modern Infrastructure**                                                           | ✅ **Complete** - Elixir 1.18, Erlang 27.2, modern CI/CD, security scanning                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| **Distributed Storage**                                                             | ✅ **Complete** - AntidoteDB integration with full test coverage (17/17 tests passing)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             |
| Encoding and Hashing                                                                | The [RLP] encoding protocol and the [Merkle Patricia Tree] data structure are fully implemented.                                                                                                                                                                                                                                                                                                                                                                                                       |
| [Ethereum Virtual Machine] | Our EVM currently passes 100% of the common [VM tests]. We are refining our implementation to address subtle differences between our EVM and other implementations.                                                                                                                                                                                                                                                       |
| Peer to Peer Networking                                                             | Currently we can connect to one of the Ethereum bootnodes, get a list of peers, and add them to a list of known peers. We have fully implemented the modified [kademlia DHT]. <br /><br />We can also successfully perform the encrypted handshake with peer nodes and derive secrets to frame the rest of the messages. We are currently configuring ExWire to work against a local Geth/Parity node. |
| DEVp2p Protocol and Ethereum Wire Protocol                                          | We are in the process of addressing networking layer issues. Progress is being tracked in Issue [#407].                                                                                                                                                                                                                                                                                                                                                                                                                       |

[RLP]: https://hex.pm/packages/ex_rlp
[Merkle Patricia Tree]: https://github.com/mana-ethereum/mana/tree/master/apps/merkle_patricia_tree
[Ethereum Virtual Machine]: https://github.com/mana-ethereum/mana/tree/master/apps/evm
[VM tests]: https://github.com/ethereum/tests/tree/develop/VMTests
[kademlia DHT]: https://github.com/mana-ethereum/mana/tree/master/apps/ex_wire/lib/ex_wire/kademlia
[#407]: https://github.com/mana-ethereum/mana/issues/407

## 🏗️ Architecture

### Distributed Storage with AntidoteDB

Mana-Ethereum uses AntidoteDB as its primary storage backend, providing:

- **Distributed Transactions**: Full ACID compliance for blockchain operations
- **CRDT Support**: Concurrent updates with automatic conflict resolution  
- **High Availability**: Fault-tolerant distributed storage
- **Blockchain Optimized**: Perfect for Ethereum state management

The AntidoteDB integration is fully tested with 17 comprehensive test cases covering:

- Basic CRUD operations
- Binary data handling
- Large value storage
- Concurrent operations
- Trie integration
- Connection management

### Modern Development Stack

- **Elixir 1.18**: Latest stable version with modern features
- **Erlang 27.2**: Latest OTP release for maximum performance
- **NixOS Development Environment**: Reproducible builds across platforms
- **GitHub Actions CI/CD**: Automated testing, security scanning, and deployment
- **CodeQL Security Scanning**: Automated vulnerability detection
- **Dependabot**: Automated dependency updates

# Documentation

To view module and reference documentation:

1. Generate documentation.
    `mix docs`

2. View the generated docs.
    `open doc/index.html`

# License

Licensed under either of:

- Apache License, Version 2.0, ([LICENSE_APACHE](LICENSE_APACHE) or <http://www.apache.org/licenses/LICENSE-2.0>)
- MIT license ([LICENSE_MIT](LICENSE_MIT) or <http://opensource.org/licenses/MIT>)

at your option.

# Contributing

See the [CONTRIBUTING](CONTRIBUTING.md) document for contribution, testing and pull request protocol.

Unless you explicitly state otherwise, any contribution intentionally submitted for inclusion in the work by you, as defined in the Apache-2.0 license, shall be dual licensed as above, without any additional terms or conditions.

# References

- [Ethereum yellow paper]: Ethereum: A Secure Decentralised Generalised Transaction Ledger Byzantium Version

- [Message Calls in Ethereum]

[Message Calls in Ethereum]: http://www.badykov.com/ethereum/2018/06/17/message-calls-in-ethereum/
