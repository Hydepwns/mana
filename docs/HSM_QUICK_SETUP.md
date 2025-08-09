# HSM Quick Setup Guide

Get HSM integration running in 5 minutes for development, or follow enterprise setup for production.

## Development Setup (SoftHSM)

### 1. Install SoftHSM

```bash
# Ubuntu/Debian
sudo apt-get update && sudo apt-get install -y softhsm2

# macOS
brew install softhsm

# RHEL/CentOS
sudo yum install softhsm
```

### 2. Initialize SoftHSM

```bash
# Create SoftHSM directory
mkdir -p ~/.config/softhsm2

# Initialize token
softhsm2-util --init-token --slot 0 --label "ETHEREUM_DEV" --pin 1234 --so-pin 1234
```

### 3. Configure Mana

Add to `config/dev.exs`:

```elixir
config :exth_crypto, :hsm,
  enabled: true,
  vendor: :softhsm,
  library_path: "/usr/lib/x86_64-linux-gnu/softhsm/libsofthsm2.so",  # Linux
  # library_path: "/usr/local/lib/softhsm/libsofthsm2.so",           # macOS
  slot_id: 0,
  pin: "1234",
  token_label: "ETHEREUM_DEV",
  fallback: %{enabled: true, auto_fallback_on_error: true}
```

### 4. Test

```elixir
# Start Mana
mix deps.get
iex -S mix

# Test HSM
iex> alias Blockchain.Transaction.HSMSignature
iex> {:ok, status} = HSMSignature.get_hsm_status()
iex> IO.inspect(status)
%{hsm_enabled: true, ...}

# Generate test key
iex> {:ok, key_id} = HSMSignature.generate_hsm_key("test-key", :transaction_signer)
iex> IO.puts("Generated HSM key: #{key_id}")

# Test signing
iex> tx = %Blockchain.Transaction{nonce: 0, gas_price: 20_000_000_000, gas_limit: 21_000, to: <<>>, value: 0, data: <<>>}
iex> signed_tx = HSMSignature.sign_transaction(tx, key_id, 1)
iex> IO.inspect(signed_tx)
```

HSM integration is now working in development.

---

## Enterprise Production Setup

### 1. HSM Prerequisites

Ensure your HSM is properly configured:

```bash
# Verify HSM library exists
ls -la /opt/nfast/toolkits/pkcs11/libcknfast.so  # Thales
ls -la /opt/cloudhsm/lib/libcloudhsm_pkcs11.so  # AWS CloudHSM
ls -la /usr/safenet/lunaclient/lib/libCryptoki2_64.so  # SafeNet Luna

# Test PKCS#11 connectivity (if available)
pkcs11-tool --list-slots --module /path/to/your/library.so
```

### 2. Secure Configuration

Create secure configuration files:

```bash
# Create HSM configuration directory
sudo mkdir -p /etc/mana/hsm
sudo chmod 700 /etc/mana/hsm

# Store PIN securely
echo "your_actual_hsm_pin" | sudo tee /etc/mana/hsm/pin
sudo chmod 600 /etc/mana/hsm/pin
sudo chown mana:mana /etc/mana/hsm/pin
```

### 3. Environment Configuration

```bash
# /etc/mana/hsm.env
HSM_ENABLED=true
HSM_VENDOR=thales  # or aws_cloudhsm, safenet_luna, utimaco, yubihsm
HSM_LIBRARY_PATH=/opt/nfast/toolkits/pkcs11/libcknfast.so
HSM_SLOT_ID=0
HSM_PIN_FILE=/etc/mana/hsm/pin
HSM_TOKEN_LABEL=ETHEREUM_PROD

# Load environment
source /etc/mana/hsm.env
```

### 4. Production Configuration

Add to `config/prod.exs`:

```elixir
config :exth_crypto, :hsm,
  enabled: true,
  # Vendor and connection details loaded from environment
  security_policy: %{
    require_hsm_for_roles: [:validator, :admin],
    allow_software_fallback: false,  # Disable for production
    max_signing_rate: 1000,
    audit_all_operations: true,
    key_generation_policy: %{
      default_backend: :hsm,
      extractable_keys: false,
      sensitive_keys: true
    }
  },
  fallback: %{
    enabled: false,  # Strict HSM-only mode
    auto_fallback_on_error: false
  },
  monitoring: %{
    health_check_interval: 15_000,  # More frequent checks
    performance_monitoring: true,
    alert_on_fallback: true,
    alert_on_errors: true
  }
```

### 5. Generate Production Keys

```elixir
# In production IEx session
alias Blockchain.Transaction.HSMSignature

# Generate validator key
{:ok, validator_key} = HSMSignature.generate_hsm_key("validator-primary-2024", :validator)
IO.puts("Validator key: #{validator_key}")

# Generate admin key
{:ok, admin_key} = HSMSignature.generate_hsm_key("admin-primary-2024", :admin)
IO.puts("Admin key: #{admin_key}")

# Verify keys are in HSM
{:ok, keys} = HSMSignature.list_hsm_keys()
Enum.each(keys, fn key -> 
  IO.puts("Key: #{key.id} (#{key.role}) - Backend: #{key.backend}")
end)
```

### 6. Monitoring Setup

```elixir
# Check health
{:ok, health} = ExthCrypto.HSM.Monitor.get_health_status()
IO.inspect(health)

# Export Prometheus metrics
metrics = ExthCrypto.HSM.Monitor.export_prometheus_metrics()
File.write!("/var/lib/mana/metrics/hsm_metrics.prom", metrics)
```

Production HSM setup complete.

---

## Troubleshooting

### Common Issues

**1. Library Not Found**
```bash
# Check library exists and is executable
file /path/to/library.so
ldd /path/to/library.so  # Check dependencies
```

**2. Permission Denied**
```bash
# Check file permissions
ls -la /path/to/library.so
# Should be readable by the mana user

# Check SELinux (if enabled)
setsebool -P use_unconfined_t 1  # Development only!
```

**3. HSM Not Responding**
```elixir
# Test basic connectivity
iex> ExthCrypto.HSM.PKCS11Interface.health_check()

# Check slot information
iex> ExthCrypto.HSM.PKCS11Interface.get_slot_info()
```

**4. Authentication Failed**
```bash
# Verify PIN
echo $HSM_PIN_FILE
cat $HSM_PIN_FILE

# Check token label
pkcs11-tool --list-slots --module /path/to/library.so
```

### Debug Mode

Enable comprehensive logging:

```elixir
# config/dev.exs
config :logger, level: :debug

config :exth_crypto, :hsm,
  debug: true,
  monitoring: %{
    health_check_interval: 5_000  # More frequent checks
  }
```

### Health Check Script

Create a health check script:

```bash
#!/bin/bash
# /usr/local/bin/mana-hsm-check

export $(cat /etc/mana/hsm.env | xargs)

elixir -e "
{:ok, _} = Application.ensure_all_started(:exth_crypto)
case ExthCrypto.HSM.Monitor.get_health_status() do
  {:ok, %{overall_status: :healthy}} -> 
    IO.puts(\"HSM Status: HEALTHY\")
    System.halt(0)
  {:ok, status} -> 
    IO.puts(\"HSM Status: #{status.overall_status}\")
    IO.inspect(status)
    System.halt(1)
  {:error, reason} -> 
    IO.puts(\"HSM Error: #{reason}\")
    System.halt(2)
end
"
```

---

## 🔄 Migration Checklist

### From Software to HSM

- [ ] **1. Install HSM software and verify connectivity**
- [ ] **2. Configure HSM with appropriate slots and tokens**
- [ ] **3. Update Mana configuration with HSM settings**
- [ ] **4. Start Mana and verify HSM integration works**
- [ ] **5. Generate HSM keys for critical operations**
- [ ] **6. Update code to use HSM keys instead of private keys**
- [ ] **7. Test transaction signing with HSM keys**
- [ ] **8. Set up monitoring and alerting**
- [ ] **9. Disable software fallback for production (optional)**
- [ ] **10. Document key IDs and emergency procedures**

### Code Migration

```elixir
# BEFORE: Using private keys
private_key = Base.decode16!("your_private_key")
signed_tx = Signature.sign_transaction(tx, private_key, chain_id)

# AFTER: Using HSM keys
{:ok, key_id} = HSMSignature.generate_hsm_key("main-signer", :transaction_signer)
signed_tx = HSMSignature.sign_transaction(tx, key_id, chain_id)
```

---

**Need Help?**

- 📖 [Full HSM Documentation](HSM_INTEGRATION.md)
- 🐛 [Report Issues](https://github.com/your-org/mana/issues)
- 💬 [Join Discord](https://discord.gg/your-server)
- 📧 [Enterprise Support](mailto:enterprise@your-org.com)