use Mix.Config

# Production configuration for Mana-Ethereum
# This configuration is optimized for production deployment

# Environment configuration
config :mana, :environment, :prod

# Logger configuration for production
config :logger,
  level: :info,
  backends: [:console, :syslog],
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :user_id, :module, :function, :line]

# Console logger backend
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :user_id, :module, :function, :line]

# Syslog backend for production logging
config :logger, :syslog,
  app_name: "mana-ethereum",
  facility: :local0,
  level: :info

# AntidoteDB production configuration
config :merkle_patricia_tree, :antidote,
  host: System.get_env("ANTIDOTE_HOST") || "localhost",
  port: String.to_integer(System.get_env("ANTIDOTE_PORT") || "8087"),
  pool_size: String.to_integer(System.get_env("ANTIDOTE_POOL_SIZE") || "50"),
  timeout: String.to_integer(System.get_env("ANTIDOTE_TIMEOUT") || "30000"),
  retry_attempts: String.to_integer(System.get_env("ANTIDOTE_RETRY_ATTEMPTS") || "5"),
  retry_delay: String.to_integer(System.get_env("ANTIDOTE_RETRY_DELAY") || "1000"),
  batch_size: String.to_integer(System.get_env("ANTIDOTE_BATCH_SIZE") || "1000"),
  compression_enabled: System.get_env("ANTIDOTE_COMPRESSION_ENABLED") == "true",
  compression_threshold: String.to_integer(System.get_env("ANTIDOTE_COMPRESSION_THRESHOLD") || "1024")

# Memory optimization configuration
config :merkle_patricia_tree, :memory_optimizer,
  max_cache_size: String.to_integer(System.get_env("MEMORY_CACHE_SIZE") || "100000"),
  gc_threshold: String.to_float(System.get_env("MEMORY_GC_THRESHOLD") || "0.8"),
  compression_enabled: System.get_env("MEMORY_COMPRESSION_ENABLED") == "true",
  compression_threshold: String.to_integer(System.get_env("MEMORY_COMPRESSION_THRESHOLD") || "1024")

# Performance monitoring configuration
config :mana, :monitoring,
  enabled: System.get_env("MONITORING_ENABLED") == "true",
  metrics_port: String.to_integer(System.get_env("METRICS_PORT") || "9568"),
  health_check_port: String.to_integer(System.get_env("HEALTH_CHECK_PORT") || "8080"),
  prometheus_enabled: System.get_env("PROMETHEUS_ENABLED") == "true",
  grafana_enabled: System.get_env("GRAFANA_ENABLED") == "true"

# Security configuration
config :mana, :security,
  ssl_enabled: System.get_env("SSL_ENABLED") == "true",
  ssl_cert_path: System.get_env("SSL_CERT_PATH"),
  ssl_key_path: System.get_env("SSL_KEY_PATH"),
  rate_limiting_enabled: System.get_env("RATE_LIMITING_ENABLED") == "true",
  max_requests_per_minute: String.to_integer(System.get_env("MAX_REQUESTS_PER_MINUTE") || "1000")

# Network configuration
config :mana, :network,
  listen_port: String.to_integer(System.get_env("LISTEN_PORT") || "8545"),
  max_connections: String.to_integer(System.get_env("MAX_CONNECTIONS") || "1000"),
  connection_timeout: String.to_integer(System.get_env("CONNECTION_TIMEOUT") || "30000"),
  keepalive_timeout: String.to_integer(System.get_env("KEEPALIVE_TIMEOUT") || "60000")

# Blockchain configuration
config :mana, :blockchain,
  network: System.get_env("ETHEREUM_NETWORK") || "mainnet",
  sync_mode: System.get_env("SYNC_MODE") || "fast",
  max_peers: String.to_integer(System.get_env("MAX_PEERS") || "50"),
  bootnodes: String.split(System.get_env("BOOTNODES") || "", ","),
  data_dir: System.get_env("DATA_DIR") || "/var/lib/mana-ethereum"

# Database configuration
config :mana, :database,
  type: System.get_env("DATABASE_TYPE") || "antidote",
  path: System.get_env("DATABASE_PATH") || "/var/lib/mana-ethereum/db",
  max_open_files: String.to_integer(System.get_env("MAX_OPEN_FILES") || "10000"),
  cache_size: String.to_integer(System.get_env("CACHE_SIZE") || "1024"),
  write_buffer_size: String.to_integer(System.get_env("WRITE_BUFFER_SIZE") || "64")

# Backup and recovery configuration
config :mana, :backup,
  enabled: System.get_env("BACKUP_ENABLED") == "true",
  schedule: System.get_env("BACKUP_SCHEDULE") || "0 2 * * *",  # Daily at 2 AM
  retention_days: String.to_integer(System.get_env("BACKUP_RETENTION_DAYS") || "30"),
  backup_path: System.get_env("BACKUP_PATH") || "/var/backups/mana-ethereum"

# Alerting configuration
config :mana, :alerts,
  enabled: System.get_env("ALERTS_ENABLED") == "true",
  slack_webhook: System.get_env("SLACK_WEBHOOK"),
  email_recipients: String.split(System.get_env("EMAIL_RECIPIENTS") || "", ","),
  alert_thresholds: %{
    memory_usage: String.to_float(System.get_env("MEMORY_ALERT_THRESHOLD") || "0.9"),
    disk_usage: String.to_float(System.get_env("DISK_ALERT_THRESHOLD") || "0.8"),
    error_rate: String.to_float(System.get_env("ERROR_RATE_THRESHOLD") || "0.05")
  }

# Performance tuning configuration
config :mana, :performance,
  worker_pool_size: String.to_integer(System.get_env("WORKER_POOL_SIZE") || "100"),
  max_concurrent_requests: String.to_integer(System.get_env("MAX_CONCURRENT_REQUESTS") || "1000"),
  request_timeout: String.to_integer(System.get_env("REQUEST_TIMEOUT") || "30000"),
  batch_size: String.to_integer(System.get_env("BATCH_SIZE") || "1000")

# Development and debugging (disabled in production)
config :mana, :debug,
  enabled: false,
  trace_enabled: false,
  profiling_enabled: false

# Application-specific configurations
config :ex_wire,
  environment: :prod,
  perform_discovery: true,
  perform_sync: true,
  warp: false,
  max_peers: String.to_integer(System.get_env("MAX_PEERS") || "50")

config :blockchain,
  environment: :prod,
  data_dir: System.get_env("DATA_DIR") || "/var/lib/mana-ethereum"

config :evm,
  environment: :prod,
  gas_limit: String.to_integer(System.get_env("GAS_LIMIT") || "8000000")

config :jsonrpc2,
  environment: :prod,
  port: String.to_integer(System.get_env("JSONRPC_PORT") || "8545"),
  max_connections: String.to_integer(System.get_env("MAX_CONNECTIONS") || "1000")

# Import environment-specific overrides
import_config "#{config_env()}.exs"
