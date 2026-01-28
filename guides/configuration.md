# Configuration

AgentSessionManager uses a layered configuration system via `AgentSessionManager.Config`. This module resolves settings through three layers in priority order, enabling safe concurrent testing while keeping production configuration straightforward.

## Resolution Order

When you call `AgentSessionManager.Config.get/1`, the value is resolved as follows:

1. **Process-local override** -- set via `AgentSessionManager.Config.put/2`, stored in the process dictionary. Scoped to the calling process and automatically cleaned up when the process exits.
2. **Application environment** -- set via `config :agent_session_manager, key: value` or `Application.put_env/3`. Shared across all processes.
3. **Built-in default** -- hardcoded fallback per key.

```
Config.get(:telemetry_enabled)
  |
  |-- Process dictionary has override? --> return override
  |-- Application.get_env has value?   --> return app env value
  |-- Return built-in default (true)
```

## Supported Keys

| Key                      | Type      | Default | Used By       |
|--------------------------|-----------|---------|---------------|
| `:telemetry_enabled`     | `boolean` | `true`  | `Telemetry`   |
| `:audit_logging_enabled` | `boolean` | `true`  | `AuditLogger` |

## Application Environment

Set values in your `config/config.exs` (or runtime config):

```elixir
config :agent_session_manager,
  telemetry_enabled: true,
  audit_logging_enabled: false
```

These values apply to all processes unless a process-local override is set.

## Process-Local Overrides

Use `AgentSessionManager.Config.put/2` to set an override that only affects the current process:

```elixir
alias AgentSessionManager.Config

# Override for this process only
Config.put(:telemetry_enabled, false)
Config.get(:telemetry_enabled)
#=> false

# Other processes still see the app env / default
spawn(fn ->
  IO.inspect(Config.get(:telemetry_enabled))
  #=> true
end)

# Remove the override (falls back to app env / default)
Config.delete(:telemetry_enabled)
Config.get(:telemetry_enabled)
#=> true
```

Process-local overrides live in the process dictionary and are automatically cleaned up when the process exits. No manual teardown is needed.

## How Telemetry and AuditLogger Use Config

Both `Telemetry` and `AuditLogger` delegate their `enabled?/0` checks to `AgentSessionManager.Config.get/1`:

```elixir
# These are equivalent:
AgentSessionManager.Telemetry.enabled?()
AgentSessionManager.Config.get(:telemetry_enabled)

# set_enabled/1 calls Config.put/2 under the hood
AgentSessionManager.Telemetry.set_enabled(false)
# equivalent to:
AgentSessionManager.Config.put(:telemetry_enabled, false)
```

This means `set_enabled/1` is process-local -- calling it in a test process does not affect other test processes or production code.

## Concurrent Testing

The process-local design enables fully concurrent tests. Before this change, `Telemetry.set_enabled/1` mutated the global application environment, forcing telemetry tests to run sequentially (`async: false`). Now each test process has its own override:

```elixir
defmodule MyApp.TelemetryTest do
  use ExUnit.Case, async: true  # safe -- no global state mutation

  alias AgentSessionManager.Telemetry

  test "telemetry can be disabled" do
    # Only affects this test process
    Telemetry.set_enabled(false)
    refute Telemetry.enabled?()
  end

  test "telemetry is enabled by default" do
    # Unaffected by the test above -- separate process
    assert Telemetry.enabled?()
  end
end
```

## Design Rationale

This pattern follows the same approach as Elixir's `Logger` module for per-process log levels. The key benefits:

- **No global state mutation** -- `Application.put_env/3` is no longer called at runtime for enable/disable toggles.
- **Concurrent tests** -- each test process can independently override settings.
- **Zero-cost cleanup** -- process dictionary entries are garbage collected with the process.
- **Transparent fallback** -- if no override is set, the application environment and built-in defaults apply as expected.
