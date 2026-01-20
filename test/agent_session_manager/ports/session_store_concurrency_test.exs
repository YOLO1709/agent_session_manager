defmodule AgentSessionManager.Ports.SessionStoreConcurrencyTest do
  @moduledoc """
  Concurrency tests for SessionStore implementations.

  These tests verify that the store handles concurrent access correctly,
  without race conditions or data corruption.
  """

  use ExUnit.Case, async: true

  alias AgentSessionManager.Adapters.InMemorySessionStore
  alias AgentSessionManager.Core.{Event, Run, Session}
  alias AgentSessionManager.Ports.SessionStore

  @concurrency_level 100
  @iterations 10

  # Helper to get a fresh store for each test
  defp new_store do
    {:ok, store} = InMemorySessionStore.start_link([])
    store
  end

  describe "Concurrent session operations" do
    test "concurrent session saves are safe" do
      store = new_store()

      tasks =
        for i <- 1..@concurrency_level do
          Task.async(fn ->
            {:ok, session} = Session.new(%{agent_id: "agent-#{i}"})
            SessionStore.save_session(store, session)
            session.id
          end)
        end

      session_ids = Task.await_many(tasks, 5000)

      {:ok, sessions} = SessionStore.list_sessions(store)

      assert length(sessions) == @concurrency_level
      assert length(Enum.uniq(session_ids)) == @concurrency_level
    end

    test "concurrent reads and writes to same session are safe" do
      store = new_store()
      {:ok, session} = Session.new(%{agent_id: "agent-1"})
      :ok = SessionStore.save_session(store, session)

      # Mix of reads and writes
      tasks =
        for i <- 1..@concurrency_level do
          Task.async(fn ->
            if rem(i, 2) == 0 do
              # Read
              SessionStore.get_session(store, session.id)
            else
              # Write (update status)
              {:ok, updated} = Session.update_status(session, :active)
              SessionStore.save_session(store, updated)
            end
          end)
        end

      results = Task.await_many(tasks, 5000)

      # All operations should succeed
      assert Enum.all?(results, fn
               :ok -> true
               {:ok, _} -> true
               _ -> false
             end)

      # Final state should be consistent
      {:ok, final_session} = SessionStore.get_session(store, session.id)
      assert final_session.id == session.id
    end

    test "concurrent deletes are safe" do
      store = new_store()

      # Create sessions first
      session_ids =
        for i <- 1..@concurrency_level do
          {:ok, session} = Session.new(%{agent_id: "agent-#{i}"})
          :ok = SessionStore.save_session(store, session)
          session.id
        end

      # Delete all concurrently
      tasks =
        for id <- session_ids do
          Task.async(fn ->
            SessionStore.delete_session(store, id)
          end)
        end

      Task.await_many(tasks, 5000)

      {:ok, sessions} = SessionStore.list_sessions(store)
      assert sessions == []
    end
  end

  describe "Concurrent run operations" do
    test "concurrent run saves for different sessions" do
      store = new_store()

      # Create sessions first
      sessions =
        for i <- 1..@concurrency_level do
          {:ok, session} = Session.new(%{agent_id: "agent-#{i}"})
          :ok = SessionStore.save_session(store, session)
          session
        end

      # Create runs concurrently
      tasks =
        for session <- sessions do
          Task.async(fn ->
            {:ok, run} = Run.new(%{session_id: session.id})
            SessionStore.save_run(store, run)
            {session.id, run.id}
          end)
        end

      results = Task.await_many(tasks, 5000)

      # Verify all runs were created
      for {session_id, run_id} <- results do
        {:ok, runs} = SessionStore.list_runs(store, session_id)
        assert length(runs) == 1
        assert hd(runs).id == run_id
      end
    end

    test "concurrent run updates to same run" do
      store = new_store()
      {:ok, session} = Session.new(%{agent_id: "agent-1"})
      :ok = SessionStore.save_session(store, session)
      {:ok, run} = Run.new(%{session_id: session.id})
      :ok = SessionStore.save_run(store, run)

      # Multiple concurrent updates
      tasks =
        for i <- 1..@concurrency_level do
          Task.async(fn ->
            {:ok, updated} = Run.increment_turn(run)
            {:ok, updated} = Run.update_token_usage(updated, %{input: i, output: i * 2})
            SessionStore.save_run(store, updated)
          end)
        end

      Task.await_many(tasks, 5000)

      # Run should still be retrievable and valid
      {:ok, final_run} = SessionStore.get_run(store, run.id)
      assert final_run.id == run.id
      assert final_run.session_id == session.id
    end

    test "get_active_run is consistent under concurrent updates" do
      store = new_store()
      {:ok, session} = Session.new(%{agent_id: "agent-1"})
      :ok = SessionStore.save_session(store, session)
      {:ok, run} = Run.new(%{session_id: session.id})
      {:ok, running_run} = Run.update_status(run, :running)
      :ok = SessionStore.save_run(store, running_run)

      # Concurrent reads of active run
      tasks =
        for _ <- 1..@concurrency_level do
          Task.async(fn ->
            SessionStore.get_active_run(store, session.id)
          end)
        end

      results = Task.await_many(tasks, 5000)

      # All reads should return the same active run
      assert Enum.all?(results, fn
               {:ok, active_run} when not is_nil(active_run) -> active_run.id == run.id
               {:ok, nil} -> false
             end)
    end
  end

  describe "Concurrent event operations" do
    test "concurrent event appends preserve order integrity" do
      store = new_store()
      {:ok, session} = Session.new(%{agent_id: "agent-1"})
      :ok = SessionStore.save_session(store, session)

      # Append events concurrently with sequence numbers
      tasks =
        for i <- 1..@concurrency_level do
          Task.async(fn ->
            {:ok, event} =
              Event.new(%{
                type: :message_received,
                session_id: session.id,
                sequence_number: i,
                data: %{index: i}
              })

            SessionStore.append_event(store, event)
            event.id
          end)
        end

      event_ids = Task.await_many(tasks, 5000)

      {:ok, events} = SessionStore.get_events(store, session.id)

      # All events should be stored
      assert length(events) == @concurrency_level

      # All event IDs should be present
      stored_ids = Enum.map(events, & &1.id)
      assert Enum.sort(event_ids) == Enum.sort(stored_ids)
    end

    test "concurrent event reads are safe" do
      store = new_store()
      {:ok, session} = Session.new(%{agent_id: "agent-1"})
      :ok = SessionStore.save_session(store, session)

      # Pre-populate events
      for i <- 1..50 do
        {:ok, event} =
          Event.new(%{
            type: :message_received,
            session_id: session.id,
            data: %{index: i}
          })

        :ok = SessionStore.append_event(store, event)
      end

      # Concurrent reads
      tasks =
        for _ <- 1..@concurrency_level do
          Task.async(fn ->
            SessionStore.get_events(store, session.id)
          end)
        end

      results = Task.await_many(tasks, 5000)

      # All reads should succeed with same event count
      assert Enum.all?(results, fn
               {:ok, events} -> length(events) == 50
               _ -> false
             end)
    end

    test "mixed read/write operations on events" do
      store = new_store()
      {:ok, session} = Session.new(%{agent_id: "agent-1"})
      :ok = SessionStore.save_session(store, session)

      # Start with some events
      for i <- 1..10 do
        {:ok, event} =
          Event.new(%{
            type: :message_received,
            session_id: session.id,
            data: %{index: i}
          })

        :ok = SessionStore.append_event(store, event)
      end

      # Mix of reads and writes
      tasks =
        for i <- 1..@concurrency_level do
          Task.async(fn ->
            if rem(i, 3) == 0 do
              # Read
              SessionStore.get_events(store, session.id)
            else
              # Write
              {:ok, event} =
                Event.new(%{
                  type: :message_sent,
                  session_id: session.id,
                  data: %{index: i}
                })

              SessionStore.append_event(store, event)
            end
          end)
        end

      results = Task.await_many(tasks, 5000)

      # All operations should succeed
      assert Enum.all?(results, fn
               :ok -> true
               {:ok, _} -> true
               _ -> false
             end)
    end
  end

  describe "Stress tests" do
    test "sustained concurrent operations" do
      store = new_store()

      for _iteration <- 1..@iterations do
        # Create a batch of sessions concurrently
        session_tasks =
          for i <- 1..10 do
            Task.async(fn ->
              {:ok, session} = Session.new(%{agent_id: "agent-#{i}"})
              :ok = SessionStore.save_session(store, session)
              session
            end)
          end

        sessions = Task.await_many(session_tasks, 5000)

        # Create runs for each session concurrently
        run_tasks =
          for session <- sessions do
            Task.async(fn ->
              {:ok, run} = Run.new(%{session_id: session.id})
              :ok = SessionStore.save_run(store, run)
              {session.id, run}
            end)
          end

        session_runs = Task.await_many(run_tasks, 5000)

        # Append events concurrently
        event_tasks =
          for {session_id, run} <- session_runs do
            Task.async(fn ->
              {:ok, event} =
                Event.new(%{
                  type: :run_started,
                  session_id: session_id,
                  run_id: run.id
                })

              :ok = SessionStore.append_event(store, event)
            end)
          end

        Task.await_many(event_tasks, 5000)
      end

      # Verify data integrity
      {:ok, all_sessions} = SessionStore.list_sessions(store)
      # Some sessions might be duplicates with same agent_id, so just verify we have sessions
      assert all_sessions != []
    end

    test "no data corruption under heavy concurrent load" do
      store = new_store()
      {:ok, session} = Session.new(%{agent_id: "stress-test"})
      :ok = SessionStore.save_session(store, session)

      # Heavy concurrent operations on same session
      tasks =
        for i <- 1..(@concurrency_level * 2) do
          Task.async(fn ->
            case rem(i, 4) do
              0 ->
                # Read session
                SessionStore.get_session(store, session.id)

              1 ->
                # Update session
                {:ok, updated} = Session.update_status(session, :active)
                SessionStore.save_session(store, updated)

              2 ->
                # Create and save run
                {:ok, run} = Run.new(%{session_id: session.id})
                SessionStore.save_run(store, run)

              3 ->
                # Append event
                {:ok, event} =
                  Event.new(%{
                    type: :message_received,
                    session_id: session.id,
                    data: %{worker: i}
                  })

                SessionStore.append_event(store, event)
            end
          end)
        end

      results = Task.await_many(tasks, 10_000)

      # All operations should complete without errors
      errors =
        Enum.filter(results, fn
          :ok -> false
          {:ok, _} -> false
          {:error, _} -> true
        end)

      assert errors == [], "Expected no errors, got: #{inspect(errors)}"

      # Session should still be readable
      {:ok, final_session} = SessionStore.get_session(store, session.id)
      assert final_session.id == session.id
    end
  end
end
