# Examples

This directory contains runnable examples that demonstrate AgentSessionManager functionality end-to-end.

## Available Examples

### `live_session.exs` -- Live Session with Streaming

Demonstrates the full session lifecycle with a real or mock AI provider:

- Provider selection (Claude or Codex) via command line
- Registry initialization with provider manifests
- Configuration loading from environment variables
- Capability negotiation before execution
- Streaming message response with real-time output
- Event logging to stderr in human-readable format
- Token usage and execution statistics
- Clean interrupt via Ctrl+C

## Running Examples

### Quick Start (Mock Mode)

No API credentials needed -- mock mode simulates provider responses:

```bash
mix run examples/live_session.exs --provider claude --mock
```

Or simply run without credentials and mock mode is auto-detected:

```bash
mix run examples/live_session.exs --provider claude
```

### With Real API Credentials

```bash
# Claude (Anthropic)
ANTHROPIC_API_KEY=sk-ant-api03-... mix run examples/live_session.exs --provider claude

# Codex (OpenAI)
OPENAI_API_KEY=sk-... mix run examples/live_session.exs --provider codex
```

### Run All Examples

Use the provided script to run all examples in sequence:

```bash
./examples/run_all.sh
```

The script runs every example in mock mode so it works without credentials.

## Command Line Options

```
Usage: mix run examples/live_session.exs [options]

Options:
  --provider, -p <name>  Provider to use (claude or codex). Default: claude
  --mock, -m             Force mock mode (no credentials needed)
  --help, -h             Show this help message

Environment Variables:
  ANTHROPIC_API_KEY      API key for Claude (Anthropic)
  OPENAI_API_KEY         API key for Codex (OpenAI)
```

## Expected Output (Mock Mode)

```
AgentSessionManager - Live Session Example
==================================================
Provider: claude
Mode:     mock (forced)
==================================================

Step 1: Mode Detection
----------------------------------------
  [INFO] Running in mock mode
  [WARN] Using mock adapter - no real API calls will be made

Step 2: Registry Setup
----------------------------------------
  [INFO] Registry initialized with 1 provider(s)

Step 3: Configuration
----------------------------------------
  [INFO] Configuration loaded for provider: claude

Step 4: Capability Check
----------------------------------------
  [INFO] Capability negotiation: full
  [INFO] Available capabilities: streaming, tool_use, vision, system_prompts, interrupt

Step 5: Session Creation
----------------------------------------
  [INFO] Session created: ses_abc123...
  [INFO] Run created: run_def456...
  [INFO] Sending message: "Hello! What can you tell me about Elixir?"

--- Response ---

Elixir is a dynamic, functional programming language designed for building
scalable and maintainable applications.

Key features include:
- Runs on the BEAM VM
- Excellent concurrency
- Fault-tolerant design
- Great tooling with Mix

Step 7: Usage Summary
--- Usage Summary ---

  Input tokens:  25
  Output tokens: 85
  Total tokens:  110
  Duration:      550ms
  Events:        4
  Stop reason:   end_turn

Example completed successfully!
```

## Obtaining API Credentials

### Anthropic (Claude)

1. Create an account at [console.anthropic.com](https://console.anthropic.com)
2. Navigate to **API Keys** in your account settings
3. Click **Create Key** and copy the key
4. Export it: `export ANTHROPIC_API_KEY=sk-ant-api03-...`

### OpenAI (Codex)

1. Create an account at [platform.openai.com](https://platform.openai.com)
2. Navigate to **API keys** in your account settings
3. Click **Create new secret key** and copy it
4. Export it: `export OPENAI_API_KEY=sk-...`

## Troubleshooting

### No credentials found

The example auto-detects mock mode when credentials are missing. To use live mode, set the appropriate environment variable. To explicitly use mock mode, pass `--mock`.

### SDK not available

The live SDK integration requires the provider SDK dependencies. Use `--mock` for demonstration without them.

### Rate limiting

If you see rate limit errors (HTTP 429), wait for the retry-after period or check your API usage dashboard.

### Network issues

Verify your internet connection and check that the API endpoint is accessible:

```bash
curl -I https://api.anthropic.com/v1/messages
```

## CI/CD Integration

Always use mock mode in CI to avoid credential requirements and API costs:

```yaml
# GitHub Actions
- name: Run examples
  run: ./examples/run_all.sh
```

## Adding New Examples

1. Create a new `.exs` file in this directory
2. Support both mock and live modes where applicable
3. Include clear output formatting and error handling
4. Add the example to `run_all.sh`
5. Document it in this README
