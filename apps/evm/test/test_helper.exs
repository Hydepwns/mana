ExUnit.configure(timeout: :infinity)
ExUnit.start()

# Load test support files
Code.require_file("support/test_factory.ex", __DIR__)
