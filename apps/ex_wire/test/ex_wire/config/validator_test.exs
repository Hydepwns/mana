defmodule ExWire.Config.ValidatorTest do
  use ExUnit.Case
  
  alias ExWire.Config.Validator
  
  describe "type validation" do
    test "validates string types" do
      schema = %{type: :string}
      
      assert Validator.validate_value("hello", schema) == :ok
      assert {:error, _} = Validator.validate_value(123, schema)
      assert {:error, _} = Validator.validate_value(true, schema)
    end
    
    test "validates integer types" do
      schema = %{type: :integer}
      
      assert Validator.validate_value(42, schema) == :ok
      assert {:error, _} = Validator.validate_value(3.14, schema)
      assert {:error, _} = Validator.validate_value("42", schema)
    end
    
    test "validates boolean types" do
      schema = %{type: :boolean}
      
      assert Validator.validate_value(true, schema) == :ok
      assert Validator.validate_value(false, schema) == :ok
      assert {:error, _} = Validator.validate_value(1, schema)
      assert {:error, _} = Validator.validate_value("true", schema)
    end
    
    test "validates list types" do
      schema = %{type: :list}
      
      assert Validator.validate_value([1, 2, 3], schema) == :ok
      assert Validator.validate_value([], schema) == :ok
      assert {:error, _} = Validator.validate_value("not a list", schema)
    end
    
    test "validates typed lists" do
      schema = %{type: {:list, :string}}
      
      assert Validator.validate_value(["a", "b", "c"], schema) == :ok
      assert {:error, _} = Validator.validate_value([1, 2, 3], schema)
      assert {:error, _} = Validator.validate_value(["a", 2, "c"], schema)
    end
    
    test "validates map types" do
      schema = %{type: :map}
      
      assert Validator.validate_value(%{key: "value"}, schema) == :ok
      assert Validator.validate_value(%{}, schema) == :ok
      assert {:error, _} = Validator.validate_value([key: "value"], schema)
    end
  end
  
  describe "constraint validation" do
    test "validates required fields" do
      schema = %{type: :string, required: true}
      
      assert Validator.validate_value("value", schema) == :ok
      assert {:error, :required_field_missing} = Validator.validate_value(nil, schema)
    end
    
    test "validates enum values" do
      schema = %{type: :string, enum: ["mainnet", "goerli", "sepolia"]}
      
      assert Validator.validate_value("mainnet", schema) == :ok
      assert Validator.validate_value("goerli", schema) == :ok
      assert {:error, {:invalid_enum_value, _}} = Validator.validate_value("ropsten", schema)
    end
    
    test "validates numeric ranges" do
      schema = %{type: :integer, min: 1, max: 100}
      
      assert Validator.validate_value(50, schema) == :ok
      assert Validator.validate_value(1, schema) == :ok
      assert Validator.validate_value(100, schema) == :ok
      assert {:error, {:below_minimum, _}} = Validator.validate_value(0, schema)
      assert {:error, {:above_maximum, _}} = Validator.validate_value(101, schema)
    end
    
    test "validates with minimum only" do
      schema = %{type: :integer, min: 10}
      
      assert Validator.validate_value(10, schema) == :ok
      assert Validator.validate_value(1000, schema) == :ok
      assert {:error, {:below_minimum, _}} = Validator.validate_value(9, schema)
    end
    
    test "validates with maximum only" do
      schema = %{type: :integer, max: 100}
      
      assert Validator.validate_value(0, schema) == :ok
      assert Validator.validate_value(100, schema) == :ok
      assert {:error, {:above_maximum, _}} = Validator.validate_value(101, schema)
    end
  end
  
  describe "format validation" do
    test "validates email format" do
      schema = %{type: :string, format: :email}
      
      assert Validator.validate_value("user@example.com", schema) == :ok
      assert Validator.validate_value("test.user+tag@domain.co.uk", schema) == :ok
      assert {:error, {:invalid_format, _}} = Validator.validate_value("invalid.email", schema)
      assert {:error, {:invalid_format, _}} = Validator.validate_value("@example.com", schema)
    end
    
    test "validates URL format" do
      schema = %{type: :string, format: :url}
      
      assert Validator.validate_value("http://example.com", schema) == :ok
      assert Validator.validate_value("https://sub.example.com/path", schema) == :ok
      assert {:error, {:invalid_format, _}} = Validator.validate_value("ftp://example.com", schema)
      assert {:error, {:invalid_format, _}} = Validator.validate_value("not a url", schema)
    end
    
    test "validates IP address format" do
      schema = %{type: :string, format: :ip_address}
      
      assert Validator.validate_value("192.168.1.1", schema) == :ok
      assert Validator.validate_value("::1", schema) == :ok
      assert Validator.validate_value("2001:db8::1", schema) == :ok
      assert {:error, {:invalid_format, _}} = Validator.validate_value("256.256.256.256", schema)
      assert {:error, {:invalid_format, _}} = Validator.validate_value("not.an.ip", schema)
    end
    
    test "validates regex patterns" do
      schema = %{type: :string, format: ~r/^[A-Z]{2,4}$/}
      
      assert Validator.validate_value("AB", schema) == :ok
      assert Validator.validate_value("ABCD", schema) == :ok
      assert {:error, {:invalid_format, _}} = Validator.validate_value("A", schema)
      assert {:error, {:invalid_format, _}} = Validator.validate_value("ABCDE", schema)
      assert {:error, {:invalid_format, _}} = Validator.validate_value("ab", schema)
    end
  end
  
  describe "custom validation" do
    test "validates with custom validator function" do
      schema = %{
        type: :integer,
        validator: fn value ->
          if rem(value, 2) == 0 do
            :ok
          else
            {:error, "must be even"}
          end
        end
      }
      
      assert Validator.validate_value(2, schema) == :ok
      assert Validator.validate_value(4, schema) == :ok
      assert {:error, "must be even"} = Validator.validate_value(3, schema)
    end
  end
  
  describe "deep validation" do
    test "validates nested configuration" do
      schema = %{
        blockchain: %{
          network: %{type: :string, required: true, enum: ["mainnet", "goerli"]},
          chain_id: %{type: :integer, required: true, min: 1}
        },
        p2p: %{
          port: %{type: :integer, min: 1024, max: 65535},
          max_peers: %{type: :integer, min: 1, max: 200}
        }
      }
      
      valid_config = %{
        blockchain: %{
          network: "mainnet",
          chain_id: 1
        },
        p2p: %{
          port: 30303,
          max_peers: 50
        }
      }
      
      assert Validator.validate_config(valid_config, schema) == :ok
    end
    
    test "reports nested validation errors" do
      schema = %{
        blockchain: %{
          network: %{type: :string, required: true, enum: ["mainnet", "goerli"]},
          chain_id: %{type: :integer, required: true, min: 1}
        }
      }
      
      invalid_config = %{
        blockchain: %{
          network: "invalid_network",
          chain_id: 0
        }
      }
      
      {:error, {:validation_failed, errors}} = Validator.validate_config(invalid_config, schema)
      
      assert length(errors) == 2
      assert Enum.any?(errors, fn {path, _} -> path == [:blockchain, :network] end)
      assert Enum.any?(errors, fn {path, _} -> path == [:blockchain, :chain_id] end)
    end
  end
  
  describe "validation report" do
    test "generates comprehensive validation report" do
      schema = %{
        required_field: %{type: :string, required: true},
        optional_field: %{type: :integer, min: 0}
      }
      
      config = %{
        optional_field: 10,
        extra_field: "not in schema"
      }
      
      report = Validator.validation_report(config, schema)
      
      assert report.valid == false
      assert length(report.errors) > 0
      assert Enum.any?(report.errors, fn error -> 
        error.path == "required_field" 
      end)
      
      # Should have warning about unused field
      assert length(report.warnings) > 0
    end
    
    test "reports deprecated fields" do
      schema = %{
        old_field: %{type: :string, deprecated: true},
        new_field: %{type: :string}
      }
      
      config = %{
        old_field: "value",
        new_field: "value"
      }
      
      report = Validator.validation_report(config, schema)
      
      assert report.valid == true
      assert Enum.any?(report.warnings, fn warning ->
        warning.type == :deprecated_fields
      end)
    end
  end
end