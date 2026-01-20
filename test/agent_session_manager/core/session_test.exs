defmodule AgentSessionManager.Core.SessionTest do
  use AgentSessionManager.SupertesterCase, async: true

  alias AgentSessionManager.Core.Session

  describe "Session struct" do
    test "defines required fields" do
      session = %Session{}

      # Required fields should exist (will be nil by default)
      assert Map.has_key?(session, :id)
      assert Map.has_key?(session, :agent_id)
      assert Map.has_key?(session, :status)
      assert Map.has_key?(session, :created_at)
      assert Map.has_key?(session, :updated_at)
    end

    test "defines optional fields" do
      session = %Session{}

      # Optional/metadata fields
      assert Map.has_key?(session, :parent_session_id)
      assert Map.has_key?(session, :metadata)
      assert Map.has_key?(session, :context)
      assert Map.has_key?(session, :tags)
    end

    test "has default values for optional fields" do
      session = %Session{}

      assert session.metadata == %{}
      assert session.context == %{}
      assert session.tags == []
      assert session.parent_session_id == nil
    end

    test "status has default value of :pending" do
      session = %Session{}
      assert session.status == :pending
    end
  end

  describe "Session.new/1" do
    test "creates a session with required fields" do
      {:ok, session} = Session.new(%{agent_id: "agent-123"})

      assert session.agent_id == "agent-123"
      assert session.id != nil
      assert is_binary(session.id)
      assert session.status == :pending
      assert session.created_at != nil
      assert session.updated_at != nil
    end

    test "generates a unique ID" do
      {:ok, session1} = Session.new(%{agent_id: "agent-123"})
      {:ok, session2} = Session.new(%{agent_id: "agent-123"})

      refute session1.id == session2.id
    end

    test "allows custom ID" do
      {:ok, session} = Session.new(%{id: "custom-id", agent_id: "agent-123"})

      assert session.id == "custom-id"
    end

    test "accepts optional metadata" do
      {:ok, session} =
        Session.new(%{
          agent_id: "agent-123",
          metadata: %{user: "test-user", purpose: "testing"}
        })

      assert session.metadata == %{user: "test-user", purpose: "testing"}
    end

    test "accepts optional context" do
      {:ok, session} =
        Session.new(%{
          agent_id: "agent-123",
          context: %{system_prompt: "You are a helpful assistant"}
        })

      assert session.context == %{system_prompt: "You are a helpful assistant"}
    end

    test "accepts optional tags" do
      {:ok, session} =
        Session.new(%{
          agent_id: "agent-123",
          tags: ["test", "development"]
        })

      assert session.tags == ["test", "development"]
    end

    test "accepts parent_session_id for hierarchical sessions" do
      {:ok, parent} = Session.new(%{agent_id: "agent-parent"})

      {:ok, child} =
        Session.new(%{
          agent_id: "agent-child",
          parent_session_id: parent.id
        })

      assert child.parent_session_id == parent.id
    end

    test "returns error when agent_id is missing" do
      result = Session.new(%{})

      assert {:error, error} = result
      assert error.code == :validation_error
      assert error.message =~ "agent_id"
    end

    test "returns error when agent_id is empty" do
      result = Session.new(%{agent_id: ""})

      assert {:error, error} = result
      assert error.code == :validation_error
    end
  end

  describe "Session status transitions" do
    test "valid status values" do
      valid_statuses = [:pending, :active, :paused, :completed, :failed, :cancelled]

      for status <- valid_statuses do
        {:ok, session} = Session.new(%{agent_id: "agent-123"})
        {:ok, updated} = Session.update_status(session, status)
        assert updated.status == status
      end
    end

    test "rejects invalid status values" do
      {:ok, session} = Session.new(%{agent_id: "agent-123"})
      result = Session.update_status(session, :invalid_status)

      assert {:error, error} = result
      assert error.code == :invalid_status
    end

    test "updates updated_at timestamp on status change" do
      {:ok, session} = Session.new(%{agent_id: "agent-123"})
      original_updated_at = session.updated_at

      # Small delay to ensure timestamp difference
      Process.sleep(1)

      {:ok, updated} = Session.update_status(session, :active)

      assert DateTime.compare(updated.updated_at, original_updated_at) == :gt
    end
  end

  describe "Session.to_map/1" do
    test "converts session to a map for JSON serialization" do
      {:ok, session} =
        Session.new(%{
          agent_id: "agent-123",
          metadata: %{key: "value"},
          tags: ["test"]
        })

      map = Session.to_map(session)

      assert is_map(map)
      assert map["id"] == session.id
      assert map["agent_id"] == "agent-123"
      assert map["status"] == "pending"
      assert map["metadata"] == %{"key" => "value"}
      assert map["tags"] == ["test"]
      assert is_binary(map["created_at"])
      assert is_binary(map["updated_at"])
    end
  end

  describe "Session.from_map/1" do
    test "reconstructs a session from a map" do
      {:ok, original} =
        Session.new(%{
          agent_id: "agent-123",
          metadata: %{key: "value"},
          tags: ["test"]
        })

      map = Session.to_map(original)
      {:ok, restored} = Session.from_map(map)

      assert restored.id == original.id
      assert restored.agent_id == original.agent_id
      assert restored.status == original.status
      assert restored.metadata == original.metadata
      assert restored.tags == original.tags
    end

    test "returns error for invalid map" do
      result = Session.from_map(%{})

      assert {:error, error} = result
      assert error.code == :validation_error
    end
  end
end
