defmodule Kaguya.SearchTest do
  use ExUnit.Case, async: false

  alias Kaguya.Search
  alias Kaguya.Search.Client

  setup do
    previous = Application.fetch_env!(:kaguya, :meilisearch)
    on_exit(fn -> Application.put_env(:kaguya, :meilisearch, previous) end)
    :ok
  end

  test "missing and blank URLs return an error before making a request" do
    for url <- [nil, "", "  "] do
      Application.put_env(:kaguya, :meilisearch, %{base_url: url, master_key: nil})
      assert {:error, :not_configured} = Search.search_index("visual_novels", "umineko")
      assert {:error, :not_configured} = Search.federated_search([])
      refute Client.healthy?()
    end
  end

  test "search requests preserve pagination, filters and federation" do
    stub(fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      request = Jason.decode!(body)

      case conn.request_path do
        "/indexes/visual_novels/search" ->
          assert request == %{
                   "q" => "umineko",
                   "page" => 2,
                   "hitsPerPage" => 5,
                   "filter" => "title_category = vn"
                 }

          Req.Test.json(conn, %{hits: [%{title: "Umineko"}]})

        "/multi-search" ->
          assert request["federation"] == %{"limit" => 3}
          assert request["queries"] == [%{"indexUid" => "characters", "q" => "beatrice"}]
          Req.Test.json(conn, %{hits: [%{name: "Beatrice"}]})
      end
    end)

    assert {:ok, %{"hits" => [%{"title" => "Umineko"}]}} =
             Search.search_index("visual_novels", "umineko", 2, 5, filter: "title_category = vn")

    assert {:ok, [%{"name" => "Beatrice"}]} =
             Search.federated_search([%{indexUid: "characters", q: "beatrice"}], limit: 3)
  end

  test "unavailable service returns errors from both query routes" do
    stub(&Plug.Conn.send_resp(&1, 503, "unavailable"))
    assert {:error, _} = Search.search_index("visual_novels", "umineko")
    assert {:error, _} = Search.federated_search([])
    refute Client.healthy?()
  end

  test "health requires the service's available response" do
    stub(fn conn ->
      assert conn.request_path == "/health"
      Req.Test.json(conn, %{status: "available"})
    end)

    assert Client.healthy?()
  end

  test "task completion checks success and reports asynchronous failures" do
    stub(fn conn ->
      case conn.request_path do
        "/tasks/1" ->
          Req.Test.json(conn, %{status: "succeeded"})

        "/tasks/2" ->
          Req.Test.json(conn, %{status: "failed", error: %{code: "invalid_document_id"}})

        "/tasks/3" ->
          Req.Test.json(conn, %{status: "canceled"})
      end
    end)

    assert :ok = Kaguya.SearchIndex.wait_for_task!(1)

    assert_raise RuntimeError, ~r/invalid_document_id/, fn ->
      Kaguya.SearchIndex.wait_for_task!(2)
    end

    assert_raise RuntimeError, ~r/canceled/, fn -> Kaguya.SearchIndex.wait_for_task!(3) end
  end

  defp stub(fun) do
    Req.Test.stub(__MODULE__, fun)

    Application.put_env(:kaguya, :meilisearch, %{
      base_url: "http://localhost:7700",
      master_key: "local-test-key",
      req_options: [plug: {Req.Test, __MODULE__}]
    })
  end
end
