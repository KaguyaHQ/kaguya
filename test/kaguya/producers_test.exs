defmodule Kaguya.ProducersTest do
  use ExUnit.Case, async: true

  alias Kaguya.Producers

  describe "select_primary/1" do
    test "returns no producers when only publishers exist" do
      rows = [
        %{role: "publisher", earliest_release_date: ~D[2020-01-01], name: "Publisher"}
      ]

      assert Producers.select_primary(rows) == []
    end

    test "keeps earliest developers only" do
      earliest = %{role: "developer", earliest_release_date: ~D[2020-01-01], name: "Earliest"}
      later = %{role: "developer", earliest_release_date: ~D[2021-01-01], name: "Later"}
      publisher = %{role: "publisher", earliest_release_date: ~D[2019-01-01], name: "Publisher"}

      assert Producers.select_primary([publisher, later, earliest]) == [earliest]
    end
  end
end
