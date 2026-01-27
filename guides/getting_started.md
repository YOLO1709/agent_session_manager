# Getting Started

This guide walks you through installing AgentSessionManager, running your first session, and understanding the core workflow.

## Installation

Add `agent_session_manager` to your `mix.exs` dependencies:

```elixir
def deps do
  [
    {:agent_session_manager, "~> 0.1.0"}
  ]
end
```

Fetch dependencies:

```bash
mix deps.get
```

AgentSessionManager pulls in a small set of runtime dependencies:

- `telemetry` -- for observability hooks
- `jason` -- for JSON encoding/decoding
- `codex_sdk` and `claude_agent_sdk` -- the underlying provider SDKs

## Your First Session

The fundamental workflow is: **create a session, create a run inside it, execute the run, inspect the result.**

```elixir
alias AgentSessionManager.Core.{Session, Run}
alias AgentSessionManager.SessionManager
alias AgentSessionManager.Adapters.{ClaudeAdapter, InMemorySessionStore}

# Start infrastructure processes
{:ok, store} = InMemorySessionStore.start_link()
{:ok, adapter} = ClaudeAdapter.start_link(api_key: System.get_env("ANTHROPIC_API_KEY"))

# Create a session (status: :pending)
{:ok, session} = SessionManager.start_session(store, adapter, %{
  agent_id: "my-agent",
  context: %{system_prompt: "You are a helpful assistant."},
  metadata: %{user_id: "user-42"}
})

# Activate the session (status: :active)
{:ok, session} = SessionManager.activate_session(store, session.id)

# Create a run with input
{:ok, run} = SessionManager.start_run(store, adapter, session.id, %{
  messages: [%{role: "user", content: "What is Elixir?"}]
})

# Execute the run -- this calls the provider and streams events
{:ok, result} = SessionManager.execute_run(store, adapter, run.id)

# The result contains the output, token usage, and events
IO.puts(result.output.content)
IO.inspect(result.token_usage)
# => %{input_tokens: 15, output_tokens: 120}

# Complete the session when done
{:ok, _} = SessionManager.complete_session(store, session.id)
```

## Understanding the Workflow

Here's what happens under the hood when you call `SessionManager.execute_run/3`:

1. The run is fetched from the store and its status updated to `:running`
2. The parent session is fetched for context
3. The provider adapter's `execute/4` is called with the run and session
4. The adapter sends the request to the AI provider
5. As the provider streams back responses, the adapter emits normalized events
6. Each event is persisted to the session store via `append_event`
7. Telemetry events are emitted for observability
8. When the provider finishes, the run is updated with output and token usage
9. The result is returned to the caller

## Using the Event Callback

You can react to events in real time by providing an event callback when executing through the adapter directly:

```elixir
callback = fn event ->
  case event.type do
    :message_streamed ->
      IO.write(event.data.delta)

    :tool_call_started ->
      IO.puts("Calling tool: #{event.data.tool_name}")

    :run_completed ->
      IO.puts("\nDone!")

    _ ->
      :ok
  end
end

{:ok, result} = ClaudeAdapter.execute(adapter, run, session, event_callback: callback)
```

## Working Without a Provider

You can use the core domain types without any provider adapter -- they are pure data structures:

```elixir
alias AgentSessionManager.Core.{Session, Run, Event}

# Create domain objects
{:ok, session} = Session.new(%{agent_id: "test-agent"})
{:ok, run} = Run.new(%{session_id: session.id})
{:ok, event} = Event.new(%{
  type: :message_received,
  session_id: session.id,
  run_id: run.id,
  data: %{content: "Hello"}
})

# Serialize to maps for storage or transmission
session_map = Session.to_map(session)
run_map = Run.to_map(run)
event_map = Event.to_map(event)

# Reconstruct from maps
{:ok, restored_session} = Session.from_map(session_map)
```

## Running the Examples

The `examples/` directory has runnable scripts that demonstrate the library end-to-end:

```bash
# Mock mode -- no API key needed
mix run examples/live_session.exs --provider claude --mock

# Live mode with real API
ANTHROPIC_API_KEY=sk-ant-... mix run examples/live_session.exs --provider claude
```

## Next Steps

- [Architecture](architecture.md) -- understand the ports & adapters design
- [Sessions and Runs](sessions_and_runs.md) -- deep dive into lifecycle management
- [Provider Adapters](provider_adapters.md) -- configure Claude or Codex, or write your own
