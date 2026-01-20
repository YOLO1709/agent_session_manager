defmodule AgentSessionManagerTest do
  use ExUnit.Case
  doctest AgentSessionManager

  test "greets the world" do
    assert AgentSessionManager.hello() == :world
  end
end
