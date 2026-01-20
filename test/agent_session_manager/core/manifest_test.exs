defmodule AgentSessionManager.Core.ManifestTest do
  use ExUnit.Case, async: true
  alias AgentSessionManager.Core.Capability
  alias AgentSessionManager.Core.Manifest

  describe "Manifest struct" do
    test "defines required fields" do
      manifest = %Manifest{}

      assert Map.has_key?(manifest, :name)
      assert Map.has_key?(manifest, :version)
      assert Map.has_key?(manifest, :capabilities)
    end

    test "defines optional fields" do
      manifest = %Manifest{}

      assert Map.has_key?(manifest, :description)
      assert Map.has_key?(manifest, :provider)
      assert Map.has_key?(manifest, :config)
      assert Map.has_key?(manifest, :metadata)
    end

    test "has default values" do
      manifest = %Manifest{}

      assert manifest.capabilities == []
      assert manifest.config == %{}
      assert manifest.metadata == %{}
      assert manifest.description == nil
      assert manifest.provider == nil
    end
  end

  describe "Manifest.new/1" do
    test "creates a manifest with required fields" do
      {:ok, manifest} =
        Manifest.new(%{
          name: "my-agent",
          version: "1.0.0"
        })

      assert manifest.name == "my-agent"
      assert manifest.version == "1.0.0"
      assert manifest.capabilities == []
    end

    test "accepts description" do
      {:ok, manifest} =
        Manifest.new(%{
          name: "my-agent",
          version: "1.0.0",
          description: "A helpful AI agent"
        })

      assert manifest.description == "A helpful AI agent"
    end

    test "accepts provider" do
      {:ok, manifest} =
        Manifest.new(%{
          name: "my-agent",
          version: "1.0.0",
          provider: "anthropic"
        })

      assert manifest.provider == "anthropic"
    end

    test "accepts config" do
      {:ok, manifest} =
        Manifest.new(%{
          name: "my-agent",
          version: "1.0.0",
          config: %{model: "claude-3-opus", temperature: 0.7}
        })

      assert manifest.config == %{model: "claude-3-opus", temperature: 0.7}
    end

    test "accepts metadata" do
      {:ok, manifest} =
        Manifest.new(%{
          name: "my-agent",
          version: "1.0.0",
          metadata: %{author: "John Doe", license: "MIT"}
        })

      assert manifest.metadata == %{author: "John Doe", license: "MIT"}
    end

    test "accepts capabilities as list of Capability structs" do
      {:ok, cap1} = Capability.new(%{name: "web_search", type: :tool})
      {:ok, cap2} = Capability.new(%{name: "file_read", type: :file_access})

      {:ok, manifest} =
        Manifest.new(%{
          name: "my-agent",
          version: "1.0.0",
          capabilities: [cap1, cap2]
        })

      assert length(manifest.capabilities) == 2
      assert Enum.any?(manifest.capabilities, &(&1.name == "web_search"))
      assert Enum.any?(manifest.capabilities, &(&1.name == "file_read"))
    end

    test "accepts capabilities as list of maps" do
      {:ok, manifest} =
        Manifest.new(%{
          name: "my-agent",
          version: "1.0.0",
          capabilities: [
            %{name: "web_search", type: :tool},
            %{name: "file_read", type: :file_access}
          ]
        })

      assert length(manifest.capabilities) == 2
      assert Enum.all?(manifest.capabilities, &match?(%Capability{}, &1))
    end

    test "returns error when name is missing" do
      result = Manifest.new(%{version: "1.0.0"})

      assert {:error, error} = result
      assert error.code == :validation_error
      assert error.message =~ "name"
    end

    test "returns error when name is empty" do
      result = Manifest.new(%{name: "", version: "1.0.0"})

      assert {:error, error} = result
      assert error.code == :validation_error
    end

    test "returns error when version is missing" do
      result = Manifest.new(%{name: "my-agent"})

      assert {:error, error} = result
      assert error.code == :validation_error
      assert error.message =~ "version"
    end

    test "returns error when version is empty" do
      result = Manifest.new(%{name: "my-agent", version: ""})

      assert {:error, error} = result
      assert error.code == :validation_error
    end

    test "returns error when capability in list is invalid" do
      result =
        Manifest.new(%{
          name: "my-agent",
          version: "1.0.0",
          capabilities: [%{name: "", type: :tool}]
        })

      assert {:error, error} = result
      assert error.code == :validation_error
    end
  end

  describe "Manifest.add_capability/2" do
    test "adds a capability to the manifest" do
      {:ok, manifest} = Manifest.new(%{name: "my-agent", version: "1.0.0"})
      {:ok, capability} = Capability.new(%{name: "web_search", type: :tool})

      {:ok, updated} = Manifest.add_capability(manifest, capability)

      assert length(updated.capabilities) == 1
      assert hd(updated.capabilities).name == "web_search"
    end

    test "adds capability from map" do
      {:ok, manifest} = Manifest.new(%{name: "my-agent", version: "1.0.0"})

      {:ok, updated} = Manifest.add_capability(manifest, %{name: "web_search", type: :tool})

      assert length(updated.capabilities) == 1
    end

    test "returns error for duplicate capability name" do
      {:ok, manifest} =
        Manifest.new(%{
          name: "my-agent",
          version: "1.0.0",
          capabilities: [%{name: "web_search", type: :tool}]
        })

      result = Manifest.add_capability(manifest, %{name: "web_search", type: :tool})

      assert {:error, error} = result
      assert error.code == :duplicate_capability
    end
  end

  describe "Manifest.remove_capability/2" do
    test "removes a capability by name" do
      {:ok, manifest} =
        Manifest.new(%{
          name: "my-agent",
          version: "1.0.0",
          capabilities: [
            %{name: "web_search", type: :tool},
            %{name: "file_read", type: :file_access}
          ]
        })

      {:ok, updated} = Manifest.remove_capability(manifest, "web_search")

      assert length(updated.capabilities) == 1
      assert hd(updated.capabilities).name == "file_read"
    end

    test "returns error when capability not found" do
      {:ok, manifest} = Manifest.new(%{name: "my-agent", version: "1.0.0"})

      result = Manifest.remove_capability(manifest, "nonexistent")

      assert {:error, error} = result
      assert error.code == :capability_not_found
    end
  end

  describe "Manifest.get_capability/2" do
    test "gets a capability by name" do
      {:ok, manifest} =
        Manifest.new(%{
          name: "my-agent",
          version: "1.0.0",
          capabilities: [%{name: "web_search", type: :tool}]
        })

      {:ok, capability} = Manifest.get_capability(manifest, "web_search")

      assert capability.name == "web_search"
      assert capability.type == :tool
    end

    test "returns error when capability not found" do
      {:ok, manifest} = Manifest.new(%{name: "my-agent", version: "1.0.0"})

      result = Manifest.get_capability(manifest, "nonexistent")

      assert {:error, error} = result
      assert error.code == :capability_not_found
    end
  end

  describe "Manifest.enabled_capabilities/1" do
    test "returns only enabled capabilities" do
      {:ok, cap1} = Capability.new(%{name: "web_search", type: :tool, enabled: true})
      {:ok, cap2} = Capability.new(%{name: "file_read", type: :file_access, enabled: false})
      {:ok, cap3} = Capability.new(%{name: "code_exec", type: :code_execution, enabled: true})

      {:ok, manifest} =
        Manifest.new(%{
          name: "my-agent",
          version: "1.0.0",
          capabilities: [cap1, cap2, cap3]
        })

      enabled = Manifest.enabled_capabilities(manifest)

      assert length(enabled) == 2
      assert Enum.all?(enabled, & &1.enabled)
      refute Enum.any?(enabled, &(&1.name == "file_read"))
    end
  end

  describe "Manifest.to_map/1" do
    test "converts manifest to a map for JSON serialization" do
      {:ok, manifest} =
        Manifest.new(%{
          name: "my-agent",
          version: "1.0.0",
          description: "A helpful agent",
          provider: "anthropic",
          config: %{model: "claude-3"},
          capabilities: [%{name: "web_search", type: :tool}]
        })

      map = Manifest.to_map(manifest)

      assert is_map(map)
      assert map["name"] == "my-agent"
      assert map["version"] == "1.0.0"
      assert map["description"] == "A helpful agent"
      assert map["provider"] == "anthropic"
      assert map["config"] == %{"model" => "claude-3"}
      assert is_list(map["capabilities"])
      assert length(map["capabilities"]) == 1
      assert hd(map["capabilities"])["name"] == "web_search"
    end
  end

  describe "Manifest.from_map/1" do
    test "reconstructs a manifest from a map" do
      {:ok, original} =
        Manifest.new(%{
          name: "my-agent",
          version: "1.0.0",
          description: "A helpful agent",
          capabilities: [%{name: "web_search", type: :tool}]
        })

      map = Manifest.to_map(original)
      {:ok, restored} = Manifest.from_map(map)

      assert restored.name == original.name
      assert restored.version == original.version
      assert restored.description == original.description
      assert length(restored.capabilities) == 1
      assert hd(restored.capabilities).name == "web_search"
    end

    test "returns error for invalid map" do
      result = Manifest.from_map(%{})

      assert {:error, error} = result
      assert error.code == :validation_error
    end
  end
end
