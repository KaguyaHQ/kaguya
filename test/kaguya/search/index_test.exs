defmodule Kaguya.SearchIndexTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Kaguya.SearchIndex

  setup do
    config = Application.fetch_env!(:kaguya, :meilisearch)
    local_only = Application.get_env(:kaguya, :meili_indexing_local_only)
    warning_key = {SearchIndex, :non_local_warning}
    :persistent_term.erase(warning_key)

    on_exit(fn ->
      Application.put_env(:kaguya, :meilisearch, config)

      if is_nil(local_only),
        do: Application.delete_env(:kaguya, :meili_indexing_local_only),
        else: Application.put_env(:kaguya, :meili_indexing_local_only, local_only)

      :persistent_term.erase(warning_key)
    end)

    :ok
  end

  test "every write skips a non-local destination and warns once" do
    Application.put_env(:kaguya, :meili_indexing_local_only, true)

    Application.put_env(:kaguya, :meilisearch, %{
      base_url: "https://search.example.invalid",
      master_key: "never-send-this",
      req_options: [plug: fn _ -> flunk("non-local write reached HTTP") end]
    })

    log =
      capture_log(fn ->
        assert :ok = SearchIndex.index_visual_novels([%Kaguya.VisualNovels.VisualNovel{}])
        assert :ok = SearchIndex.index_characters([%Kaguya.Characters.Character{}])
        assert :ok = SearchIndex.index_producers([%Kaguya.Producers.Producer{}])
        assert :ok = SearchIndex.add_or_update_documents("visual_novels", [%{id: "1"}])
        assert :ok = SearchIndex.configure_visual_novels_index()
        assert :ok = SearchIndex.configure_producers_index()

        for remove <- [:remove_visual_novel, :remove_character, :remove_producer] do
          assert :ok = apply(SearchIndex, remove, ["id"])
        end

        for remove <- [:remove_visual_novels, :remove_characters, :remove_producers] do
          assert :ok = apply(SearchIndex, remove, [["id"]])
        end
      end)

    assert length(Regex.scan(~r/dev requires localhost or 127.0.0.1/, log)) == 1
    assert_raise RuntimeError, ~r/non-local/, fn -> SearchIndex.reindex("characters") end
  end

  test "test indexing stays disabled, even for a local URL" do
    Application.put_env(:kaguya, :meilisearch, %{
      base_url: "http://127.0.0.1:7700",
      master_key: nil
    })

    refute SearchIndex.writable?()
    assert :ok = SearchIndex.add_or_update_documents("characters", [%{id: "1"}])
  end
end
