# Mana-Ethereum

[![GitHub Actions](https://github.com/mana-ethereum/mana/workflows/CI/badge.svg)](https://github.com/mana-ethereum/mana/actions) [![CodeQL](https://github.com/mana-ethereum/mana/workflows/CodeQL/badge.svg)](https://github.com/mana-ethereum/mana/security/code-scanning)

The world's first distributed Ethereum client leveraging Elixir/OTP fault tolerance and AntidoteDB's CRDT-based storage for unprecedented resilience and scalability.

Mana-Ethereum provides unique capabilities no other client offers:
- Multi-datacenter operation with automatic failover
- Zero-coordination writes using CRDTs
- Partition-tolerant operation during network splits
- Horizontal scalability without resharding
- Hardware security module (HSM) integration
- Enterprise compliance system (SOX, PCI-DSS, FIPS 140-2, GDPR)

## Documentation

- [Roadmap](docs/progress/TODO.md) - Development priorities and timeline
- [Contributing](CONTRIBUTING.md) - How to contribute
- [Progress Reports](docs/progress/) - Detailed implementation notes
- [HSM Integration](docs/progress/HSM_INTEGRATION.md) - Hardware security module setup
- [Compliance System](docs/COMPLIANCE_SYSTEM.md) - Enterprise compliance features

## Current Status: Phase 3 (75% Complete)

**Production Ready Features:**
- 100% EVM test compliance across all hardforks
- AntidoteDB CRDT-based distributed storage
- Multi-datacenter consensus-free operation
- Fast sync with state snapshots (sub-hour sync time)
- Comprehensive P2P networking with peer reputation
- Complete JSON-RPC API with WebSocket subscriptions
- Hardware security module integration
- Enterprise compliance system with audit trails

**Technology Stack:**
- Elixir 1.18.4 / Erlang 26.2.4 - Modern BEAM VM
- AntidoteDB - Distributed database with CRDT support
- GitHub Actions - CI/CD with security scanning

## Requirements

- Elixir 1.18.4+
- Erlang 26.2.4+
- AntidoteDB (for distributed features)

## Installation

```bash
git clone --recurse-submodules https://github.com/mana-ethereum/mana.git
cd mana
mix deps.get
mix compile
mix test --exclude network
```

## Usage

### Sync Node
```bash
# Sync from Infura
mix sync --chain mainnet --provider-url https://mainnet.infura.io/v3/<api_key>

# Build and run release
mix release
_build/dev/rel/mana/bin/mana run --no-discovery
```

### Development
```bash
# Run tests
mix test

# Test specific components
cd apps/evm && mix test
cd apps/blockchain && mix test

# Set debugging breakpoints
BREAKPOINT=0x60014578... mix sync
```

## Test Coverage

| Component | Status | Notes |
|-----------|--------|-------|
| EVM | 100% passing | All opcodes implemented |
| Blockchain | 100% passing | All hardforks supported |
| State Tests | 100% passing | Constantinople complete |
| P2P Networking | Production ready | Advanced peer management |
| JSON-RPC | Complete | All standard methods |
| HSM Integration | Production ready | PKCS#11 support |
| Compliance System | Production ready | Multi-framework support |

## Unique Capabilities

No other Ethereum client offers:

**Multi-Datacenter Operation**: Single logical node across continents with CRDT-based consensus-free replication

**Hardware Security Modules**: PKCS#11 integration with automatic fallback for enterprise cryptographic operations

**Enterprise Compliance**: Automated SOX, PCI-DSS, FIPS 140-2, GDPR reporting with immutable audit trails

**Zero-Coordination Writes**: Mathematical conflict resolution without traditional consensus mechanisms

**Partition Tolerance**: Continue operation during network splits with automatic reconciliation

## Documentation

```bash
mix docs
open doc/index.html
```

## License

Dual licensed under Apache 2.0 and MIT. See [LICENSE_APACHE](LICENSE_APACHE) and [LICENSE_MIT](LICENSE_MIT).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## References

- [Ethereum Yellow Paper](https://ethereum.github.io/yellowpaper/paper.pdf)
- [Ethereum Common Tests](https://github.com/ethereum/tests)
- [Development Roadmap](docs/progress/TODO.md)
