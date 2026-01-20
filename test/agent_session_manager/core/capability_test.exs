defmodule AgentSessionManager.Core.CapabilityTest do
  use AgentSessionManager.SupertesterCase, async: true

  alias AgentSessionManager.Core.Capability

  describe "Capability struct" do
    test "defines required fields" do
      capability = %Capability{}

      assert Map.has_key?(capability, :name)
      assert Map.has_key?(capability, :type)
      assert Map.has_key?(capability, :enabled)
    end

    test "defines optional fields" do
      capability = %Capability{}

      assert Map.has_key?(capability, :description)
      assert Map.has_key?(capability, :config)
      assert Map.has_key?(capability, :permissions)
    end

    test "has default values" do
      capability = %Capability{}

      assert capability.enabled == true
      assert capability.config == %{}
      assert capability.permissions == []
      assert capability.description == nil
    end
  end

  describe "Capability types" do
    test "valid capability types" do
      valid_types = [
        :tool,
        :resource,
        :prompt,
        :sampling,
        :file_access,
        :network_access,
        :code_execution
      ]

      for type <- valid_types do
        assert Capability.valid_type?(type),
               "Expected #{type} to be a valid capability type"
      end
    end

    test "invalid capability types are rejected" do
      refute Capability.valid_type?(:invalid_type)
      refute Capability.valid_type?("string_type")
      refute Capability.valid_type?(123)
    end

    test "all_types/0 returns all valid capability types" do
      types = Capability.all_types()

      assert is_list(types)
      assert :tool in types
      assert :resource in types
      assert :prompt in types
    end
  end

  describe "Capability.new/1" do
    test "creates a capability with required fields" do
      {:ok, capability} =
        Capability.new(%{
          name: "web_search",
          type: :tool
        })

      assert capability.name == "web_search"
      assert capability.type == :tool
      assert capability.enabled == true
    end

    test "accepts optional description" do
      {:ok, capability} =
        Capability.new(%{
          name: "web_search",
          type: :tool,
          description: "Search the web for information"
        })

      assert capability.description == "Search the web for information"
    end

    test "accepts config map" do
      {:ok, capability} =
        Capability.new(%{
          name: "web_search",
          type: :tool,
          config: %{max_results: 10, timeout_ms: 5000}
        })

      assert capability.config == %{max_results: 10, timeout_ms: 5000}
    end

    test "accepts permissions list" do
      {:ok, capability} =
        Capability.new(%{
          name: "file_reader",
          type: :file_access,
          permissions: ["read", "list"]
        })

      assert capability.permissions == ["read", "list"]
    end

    test "allows disabling capability" do
      {:ok, capability} =
        Capability.new(%{
          name: "web_search",
          type: :tool,
          enabled: false
        })

      assert capability.enabled == false
    end

    test "returns error when name is missing" do
      result = Capability.new(%{type: :tool})

      assert {:error, error} = result
      assert error.code == :validation_error
      assert error.message =~ "name"
    end

    test "returns error when name is empty" do
      result = Capability.new(%{name: "", type: :tool})

      assert {:error, error} = result
      assert error.code == :validation_error
    end

    test "returns error when type is missing" do
      result = Capability.new(%{name: "web_search"})

      assert {:error, error} = result
      assert error.code == :validation_error
      assert error.message =~ "type"
    end

    test "returns error when type is invalid" do
      result = Capability.new(%{name: "web_search", type: :invalid_type})

      assert {:error, error} = result
      assert error.code == :invalid_capability_type
    end
  end

  describe "Capability.enable/1 and Capability.disable/1" do
    test "enable/1 sets enabled to true" do
      {:ok, capability} = Capability.new(%{name: "web_search", type: :tool, enabled: false})
      enabled = Capability.enable(capability)

      assert enabled.enabled == true
    end

    test "disable/1 sets enabled to false" do
      {:ok, capability} = Capability.new(%{name: "web_search", type: :tool})
      disabled = Capability.disable(capability)

      assert disabled.enabled == false
    end
  end

  describe "Capability.to_map/1" do
    test "converts capability to a map for JSON serialization" do
      {:ok, capability} =
        Capability.new(%{
          name: "web_search",
          type: :tool,
          description: "Search the web",
          config: %{max_results: 10},
          permissions: ["read"]
        })

      map = Capability.to_map(capability)

      assert is_map(map)
      assert map["name"] == "web_search"
      assert map["type"] == "tool"
      assert map["description"] == "Search the web"
      assert map["enabled"] == true
      assert map["config"] == %{"max_results" => 10}
      assert map["permissions"] == ["read"]
    end
  end

  describe "Capability.from_map/1" do
    test "reconstructs a capability from a map" do
      {:ok, original} =
        Capability.new(%{
          name: "web_search",
          type: :tool,
          description: "Search the web",
          config: %{max_results: 10}
        })

      map = Capability.to_map(original)
      {:ok, restored} = Capability.from_map(map)

      assert restored.name == original.name
      assert restored.type == original.type
      assert restored.description == original.description
      assert restored.config == original.config
      assert restored.enabled == original.enabled
    end

    test "returns error for invalid map" do
      result = Capability.from_map(%{})

      assert {:error, error} = result
      assert error.code == :validation_error
    end
  end
end
