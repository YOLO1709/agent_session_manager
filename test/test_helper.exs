# Configure ExUnit
ExUnit.start(exclude: [:skip, :load_test])

# Ensure Supertester is available and configured
# The supertester library provides:
# - Robust test isolation with Supertester.ExUnitFoundation
# - Deterministic async testing via TestableGenServer
# - Process lifecycle assertions via Supertester.Assertions
# - Performance testing via Supertester.PerformanceHelpers
# - Chaos engineering via Supertester.ChaosHelpers

# Import test fixtures for easy access
# Usage in tests:
#   use AgentSessionManager.SupertesterCase, async: true
#
# Or for simple tests without full supertester infrastructure:
#   import AgentSessionManager.Test.Fixtures
