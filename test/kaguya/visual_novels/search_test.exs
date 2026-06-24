defmodule Kaguya.VisualNovels.SearchTest do
  use ExUnit.Case, async: true

  alias Kaguya.VisualNovels

  describe "normalize_search_query/1" do
    test "compacts punctuation-heavy title acronyms" do
      assert VisualNovels.normalize_search_query("I/O") == "IO"
      assert VisualNovels.normalize_search_query("i-o") == "io"
      assert VisualNovels.normalize_search_query("i o") == "io"
    end

    test "strips punctuation inside title words to match indexed prefixes" do
      assert VisualNovels.normalize_search_query("Muv-Luv Alternative") == "MuvLuv Alternative"
      assert VisualNovels.normalize_search_query("Fate/stay night") == "Fatestay night"
      assert VisualNovels.normalize_search_query("D.C.") == "DC"
    end

    test "keeps multi-word title searches readable" do
      assert VisualNovels.normalize_search_query("mama x holic") == "mama x holic"
      assert VisualNovels.normalize_search_query("Rance X -Kessen-") == "Rance X Kessen"
    end
  end
end
