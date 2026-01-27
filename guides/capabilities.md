# Capabilities

Capabilities define what an AI provider can do. AgentSessionManager uses a capability system to declare requirements, check provider support, and fail fast when requirements aren't met.

## Capability Types

Each capability has a type that categorizes what it represents:

| Type | Description | Example |
|------|-------------|---------|
| `:tool` | A tool the agent can invoke | web_search, file_read |
| `:resource` | A resource the agent can access | vision, database |
| `:prompt` | A prompt template | system_prompts |
| `:sampling` | Sampling/generation mode | streaming, interrupt |
| `:file_access` | File system access | file_operations |
| `:network_access` | Network/HTTP access | http_requests |
| `:code_execution` | Code execution | bash, eval |

## Defining Capabilities

```elixir
alias AgentSessionManager.Core.Capability

{:ok, cap} = Capability.new(%{
  name: "web_search",
  type: :tool,
  description: "Search the web for information",
  config: %{max_results: 10},
  permissions: ["network:read"]
})

cap.enabled  # => true (default)
```

### Enabling and Disabling

```elixir
disabled = Capability.disable(cap)
disabled.enabled  # => false

enabled = Capability.enable(disabled)
enabled.enabled   # => true
```

## Capability Negotiation

The `CapabilityResolver` checks whether a provider supports the capabilities your application needs.

### How It Works

1. You declare which capability **types** are required and which are optional
2. The resolver compares these against the provider's actual capabilities
3. If any required type is missing, negotiation fails immediately
4. If optional types are missing, negotiation succeeds with a `:degraded` status and warnings

```elixir
alias AgentSessionManager.Core.CapabilityResolver

# Declare requirements
{:ok, resolver} = CapabilityResolver.new(
  required: [:sampling],         # must have at least one :sampling capability
  optional: [:tool, :prompt]     # nice to have, but not required
)

# Provider capabilities (from adapter)
{:ok, capabilities} = ClaudeAdapter.capabilities(adapter)

# Negotiate
case CapabilityResolver.negotiate(resolver, capabilities) do
  {:ok, result} ->
    result.status      # => :full (all satisfied) or :degraded (optional missing)
    result.supported   # => MapSet of supported types
    result.unsupported # => MapSet of unsupported optional types
    result.warnings    # => ["Optional capability 'prompt' is not supported..."]

  {:error, %Error{code: :missing_required_capability}} ->
    # Required capability missing -- cannot proceed
end
```

### Integration with SessionManager

When creating a run, you can pass capability requirements:

```elixir
{:ok, run} = SessionManager.start_run(store, adapter, session.id, input,
  required_capabilities: [:sampling, :tool],
  optional_capabilities: [:prompt]
)
```

The SessionManager calls the resolver automatically. If required capabilities are missing, the run isn't created.

### Helper Functions

```elixir
# Check if any capability of a type exists
CapabilityResolver.has_capability_type?(capabilities, :tool)  # => true

# Get all capabilities of a type
tools = CapabilityResolver.capabilities_of_type(capabilities, :tool)
# => [%Capability{name: "tool_use", type: :tool, ...}]
```

## Manifests

A `Manifest` bundles an agent's identity with its capabilities:

```elixir
alias AgentSessionManager.Core.Manifest

{:ok, manifest} = Manifest.new(%{
  name: "claude-agent",
  version: "1.0.0",
  description: "Claude-powered research agent",
  provider: "anthropic",
  capabilities: [
    %{name: "streaming", type: :sampling, description: "Real-time streaming"},
    %{name: "tool_use", type: :tool, description: "Tool calling"},
    %{name: "vision", type: :resource, description: "Image understanding"}
  ]
})
```

### Managing Capabilities in a Manifest

```elixir
# Add a capability
{:ok, manifest} = Manifest.add_capability(manifest, %{
  name: "code_execution",
  type: :code_execution,
  description: "Execute code"
})

# Remove a capability
{:ok, manifest} = Manifest.remove_capability(manifest, "vision")

# Get a capability by name
{:ok, cap} = Manifest.get_capability(manifest, "streaming")

# Get only enabled capabilities
enabled = Manifest.enabled_capabilities(manifest)
```

## The Registry

The `Registry` provides a thread-safe, immutable store for manifests. Each operation returns a new registry without mutating the original.

```elixir
alias AgentSessionManager.Core.Registry

# Create and populate
registry = Registry.new()
{:ok, registry} = Registry.register(registry, manifest)

# Lookup
{:ok, found} = Registry.get(registry, "claude-agent")
Registry.exists?(registry, "claude-agent")  # => true
Registry.count(registry)                     # => 1

# List (always sorted by name)
manifests = Registry.list(registry)

# Update an existing manifest
{:ok, registry} = Registry.update(registry, updated_manifest)

# Remove
{:ok, registry} = Registry.unregister(registry, "claude-agent")
```

### Filtering

```elixir
# By provider
anthropic_agents = Registry.filter_by_provider(registry, "anthropic")

# By capability type
tool_agents = Registry.filter_by_capability(registry, :tool)
```

### Validation

```elixir
case Registry.validate_manifest(manifest) do
  :ok -> :valid
  {:error, %Error{message: msg}} -> IO.puts("Invalid: #{msg}")
end
```

Validation checks:
- Name is present and non-empty
- Version is present and non-empty
- All capabilities have valid names and types

### Serialization

Both manifests and the registry support serialization:

```elixir
# Manifest
map = Manifest.to_map(manifest)
{:ok, restored} = Manifest.from_map(map)

# Registry
map = Registry.to_map(registry)
{:ok, restored} = Registry.from_map(map)
```
