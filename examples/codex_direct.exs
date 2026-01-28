defmodule CodexDirect do
  @moduledoc false

  # Demonstrates Codex SDK unique features accessed directly via Codex.
  #
  # Sections:
  #   threads  - Thread lifecycle with typed events
  #   options  - Advanced thread options
  #   sessions - Session listing
  #   all      - Run all sections (default)

  alias Codex.Events
  alias Codex.Items

  @sections ~w(threads options sessions all)

  # ============================================================================
  # Entry Point
  # ============================================================================

  @doc """
  Main entry point for the Codex direct features example.
  """
  def main(args) do
    section = parse_args(args)
    print_header(section)

    case run_sections(section) do
      :ok ->
        print_success("Codex direct example completed successfully!")
        System.halt(0)

      {:error, error} ->
        print_error("Example failed: #{format_error(error)}")
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

    Usage: mix run examples/codex_direct.exs [options]

    Options:
      --section, -s <name>  Section to run (#{Enum.join(@sections, ", ")}). Default: all
      --help, -h            Show this help message

    Authentication:
      Run `codex login` or set CODEX_API_KEY / OPENAI_API_KEY

    Examples:
      mix run examples/codex_direct.exs
      mix run examples/codex_direct.exs --section threads
      mix run examples/codex_direct.exs --section sessions
    """)
  end

  # ============================================================================
  # Section Router
  # ============================================================================

  defp run_sections("all") do
    sections = ["threads", "options", "sessions"]

    Enum.reduce_while(sections, :ok, fn section, _acc ->
      case run_section(section) do
        :ok -> {:cont, :ok}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp run_sections(section), do: run_section(section)

  defp run_section("threads"), do: run_threads()
  defp run_section("options"), do: run_options()
  defp run_section("sessions"), do: run_sessions()

  # ============================================================================
  # Section: Threads (Typed Events)
  # ============================================================================

  defp run_threads do
    print_section("Threads - Typed Events & Items")

    print_step(1, "Starting thread")

    with {:ok, codex_opts} <- Codex.Options.new(%{}),
         {:ok, thread_opts} <- Codex.Thread.Options.new(%{working_directory: File.cwd!()}),
         {:ok, thread} <- Codex.start_thread(codex_opts, thread_opts) do
      print_info("Thread created")

      print_step(2, "Running streamed query")
      print_info("Prompt: \"What files are in this directory? List the first 5.\"")
      IO.puts("")

      case Codex.Thread.run_streamed(
             thread,
             "What files are in this directory? List the first 5.",
             %{}
           ) do
        {:ok, streaming} ->
          events =
            streaming
            |> Codex.RunResultStreaming.raw_events()
            |> Enum.map(fn event ->
              handle_typed_event(event)
              event
            end)

          IO.puts("")

          # Summary
          print_step(3, "Event summary")
          print_info("Total events: #{length(events)}")

          event_types =
            events
            |> Enum.map(&event_struct_name/1)
            |> Enum.frequencies()
            |> Enum.sort_by(fn {_name, count} -> -count end)

          Enum.each(event_types, fn {name, count} ->
            IO.puts("    #{name}: #{count}")
          end)

          # Show final response if available
          print_step(4, "Final response inspection")

          turn_completed =
            Enum.find(events, fn
              %Events.TurnCompleted{} -> true
              _ -> false
            end)

          if turn_completed do
            case turn_completed.final_response do
              %Items.AgentMessage{text: text} when is_binary(text) ->
                print_info("AgentMessage text: #{String.slice(text, 0, 200)}")

              %{"text" => text} when is_binary(text) ->
                print_info("Response text: #{String.slice(text, 0, 200)}")

              other ->
                print_info("Final response type: #{inspect(other, limit: 100)}")
            end

            if turn_completed.usage do
              input_tokens =
                turn_completed.usage["input_tokens"] || turn_completed.usage[:input_tokens] || 0

              output_tokens =
                turn_completed.usage["output_tokens"] || turn_completed.usage[:output_tokens] || 0

              print_info("Usage: input=#{input_tokens} output=#{output_tokens}")
            end
          else
            print_info("No TurnCompleted event found")
          end

          :ok

        {:error, reason} ->
          print_error("Thread run failed: #{inspect(reason)}")
          {:error, reason}
      end
    else
      {:error, reason} ->
        print_error("Thread setup failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp handle_typed_event(event) do
    case event do
      %Events.ThreadStarted{thread_id: id} ->
        print_event("ThreadStarted", "thread_id=#{id}")

      %Events.TurnStarted{turn_id: turn_id} ->
        print_event("TurnStarted", "turn_id=#{turn_id}")

      %Events.TurnPlanUpdated{} ->
        print_event("TurnPlanUpdated", "")

      %Events.ItemAgentMessageDelta{item: item} ->
        content = extract_item_text(item)

        if content != "" do
          IO.write(IO.ANSI.cyan() <> content <> IO.ANSI.reset())
        end

      %Events.ThreadTokenUsageUpdated{usage: usage} ->
        input = usage["input_tokens"] || usage[:input_tokens] || 0
        output = usage["output_tokens"] || usage[:output_tokens] || 0
        print_event("TokenUsage", "input=#{input} output=#{output}")

      %Events.TurnCompleted{status: status} ->
        IO.puts("")
        print_event("TurnCompleted", "status=#{status}")

      %Events.ItemCompleted{} ->
        print_event("ItemCompleted", "")

      %Events.ItemStarted{} ->
        :ok

      _ ->
        name = event_struct_name(event)
        print_event(name, "")
    end
  end

  # ============================================================================
  # Section: Advanced Options
  # ============================================================================

  defp run_options do
    print_section("Options - Advanced Thread Configuration")

    print_step(1, "Building advanced thread options")

    {:ok, opts} =
      Codex.Thread.Options.new(%{
        working_directory: File.cwd!()
      })

    print_info("Working directory: #{opts.working_directory}")
    print_info("Thread options created successfully")

    print_step(2, "Building global Codex options")

    {:ok, codex_opts} = Codex.Options.new(%{})
    print_info("Codex options created with defaults")
    print_info("Model: #{codex_opts.model || "(default)"}")

    :ok
  end

  # ============================================================================
  # Section: Sessions
  # ============================================================================

  defp run_sessions do
    print_section("Sessions - Session Listing")

    print_step(1, "Listing Codex sessions")

    case Codex.Sessions.list_sessions() do
      {:ok, sessions} ->
        if sessions == [] do
          print_info("No sessions found (this is normal for fresh installations)")
        else
          print_info("Found #{length(sessions)} session(s)")
          IO.puts("")

          sessions
          |> Enum.take(5)
          |> Enum.each(fn entry ->
            IO.puts("    ID:         #{entry.id}")
            IO.puts("    Started:    #{entry.started_at || "unknown"}")
            IO.puts("    CWD:        #{entry.cwd || "unknown"}")
            IO.puts("    CLI:        #{entry.cli_version || "unknown"}")
            IO.puts("")
          end)

          if length(sessions) > 5 do
            print_info("... and #{length(sessions) - 5} more")
          end
        end

        :ok

      {:error, reason} ->
        print_info("Could not list sessions: #{inspect(reason)}")
        print_info("This is expected if codex has not been used before")
        :ok
    end
  end

  # ============================================================================
  # Helpers
  # ============================================================================

  defp extract_item_text(%{"text" => text}) when is_binary(text), do: text
  defp extract_item_text(%{text: text}) when is_binary(text), do: text
  defp extract_item_text(_), do: ""

  defp event_struct_name(%{__struct__: mod}) do
    mod
    |> Module.split()
    |> List.last()
  end

  defp event_struct_name(_), do: "unknown"

  # ============================================================================
  # Output Formatting
  # ============================================================================

  defp print_header(section) do
    IO.puts("")
    IO.puts(IO.ANSI.bright() <> "AgentSessionManager - Codex Direct Features" <> IO.ANSI.reset())
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

  defp print_event(name, detail) do
    label = IO.ANSI.yellow() <> "  [#{name}]" <> IO.ANSI.reset()

    if detail != "" do
      IO.puts(:stderr, "#{label} #{detail}")
    else
      IO.puts(:stderr, label)
    end
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

CodexDirect.main(System.argv())
