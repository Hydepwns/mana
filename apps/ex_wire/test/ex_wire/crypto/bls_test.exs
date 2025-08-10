defmodule ExWire.Crypto.BLSTest do
  use ExUnit.Case, async: true
  alias ExWire.Crypto.BLS

  describe "BLS signature operations" do
    test "generate_keypair/0 creates valid keypair" do
      {pubkey, privkey} = BLS.generate_keypair()

      assert byte_size(pubkey) == 48
      assert byte_size(privkey) == 32

      # Verify we can derive pubkey from privkey
      derived_pubkey = BLS.privkey_to_pubkey(privkey)
      assert derived_pubkey == pubkey
    end

    test "sign/2 and verify/3 work correctly" do
      {pubkey, privkey} = BLS.generate_keypair()
      message = "Hello, Ethereum 2.0!"

      signature = BLS.sign(privkey, message)
      assert byte_size(signature) == 96

      # Valid signature should verify
      assert BLS.verify(pubkey, message, signature) == true

      # Wrong message should fail
      assert BLS.verify(pubkey, "Wrong message", signature) == false

      # Wrong pubkey should fail
      {wrong_pubkey, _} = BLS.generate_keypair()
      assert BLS.verify(wrong_pubkey, message, signature) == false
    end

    test "aggregate_signatures/1 combines multiple signatures" do
      # Create multiple signers
      signers =
        for _ <- 1..3 do
          {pubkey, privkey} = BLS.generate_keypair()
          {pubkey, privkey}
        end

      message = "Shared message for aggregation"

      # Each signer signs the message
      signatures =
        for {_, privkey} <- signers do
          BLS.sign(privkey, message)
        end

      # Aggregate the signatures
      agg_signature = BLS.aggregate_signatures(signatures)
      assert byte_size(agg_signature) == 96

      # Aggregate the public keys
      pubkeys = for {pubkey, _} <- signers, do: pubkey
      agg_pubkey = BLS.aggregate_pubkeys(pubkeys)
      assert byte_size(agg_pubkey) == 48

      # Verify the aggregate signature
      assert BLS.verify(agg_pubkey, message, agg_signature) == true
    end

    test "fast_aggregate_verify/3 verifies multiple signatures of same message" do
      # Create multiple signers
      signers =
        for _ <- 1..5 do
          {pubkey, privkey} = BLS.generate_keypair()
          {pubkey, privkey}
        end

      message = "Attestation data"

      # Each signer signs the same message
      signatures =
        for {_, privkey} <- signers do
          BLS.sign(privkey, message)
        end

      # Aggregate signatures
      agg_signature = BLS.aggregate_signatures(signatures)

      # Get all public keys
      pubkeys = for {pubkey, _} <- signers, do: pubkey

      # Fast aggregate verify should succeed
      assert BLS.fast_aggregate_verify(pubkeys, message, agg_signature) == true

      # Wrong message should fail
      assert BLS.fast_aggregate_verify(pubkeys, "wrong", agg_signature) == false

      # Missing pubkey should fail
      assert BLS.fast_aggregate_verify(Enum.drop(pubkeys, 1), message, agg_signature) == false
    end

    test "aggregate_verify/2 verifies signatures of different messages" do
      # Create signers with different messages
      test_data = [
        {"Message 1 for Alice"},
        {"Message 2 for Bob"},
        {"Message 3 for Charlie"}
      ]

      pubkey_message_pairs = []
      signatures = []

      for message <- test_data do
        {pubkey, privkey} = BLS.generate_keypair()
        signature = BLS.sign(privkey, message)

        pubkey_message_pairs = pubkey_message_pairs ++ [{pubkey, message}]
        signatures = signatures ++ [signature]
      end

      # Aggregate all signatures
      agg_signature = BLS.aggregate_signatures(signatures)

      # Aggregate verify should succeed
      assert BLS.aggregate_verify(pubkey_message_pairs, agg_signature) == true

      # Modified message should fail
      [{pk, _} | rest] = pubkey_message_pairs
      wrong_pairs = [{pk, "wrong"} | rest]
      assert BLS.aggregate_verify(wrong_pairs, agg_signature) == false
    end
  end

  describe "Ethereum 2.0 specific functions" do
    test "sign_with_domain/3 adds domain separation" do
      {pubkey, privkey} = BLS.generate_keypair()
      message = "Block root hash"
      domain = :crypto.strong_rand_bytes(32)

      {:ok, signature} = BLS.sign_with_domain(privkey, message, domain)
      assert byte_size(signature) == 96

      # Verify with domain should succeed
      assert BLS.verify_with_domain(pubkey, message, signature, domain) == true

      # Wrong domain should fail
      wrong_domain = :crypto.strong_rand_bytes(32)
      assert BLS.verify_with_domain(pubkey, message, signature, wrong_domain) == false
    end

    test "eth2_sign/5 handles Ethereum 2.0 domain construction" do
      {pubkey, privkey} = BLS.generate_keypair()
      message = "Attestation data"
      domain_type = :beacon_attester
      fork_version = <<0, 0, 0, 1>>
      genesis_validators_root = :crypto.strong_rand_bytes(32)

      {:ok, signature} =
        BLS.eth2_sign(
          privkey,
          message,
          domain_type,
          fork_version,
          genesis_validators_root
        )

      assert byte_size(signature) == 96

      # Build the expected domain for verification
      domain = BLS.compute_domain(domain_type, fork_version, genesis_validators_root)
      assert BLS.verify_with_domain(pubkey, message, signature, domain) == true
    end

    test "eth2_fast_aggregate_verify/4 verifies attestations" do
      # Simulate multiple validators signing same attestation
      validators =
        for _ <- 1..10 do
          {pubkey, privkey} = BLS.generate_keypair()
          {pubkey, privkey}
        end

      attestation_data = "Attestation for slot 12345"
      domain = :crypto.strong_rand_bytes(32)

      # Each validator signs with domain
      signatures =
        for {_, privkey} <- validators do
          {:ok, sig} = BLS.sign_with_domain(privkey, attestation_data, domain)
          sig
        end

      # Aggregate signatures
      agg_signature = BLS.aggregate_signatures(signatures)

      # Get all public keys
      pubkeys = for {pubkey, _} <- validators, do: pubkey

      # Fast aggregate verify should succeed
      assert BLS.eth2_fast_aggregate_verify(
               pubkeys,
               attestation_data,
               agg_signature,
               domain
             ) == true
    end

    test "derive_child_privkey/2 derives validator keys" do
      parent_privkey = :crypto.strong_rand_bytes(32)

      # Derive multiple child keys
      child1 = BLS.derive_child_privkey(parent_privkey, 0)
      child2 = BLS.derive_child_privkey(parent_privkey, 1)
      child3 = BLS.derive_child_privkey(parent_privkey, 2)

      # Child keys should be different
      assert child1 != child2
      assert child2 != child3
      assert child1 != child3

      # Child keys should be valid
      assert byte_size(child1) == 32
      assert byte_size(child2) == 32
      assert byte_size(child3) == 32

      # Same index should produce same key
      child1_again = BLS.derive_child_privkey(parent_privkey, 0)
      assert child1 == child1_again
    end

    test "create_deposit_signature/3 creates valid deposit signatures" do
      {pubkey, privkey} = BLS.generate_keypair()

      # Create deposit message (pubkey + withdrawal credentials + amount)
      withdrawal_credentials = :crypto.strong_rand_bytes(32)
      # 32 ETH in Gwei
      amount = <<32, 0, 0, 0, 0, 0, 0, 0>>
      deposit_message = pubkey <> withdrawal_credentials <> amount

      # Genesis fork version
      fork_version = <<0, 0, 0, 0>>

      {:ok, signature} =
        BLS.create_deposit_signature(
          privkey,
          deposit_message,
          fork_version
        )

      assert byte_size(signature) == 96

      # Verify the deposit signature with deposit domain
      deposit_domain = BLS.compute_domain(:deposit, fork_version, <<0::256>>)
      assert BLS.verify_with_domain(pubkey, deposit_message, signature, deposit_domain) == true
    end
  end

  describe "Edge cases and error handling" do
    test "invalid privkey size returns error" do
      assert {:error, :invalid_privkey_size} =
               BLS.sign_with_domain(<<1, 2, 3>>, "message", :crypto.strong_rand_bytes(32))
    end

    test "invalid pubkey size returns error" do
      assert false ==
               BLS.verify_with_domain(
                 <<1, 2, 3>>,
                 "message",
                 :crypto.strong_rand_bytes(96),
                 :crypto.strong_rand_bytes(32)
               )
    end

    test "invalid signature size returns error" do
      {pubkey, _} = BLS.generate_keypair()

      assert false ==
               BLS.verify_with_domain(
                 pubkey,
                 "message",
                 <<1, 2, 3>>,
                 :crypto.strong_rand_bytes(32)
               )
    end

    test "invalid domain size returns error" do
      {_, privkey} = BLS.generate_keypair()

      assert {:error, :invalid_domain_size} =
               BLS.sign_with_domain(privkey, "message", <<1, 2, 3>>)
    end

    test "empty signature list returns error" do
      assert_raise FunctionClauseError, fn ->
        BLS.aggregate_signatures([])
      end
    end

    test "empty pubkey list returns error" do
      assert_raise FunctionClauseError, fn ->
        BLS.aggregate_pubkeys([])
      end
    end

    test "fast_aggregate_verify with empty pubkeys returns false" do
      signature = :crypto.strong_rand_bytes(96)
      assert false == BLS.fast_aggregate_verify([], "message", signature)
    end
  end

  describe "Performance characteristics" do
    @tag :performance
    test "signature generation performance" do
      {_, privkey} = BLS.generate_keypair()
      message = "Performance test message"

      {time, _} =
        :timer.tc(fn ->
          for _ <- 1..100 do
            BLS.sign(privkey, message)
          end
        end)

      # Convert to ms
      avg_time = time / 100 / 1000
      IO.puts("Average signature time: #{avg_time}ms")

      # Should be reasonably fast (< 10ms per signature)
      assert avg_time < 10
    end

    @tag :performance
    test "verification performance" do
      {pubkey, privkey} = BLS.generate_keypair()
      message = "Performance test message"
      signature = BLS.sign(privkey, message)

      {time, _} =
        :timer.tc(fn ->
          for _ <- 1..100 do
            BLS.verify(pubkey, message, signature)
          end
        end)

      # Convert to ms
      avg_time = time / 100 / 1000
      IO.puts("Average verification time: #{avg_time}ms")

      # Should be reasonably fast (< 15ms per verification)
      assert avg_time < 15
    end

    @tag :performance
    test "aggregation performance with many signatures" do
      # Create many signatures
      signatures =
        for _ <- 1..100 do
          {_, privkey} = BLS.generate_keypair()
          BLS.sign(privkey, "shared message")
        end

      {time, agg_sig} =
        :timer.tc(fn ->
          BLS.aggregate_signatures(signatures)
        end)

      time_ms = time / 1000
      IO.puts("Aggregation of 100 signatures: #{time_ms}ms")

      assert byte_size(agg_sig) == 96
      # Should be fast (< 50ms for 100 signatures)
      assert time_ms < 50
    end
  end
end
