defmodule AgentSessionManager.SupertesterCase do
  @moduledoc """
  Shared test infrastructure using Supertester for robust OTP testing.

  This module provides a drop-in replacement for `ExUnit.Case` that integrates
  Supertester's isolation, deterministic synchronization, and assertions.

  ## Usage

      defmodule MyTest do
        use AgentSessionManager.SupertesterCase, async: true

        test "my test", ctx do
          # ctx.isolation_context contains supertester isolation info
          {:ok, store} = setup_test_store(ctx)
          # ...
        end
      end

  ## Features

  - Full process isolation via Supertester.ExUnitFoundation
  - Automatic cleanup of GenServers started with setup helpers
  - Deterministic async testing with cast_and_sync patterns
  - Built-in assertions for GenServer state and process lifecycle
  - Telemetry isolation for async-safe telemetry testing
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      use Supertester.ExUnitFoundation, isolation: :full_isolation

      import Supertester.OTPHelpers
      import Supertester.GenServerHelpers
      import Supertester.Assertions

      alias AgentSessionManager.Adapters.InMemorySessionStore
      alias AgentSessionManager.Core.{Capability, Error, Event, Run, Session}
      alias AgentSessionManager.Ports.SessionStore
      alias AgentSessionManager.Test.{Fixtures, MockProviderAdapter}

      @doc """
      Sets up an isolated InMemorySessionStore for the test.

      Returns `{:ok, store_pid}` with automatic cleanup registered.
      """
      @spec setup_test_store(map()) :: {:ok, pid()}
      def setup_test_store(_ctx \\ %{}) do
        {:ok, store} = InMemorySessionStore.start_link([])

        on_exit(fn ->
          if Process.alive?(store), do: GenServer.stop(store, :normal)
        end)

        {:ok, store}
      end

      @doc """
      Sets up an isolated MockProviderAdapter for the test.

      ## Options

        * `:capabilities` - List of capabilities (default: full_claude)
        * `:execution_mode` - Execution mode (default: :instant)
        * `:responses` - Map of response overrides

      Returns `{:ok, adapter_pid}` with automatic cleanup registered.
      """
      @spec setup_test_adapter(map(), keyword()) :: {:ok, pid()}
      def setup_test_adapter(_ctx \\ %{}, opts \\ []) do
        adapter_opts =
          Keyword.merge(
            [
              capabilities: Fixtures.provider_capabilities(:full_claude),
              execution_mode: :instant
            ],
            opts
          )

        {:ok, adapter} = MockProviderAdapter.start_link(adapter_opts)

        on_exit(fn ->
          if Process.alive?(adapter), do: MockProviderAdapter.stop(adapter)
        end)

        {:ok, adapter}
      end

      @doc """
      Sets up both store and adapter for the test.

      Returns `{:ok, %{store: store_pid, adapter: adapter_pid}}`.
      """
      @spec setup_test_infrastructure(map(), keyword()) :: {:ok, map()}
      def setup_test_infrastructure(ctx \\ %{}, opts \\ []) do
        {:ok, store} = setup_test_store(ctx)
        {:ok, adapter} = setup_test_adapter(ctx, opts)
        {:ok, %{store: store, adapter: adapter}}
      end

      @doc """
      Creates a test session with the given options.

      This is a helper that creates a session through the fixture system
      but doesn't persist it.
      """
      @spec build_test_session(keyword()) :: Session.t()
      def build_test_session(opts \\ []) do
        Fixtures.build_session(opts)
      end

      @doc """
      Creates a test run with the given options.
      """
      @spec build_test_run(keyword()) :: Run.t()
      def build_test_run(opts \\ []) do
        Fixtures.build_run(opts)
      end

      @doc """
      Waits for a GenServer to be ready and responsive.

      Uses Supertester's sync mechanism for deterministic testing.
      """
      @spec wait_for_server_ready(GenServer.server(), timeout()) :: :ok | {:error, term()}
      def wait_for_server_ready(server, timeout \\ 5000) do
        Supertester.OTPHelpers.wait_for_genserver_sync(server, timeout)
      end

      @doc """
      Asserts that a process is alive and responsive.
      """
      @spec assert_server_alive(pid() | GenServer.server()) :: :ok
      def assert_server_alive(server) when is_pid(server) do
        assert Process.alive?(server), "Expected process #{inspect(server)} to be alive"
        :ok
      end

      def assert_server_alive(server) do
        pid = GenServer.whereis(server)
        assert pid != nil, "Expected server #{inspect(server)} to be registered"
        assert Process.alive?(pid), "Expected server #{inspect(server)} to be alive"
        :ok
      end

      @doc """
      Asserts that all processes in a list are alive.
      """
      @spec assert_all_servers_alive([pid() | GenServer.server()]) :: :ok
      def assert_all_servers_alive(servers) do
        Enum.each(servers, &assert_server_alive/1)
        :ok
      end

      @doc """
      Safely stops a GenServer, catching exit errors.
      """
      @spec safe_stop(pid() | GenServer.server()) :: :ok
      def safe_stop(server) do
        try do
          if is_pid(server) and Process.alive?(server) do
            GenServer.stop(server, :normal)
          end
        catch
          :exit, _ -> :ok
        end

        :ok
      end

      @doc """
      Runs a function concurrently with the given number of tasks.

      Returns all results.
      """
      @spec run_concurrent(pos_integer(), (integer() -> term()), timeout()) :: [term()]
      def run_concurrent(count, fun, timeout \\ 5000) do
        tasks =
          for i <- 1..count do
            Task.async(fn -> fun.(i) end)
          end

        Task.await_many(tasks, timeout)
      end

      @doc """
      Asserts that all results match the expected pattern.
      """
      defmacro assert_all_match(results, pattern) do
        quote do
          Enum.each(unquote(results), fn result ->
            assert match?(unquote(pattern), result),
                   "Expected #{inspect(result)} to match #{unquote(Macro.to_string(pattern))}"
          end)
        end
      end

      @doc """
      Collects messages matching a pattern within a timeout.
      """
      @spec collect_messages(timeout()) :: [term()]
      def collect_messages(timeout_ms \\ 100) do
        collect_messages_acc([], timeout_ms)
      end

      defp collect_messages_acc(acc, timeout_ms) do
        receive do
          msg -> collect_messages_acc([msg | acc], timeout_ms)
        after
          timeout_ms -> Enum.reverse(acc)
        end
      end
    end
  end

  setup tags do
    # Allow tests to opt out of telemetry isolation
    if Map.get(tags, :telemetry_isolation, false) do
      {:ok, _} = Supertester.TelemetryHelpers.setup_telemetry_isolation()
    end

    :ok
  end
end
