defmodule KaguyaWeb.FormatTest do
  use ExUnit.Case, async: true

  alias KaguyaWeb.Format

  describe "integer/1" do
    test "formats nil and integers with stable digit order and separators" do
      assert Format.integer(nil) == "0"
      assert Format.integer(0) == "0"
      assert Format.integer(3) == "3"
      assert Format.integer(10) == "10"
      assert Format.integer(319) == "319"
      assert Format.integer(1_234) == "1,234"
      assert Format.integer(12_345) == "12,345"
      assert Format.integer(1_234_567) == "1,234,567"
      assert Format.integer(-12_345) == "-12,345"
    end

    test "rounds floats before formatting" do
      assert Format.integer(12_345.4) == "12,345"
      assert Format.integer(12_345.5) == "12,346"
    end
  end
end
