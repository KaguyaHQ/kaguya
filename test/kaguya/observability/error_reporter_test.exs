defmodule Kaguya.ErrorReporterTest do
  use ExUnit.Case, async: false

  alias Kaguya.Observability.ErrorReporter

  describe "report/2" do
    test "accepts an exception with full options" do
      assert :ok =
               ErrorReporter.report(%RuntimeError{message: "boom"},
                 operation: "test.exception",
                 resource_type: "test_thing",
                 resource_id: "abc-123",
                 critical: true,
                 metadata: %{foo: "bar"}
               )
    end

    test "accepts a string message" do
      assert :ok =
               ErrorReporter.report("something broke",
                 operation: "test.message",
                 metadata: %{count: 3}
               )
    end

    test "accepts arbitrary terms via inspect" do
      assert :ok = ErrorReporter.report({:weird, :error_term}, operation: "test.term")
    end

    test "raises when operation is missing — fail loud, not silent" do
      assert_raise KeyError, fn ->
        ErrorReporter.report(%RuntimeError{message: "x"}, [])
      end
    end
  end
end
