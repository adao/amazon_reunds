defmodule ARTest do
  use ExUnit.Case
  doctest AR

  test "greets the world" do
    assert AR.hello() == :world
  end
end
