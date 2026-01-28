defmodule ClaudeDirect do
  @moduledoc false

  # Demonstrates Claude SDK unique features accessed directly via ClaudeAgentSDK.
  #
  # Sections:
  #   orchestrator - Parallel queries and retry
  #   streaming    - Bidirectional streaming sessions
  #   hooks        - Pre-tool-use hooks for logging
  #   agent        - Constrained agent profiles
  #   all          - Run all sections (default)

  alias ClaudeAgentSDK.{Agent, ContentExtractor, Orchestrator, Options, Session, Streaming}
  alias ClaudeAgentSDK.Hooks.{Matcher, Output}

  @sections ~w(orchestrator streaming hooks agent all)

  # ============================================================================
  # Entry Point
  # ============================================================================

  @doc """
  Main entry point for the Claude direct features example.
  """
  def main(args) do
    section = parse_args(args)
    print_header(section)

    case check_auth() do
      :ok ->
        case run_sections(section) do
          :ok ->
            print_success("Claude direct example completed successfully!")
            System.halt(0)

          {:error, error} ->
            print_error("Example failed: #{format_error(error)}")
            System.halt(1)
        end

      {:error, reason} ->
        print_error("Authentication check failed: #{reason}")
        print_auth_instructions()
        System.halt(1)
    end
  end

  # ============================================================================
  # Command Line Argument Parsing
  # ============================================================================

  defp parse_args(args) do
    {opts, _rest, _invalid} =
      OptionParser.parse(args,
        strict: [section: :string, help: :boolean],
        aliases: [s: :section, h: :help]
      )

    if opts[:help] do
      print_usage()
      System.halt(0)
    end

    section = opts[:section] || "all"

    unless section in @sections do
      print_error("Unknown section: #{section}")
      print_usage()
      System.halt(1)
    end

    section
  end

  defp print_usage do
    IO.puts("""

    Usage: mix run examples/claude_direct.exs [options]

    Options:
      --section, -s <name>  Section to run (#{Enum.join(@sections, ", ")}). Default: all
      --help, -h            Show this help message

    Authentication:
      Run `claude login` or set ANTHROPIC_API_KEY

    Examples:
      mix run examples/claude_direct.exs
      mix run examples/claude_direct.exs --section orchestrator
      mix run examples/claude_direct.exs --section streaming
    """)
  end

  defp print_auth_instructions do
    IO.puts("""

    To authenticate with Claude:
      1. Install Claude Code: npm install -g @anthropic-ai/claude-code
      2. Run: claude login
      3. Or set: export ANTHROPIC_API_KEY=your_key_here
    """)
  end

  # ============================================================================
  # Authentication
  # ============================================================================

  defp check_auth do
    if ClaudeAgentSDK.AuthChecker.authenticated?() do
      :ok
    else
      {:error, "Claude is not authenticated"}
    end
  end

  # ============================================================================
  # Section Router
  # ============================================================================

  defp run_sections("all") do
    sections = ["orchestrator", "streaming", "hooks", "agent"]

    Enum.reduce_while(sections, :ok, fn section, _acc ->
      case run_section(section) do
        :ok -> {:cont, :ok}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp run_sections(section), do: run_section(section)

  defp run_section("orchestrator"), do: run_orchestrator()
  defp run_section("streaming"), do: run_streaming()
  defp run_section("hooks"), do: run_hooks()
  defp run_section("agent"), do: run_agent()

  # ============================================================================
  # Section: Orchestrator
  # ============================================================================

  defp run_orchestrator do
    print_section("Orchestrator - Parallel Queries & Retry")

    opts = %Options{
      max_turns: 1,
      system_prompt: "Answer in one concise sentence."
    }

    queries = [
      {"What is Elixir?", opts},
      {"What is OTP?", opts},
      {"What is Phoenix?", opts}
    ]

    # Parallel execution
    print_step(1, "Parallel query execution (3 queries, max_concurrent: 2)")

    case Orchestrator.query_parallel(queries, max_concurrent: 2) do
      {:ok, results} ->
        Enum.each(results, fn result ->
          label = result.prompt
          text = ContentExtractor.extract_all_text(result.messages, " ")
          success = if result.success, do: "OK", else: "FAIL"
          print_info("[#{success}] #{label}")
          IO.puts("    #{String.slice(text, 0, 120)}")
        end)

        total_cost =
          results
          |> Enum.map(& &1.cost)
          |> Enum.sum()

        print_info("Total cost: $#{Float.round(total_cost, 6)}")

      {:error, reason} ->
        print_error("Parallel queries failed: #{inspect(reason)}")
        throw({:error, reason})
    end

    # Retry
    print_step(2, "Query with retry (max_retries: 2)")

    case Orchestrator.query_with_retry(
           "What is the BEAM virtual machine? One sentence.",
           opts,
           max_retries: 2,
           backoff_ms: 500
         ) do
      {:ok, messages} ->
        text = ContentExtractor.extract_all_text(messages, " ")
        print_info("Response: #{String.slice(text, 0, 200)}")

        cost = Session.calculate_cost(messages)
        print_info("Cost: $#{Float.round(cost, 6)}")

      {:error, reason} ->
        print_error("Retry query failed: #{inspect(reason)}")
        throw({:error, reason})
    end

    :ok
  catch
    {:error, _reason} = error -> error
  end

  # ============================================================================
  # Section: Streaming
  # ============================================================================

  defp run_streaming do
    print_section("Streaming - Bidirectional Session")

    opts = %Options{
      max_turns: 1,
      system_prompt: "You are a poet. Keep responses to 2 lines."
    }

    print_step(1, "Starting streaming session")

    case Streaming.start_session(opts) do
      {:ok, session} ->
        # First message
        print_step(2, "Sending first message")
        print_info("Prompt: \"Tell me a haiku about Elixir\"")
        IO.puts("")
        IO.write("  ")

        Streaming.send_message(session, "Tell me a haiku about Elixir")
        |> Stream.each(fn event ->
          case event do
            %{type: :text_delta, text: text} ->
              IO.write(IO.ANSI.cyan() <> text <> IO.ANSI.reset())

            %{type: :message_stop} ->
              IO.puts("")

            _ ->
              :ok
          end
        end)
        |> Stream.run()

        IO.puts("")

        # Second message
        print_step(3, "Sending follow-up message")
        print_info("Prompt: \"Now one about OTP\"")
        IO.puts("")
        IO.write("  ")

        Streaming.send_message(session, "Now one about OTP")
        |> Stream.each(fn event ->
          case event do
            %{type: :text_delta, text: text} ->
              IO.write(IO.ANSI.cyan() <> text <> IO.ANSI.reset())

            %{type: :message_stop} ->
              IO.puts("")

            _ ->
              :ok
          end
        end)
        |> Stream.run()

        IO.puts("")

        # Session info
        print_step(4, "Session info")

        case Streaming.get_session_id(session) do
          {:ok, session_id} ->
            print_info("Session ID: #{session_id}")

          {:error, _reason} ->
            print_info("Session ID: (not available)")
        end

        :ok = Streaming.close_session(session)
        print_info("Session closed")
        :ok

      {:error, reason} ->
        print_error("Failed to start streaming session: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # ============================================================================
  # Section: Hooks
  # ============================================================================

  defp run_hooks do
    print_section("Hooks - Pre-Tool-Use Logging")

    hook_log = :ets.new(:hook_log, [:bag, :public])

    hook_fn = fn input, _tool_use_id, _context ->
      tool_name = input["tool_name"] || "unknown"
      :ets.insert(hook_log, {:hook_invocation, tool_name, DateTime.utc_now()})
      print_info("  Hook triggered: tool=#{tool_name}")
      Output.allow("Approved by example hook")
    end

    matcher = Matcher.new("*", [hook_fn])

    opts = %Options{
      max_turns: 5,
      system_prompt: "You are a helpful assistant.",
      hooks: %{pre_tool_use: [matcher]}
    }

    print_step(1, "Running query with hooks")
    print_info("Prompt: \"What files are in the current directory?\"")
    IO.puts("")

    messages =
      ClaudeAgentSDK.query("What files are in the current directory?", opts)
      |> Enum.to_list()

    IO.puts("")

    # Show hook invocations
    print_step(2, "Hook invocation summary")
    invocations = :ets.tab2list(hook_log)
    print_info("Total hook invocations: #{length(invocations)}")

    Enum.each(invocations, fn {:hook_invocation, tool_name, _ts} ->
      IO.puts("    Tool: #{tool_name}")
    end)

    :ets.delete(hook_log)

    # Show final message
    print_step(3, "Final response")
    text = ContentExtractor.extract_all_text(messages, " ")
    IO.puts("  #{String.slice(text, 0, 300)}")
    IO.puts("")

    :ok
  end

  # ============================================================================
  # Section: Agent
  # ============================================================================

  defp run_agent do
    print_section("Agent - Constrained Agent Profile")

    agent =
      Agent.new(
        name: :summarizer,
        description: "Text summarization specialist",
        prompt: "You are a summarization expert. Provide concise summaries only.",
        allowed_tools: ["Read"]
      )

    print_step(1, "Agent definition")
    print_info("Name: #{agent.name}")
    print_info("Description: #{agent.description}")
    print_info("Allowed tools: #{Enum.join(agent.allowed_tools, ", ")}")

    case Agent.validate(agent) do
      :ok ->
        print_info("Validation: passed")

      {:error, reason} ->
        print_error("Validation failed: #{reason}")
        throw({:error, reason})
    end

    # Show CLI representation
    print_step(2, "CLI representation")
    cli_map = Agent.to_cli_map(agent)

    Enum.each(cli_map, fn {key, value} ->
      IO.puts("    #{key}: #{inspect(value)}")
    end)

    # Run query with agent
    print_step(3, "Running query with agent profile")

    opts = %Options{
      max_turns: 1,
      system_prompt: agent.prompt,
      allowed_tools: agent.allowed_tools
    }

    messages =
      ClaudeAgentSDK.query("Summarize what Elixir is in one sentence.", opts)
      |> Enum.to_list()

    text = ContentExtractor.extract_all_text(messages, " ")
    print_info("Agent response: #{String.slice(text, 0, 200)}")

    :ok
  catch
    {:error, _reason} = error -> error
  end

  # ============================================================================
  # Output Formatting
  # ============================================================================

  defp print_header(section) do
    IO.puts("")
    IO.puts(IO.ANSI.bright() <> "AgentSessionManager - Claude Direct Features" <> IO.ANSI.reset())
    IO.puts(String.duplicate("=", 50))
    IO.puts("Section: #{section}")
    IO.puts(String.duplicate("=", 50))
    IO.puts("")
  end

  defp print_section(title) do
    IO.puts("")
    IO.puts(IO.ANSI.bright() <> IO.ANSI.magenta() <> title <> IO.ANSI.reset())
    IO.puts(String.duplicate("=", 50))
  end

  defp print_step(num, title) do
    IO.puts("")

    IO.puts(
      IO.ANSI.bright() <>
        IO.ANSI.blue() <> "Step #{num}: #{title}" <> IO.ANSI.reset()
    )

    IO.puts(String.duplicate("-", 40))
  end

  defp print_info(message) do
    IO.puts(IO.ANSI.green() <> "  [INFO] " <> IO.ANSI.reset() <> message)
  end

  defp print_error(message) do
    IO.puts(IO.ANSI.red() <> "  [ERROR] " <> IO.ANSI.reset() <> message)
  end

  defp print_success(message) do
    IO.puts("")
    IO.puts(IO.ANSI.bright() <> IO.ANSI.green() <> message <> IO.ANSI.reset())
    IO.puts("")
  end

  defp format_error(error) when is_binary(error), do: error
  defp format_error(error), do: inspect(error)
end

ClaudeDirect.main(System.argv())
