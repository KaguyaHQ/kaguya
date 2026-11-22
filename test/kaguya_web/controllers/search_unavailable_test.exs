defmodule KaguyaWeb.SearchUnavailableTest do
  use KaguyaWeb.ConnCase, async: false

  setup do
    config = Application.fetch_env!(:kaguya, :meilisearch)
    Application.put_env(:kaguya, :meilisearch, %{base_url: nil, master_key: nil})
    on_exit(fn -> Application.put_env(:kaguya, :meilisearch, config) end)
    :ok
  end

  test "VN autocomplete returns the existing service-unavailable JSON", %{conn: conn} do
    conn = get(conn, "/search/visual-novels", q: "umineko")
    assert json_response(conn, 503) == %{"error" => "Search is temporarily unavailable"}
  end

  test "topic picker keeps standalone categories without Meilisearch" do
    assert {:ok, [_ | _]} = Kaguya.Discussions.Targets.search_category_targets("")
    assert {:ok, results} = Kaguya.Discussions.Targets.search_category_targets("general")
    assert Enum.any?(results, &(&1.category_type == :general))
  end

  test "search page renders its unavailable state without crashing", %{conn: conn} do
    {:ok, view, _} = live(conn, "/search?q=umineko")
    assert has_element?(view, "div", "Something went wrong")
  end
end
