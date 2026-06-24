defmodule Kaguya.Users.UserTest do
  use ExUnit.Case, async: true

  alias Kaguya.Users.User

  defp changeset(display_name) do
    User.changeset(%User{}, %{display_name: display_name})
  end

  defp display_name(cs), do: Ecto.Changeset.get_change(cs, :display_name)
  defp errors(cs), do: Keyword.get_values(cs.errors, :display_name)

  describe "display name sanitization" do
    test "plain text passes through unchanged" do
      assert display_name(changeset("Alice")) == "Alice"
    end

    test "strips zero-width spaces from edges" do
      assert display_name(changeset("\u200BAlice\u200B")) == "Alice"
    end

    test "strips zero-width non-joiners from edges" do
      assert display_name(changeset("\u200CAlice\u200C")) == "Alice"
    end

    test "strips zero-width joiners from edges" do
      assert display_name(changeset("\u200DAlice\u200D")) == "Alice"
    end

    test "strips braille blank (U+2800) from edges" do
      assert display_name(changeset("\u2800Hello\u2800")) == "Hello"
    end

    test "strips hangul filler (U+3164) from edges" do
      assert display_name(changeset("\u3164Test\u3164")) == "Test"
    end

    test "strips regular leading/trailing spaces" do
      assert display_name(changeset("  Alice  ")) == "Alice"
    end

    test "collapses interior invisible characters to a single space" do
      assert display_name(changeset("Alice\u200B\u200B\u2800Bob")) == "Alice Bob"
    end

    test "collapses interior mixed invisible and regular spaces" do
      assert display_name(changeset("Alice \u200B Bob")) == "Alice Bob"
    end

    test "collapses multiple regular interior spaces" do
      assert display_name(changeset("Alice   Bob")) == "Alice Bob"
    end

    test "handles combination of edge stripping and interior collapsing" do
      assert display_name(changeset("\u2800Alice\u200B\u200BBob\u3164")) == "Alice Bob"
    end

    test "preserves non-ASCII visible characters" do
      assert display_name(changeset("日本語テスト")) == "日本語テスト"
    end

    test "preserves emoji" do
      assert display_name(changeset("Alice 🎮 Bob")) == "Alice 🎮 Bob"
    end
  end

  describe "display name visibility validation" do
    test "rejects all zero-width spaces" do
      cs = changeset("\u200B\u200B\u200B")
      refute cs.valid?
      assert {"must contain at least one visible character", []} in errors(cs)
    end

    test "rejects all braille blanks" do
      cs = changeset("\u2800\u2800")
      refute cs.valid?
      assert {"must contain at least one visible character", []} in errors(cs)
    end

    test "rejects all hangul fillers" do
      cs = changeset("\u3164\u3164")
      refute cs.valid?
      assert {"must contain at least one visible character", []} in errors(cs)
    end

    test "rejects mix of invisible characters" do
      cs = changeset("\u200B\u2800\u3164\u200C\u200D")
      refute cs.valid?
      assert {"must contain at least one visible character", []} in errors(cs)
    end

    test "all regular spaces are dropped by cast (no change, no error)" do
      cs = changeset("   ")
      assert cs.valid?
      assert display_name(cs) == nil
    end

    test "accepts a single visible character" do
      cs = changeset("A")
      assert display_name(cs) == "A"
      refute {"must contain at least one visible character", []} in errors(cs)
    end

    test "accepts visible character surrounded by invisible" do
      cs = changeset("\u200BA\u200B")
      assert display_name(cs) == "A"
      assert cs.valid?
    end
  end
end
