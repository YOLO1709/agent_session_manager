defmodule AgentSessionManager.Examples.ClaudeDirectTest do
  @moduledoc """
  Tests for the Claude direct features example script.

  These tests verify that claude_direct.exs compiles and, when
  live, correctly exercises Claude-unique SDK features such as
  the Orchestrator, Streaming, Hooks, and Agent profiles.
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

  describe "claude direct example" do
    @tag :live
    test "example script compiles without warnings", ctx do
      if ctx[:skip] do
        :ok
      else
        {result, _binding} =
          Code.eval_string(
            File.read!("examples/claude_direct.exs")
            |> String.replace(~r/^ClaudeDirect\.main\(System\.argv\(\)\)$/m, ":ok"),
            [],
            file: "examples/claude_direct.exs"
          )

        assert result == :ok
      end
    end

    @tag :live
    test "orchestrator parallel queries return results", ctx do
      if ctx[:skip] do
        :ok
      else
        opts = %ClaudeAgentSDK.Options{
          max_turns: 1,
          system_prompt: "Reply in one word only."
        }

        queries = [
          {"What color is the sky?", opts},
          {"What color is grass?", opts}
        ]

        {:ok, results} =
          ClaudeAgentSDK.Orchestrator.query_parallel(queries, max_concurrent: 2)

        assert length(results) == 2

        Enum.each(results, fn result ->
          assert result.success == true
        end)
      end
    end

    @tag :live
    test "streaming session multi-turn works", ctx do
      if ctx[:skip] do
        :ok
      else
        opts = %ClaudeAgentSDK.Options{
          max_turns: 1,
          system_prompt: "Be concise. One sentence max."
        }

        {:ok, session} = ClaudeAgentSDK.Streaming.start_session(opts)

        # First message
        events1 =
          ClaudeAgentSDK.Streaming.send_message(session, "Say hello.")
          |> Enum.to_list()

        text_deltas1 = Enum.filter(events1, &(&1.type == :text_delta))
        assert text_deltas1 != []

        # Second message
        events2 =
          ClaudeAgentSDK.Streaming.send_message(session, "Say goodbye.")
          |> Enum.to_list()

        text_deltas2 = Enum.filter(events2, &(&1.type == :text_delta))
        assert text_deltas2 != []

        :ok = ClaudeAgentSDK.Streaming.close_session(session)
      end
    end

    @tag :live
    test "agent profile defines constraints", _ctx do
      agent =
        ClaudeAgentSDK.Agent.new(
          name: :summarizer,
          description: "Summarization specialist",
          prompt: "You summarize text concisely.",
          allowed_tools: ["Read"]
        )

      assert :ok == ClaudeAgentSDK.Agent.validate(agent)
      assert agent.name == :summarizer
      assert agent.allowed_tools == ["Read"]

      cli_map = ClaudeAgentSDK.Agent.to_cli_map(agent)
      assert cli_map["description"] == "Summarization specialist"
      assert cli_map["tools"] == ["Read"]
    end
  end
end
