defmodule KaguyaWeb.Components.Activity.HelpersTest do
  use ExUnit.Case, async: true

  alias KaguyaWeb.Components.Activity.Helpers

  describe "tag_vote_phrase/1 (graded relevance 0..5)" do
    test "maps each vote value to a grade-carrying connective" do
      # The grade is always present, so "voted Comedy a small element of X"
      # never overstates as the categorical "tagged X as Comedy".
      assert Helpers.tag_vote_phrase(5) == "the main theme of"
      assert Helpers.tag_vote_phrase(4) == "a major element of"
      assert Helpers.tag_vote_phrase(3) == "a moderate element of"
      assert Helpers.tag_vote_phrase(2) == "a minor element of"
      assert Helpers.tag_vote_phrase(1) == "a small element of"
    end

    test "0 reads as the 'not relevant' downvote, not an endorsement" do
      assert Helpers.tag_vote_phrase(0) == "not relevant to"
    end

    test "coerces stringified jsonb values" do
      assert Helpers.tag_vote_phrase("2") == "a minor element of"
      assert Helpers.tag_vote_phrase("0") == "not relevant to"
    end

    test "falls back to a neutral, grammatical phrase for unexpected values" do
      assert Helpers.tag_vote_phrase(nil) == "relevant to"
      assert Helpers.tag_vote_phrase(99) == "relevant to"
      assert Helpers.tag_vote_phrase("garbage") == "relevant to"
    end
  end
end
