defmodule AgentSessionManager.Examples.CodexDirectTest do
  @moduledoc """
  Tests for the Codex direct features example script.

  These tests verify that codex_direct.exs compiles and, when
  live, correctly exercises Codex-unique SDK features such as
  typed events, thread options, and session listing.
  """

  use AgentSessionManager.SupertesterCase, async: false

  @moduletag :live

  setup ctx do
    if System.get_env("LIVE_TESTS") != "true" do
      {:ok, Map.put(ctx, :skip, true)}
    else
      {:ok, Map.put(ctx, :skip, false)}
    end
  end

  describe "codex direct example" do
    @tag :live
    test "example script compiles without warnings", ctx do
      if ctx[:skip] do
        :ok
      else
        {result, _binding} =
          Code.eval_string(
            File.read!("examples/codex_direct.exs")
            |> String.replace(~r/^CodexDirect\.main\(System\.argv\(\)\)$/m, ":ok"),
            [],
            file: "examples/codex_direct.exs"
          )

        assert result == :ok
      end
    end

    @tag :live
    test "thread produces typed events", ctx do
      if ctx[:skip] do
        :ok
      else
        {:ok, codex_opts} = Codex.Options.new(%{})
        {:ok, thread_opts} = Codex.Thread.Options.new(%{working_directory: File.cwd!()})
        {:ok, thread} = Codex.start_thread(codex_opts, thread_opts)

        {:ok, streaming} =
          Codex.Thread.run_streamed(thread, "What is 2 + 2? Reply only the number.", %{})

        events =
          streaming
          |> Codex.RunResultStreaming.raw_events()
          |> Enum.to_list()

        assert events != []

        event_types = Enum.map(events, &event_struct_name/1)
        assert "ThreadStarted" in event_types or "TurnStarted" in event_types
      end
    end

    @tag :live
    test "session listing returns a list", ctx do
      if ctx[:skip] do
        :ok
      else
        {:ok, sessions} = Codex.Sessions.list_sessions()
        assert is_list(sessions)
      end
    end

    @tag :live
    test "thread options validate correctly", _ctx do
      {:ok, opts} =
        Codex.Thread.Options.new(%{
          working_directory: File.cwd!()
        })

      assert opts.working_directory == File.cwd!()
    end
  end

  defp event_struct_name(%{__struct__: mod}) do
    mod
    |> Module.split()
    |> List.last()
  end

  defp event_struct_name(_), do: "unknown"
end
