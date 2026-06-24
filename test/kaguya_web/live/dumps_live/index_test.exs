defmodule KaguyaWeb.DumpsLive.IndexTest do
  use KaguyaWeb.ConnCase, async: false

  defmodule FakePublisher do
    def list_published do
      Application.fetch_env!(:kaguya, :public_dump_payload)
    end
  end

  setup do
    previous_publisher = Application.get_env(:kaguya, :public_dump_publisher)
    previous_payload = Application.get_env(:kaguya, :public_dump_payload)

    Application.put_env(:kaguya, :public_dump_publisher, FakePublisher)

    on_exit(fn ->
      restore_env(:public_dump_publisher, previous_publisher)
      restore_env(:public_dump_payload, previous_payload)
    end)

    :ok
  end

  test "renders the latest dump and retained older archives" do
    Application.put_env(:kaguya, :public_dump_payload, {:ok, payload()})

    {:ok, _view, html} = live(build_conn(), "/dumps")

    assert html =~ "Database Dump"
    assert html =~ "kaguya-db-latest.tar.zst"
    assert html =~ "2 MiB"
    assert html =~ "2026-05-10 00:00 UTC"
    assert html =~ "Older versions"
    assert html =~ "kaguya-db-2026-05-03.tar.zst"
    assert html =~ "kaguya-db-2026-04-26.tar.zst"
    refute html =~ "kaguya-db-2026-04-19.tar.zst"
    assert html =~ ~s(download="kaguya-db-latest.tar.zst")
  end

  test "renders empty state when no dump has been published" do
    Application.put_env(:kaguya, :public_dump_payload, {:ok, %{latest: nil, past: []}})

    {:ok, _view, html} = live(build_conn(), "/dumps")

    assert html =~ "No dump is currently available"
    assert html =~ "Publishes run every Sunday 00:00 UTC"
  end

  test "keeps JSON payload endpoint available" do
    Application.put_env(:kaguya, :public_dump_payload, {:ok, payload()})

    conn = get(build_conn(), "/dumps.json")

    assert json_response(conn, 200)["latest"]["filename"] == "kaguya-db-latest.tar.zst"
  end

  defp payload do
    %{
      latest: %{
        filename: "kaguya-db-latest.tar.zst",
        size: 2_097_152,
        last_modified: "2026-05-10T00:00:00Z",
        url: "https://images.kaguya.io/dumps/kaguya-db-latest.tar.zst"
      },
      past: [
        %{
          filename: "kaguya-db-2026-05-03.tar.zst",
          size: 1_048_576,
          last_modified: "2026-05-03T00:00:00Z",
          url: "https://images.kaguya.io/dumps/kaguya-db-2026-05-03.tar.zst"
        },
        %{
          filename: "kaguya-db-2026-04-26.tar.zst",
          size: 524_288,
          last_modified: "2026-04-26T00:00:00Z",
          url: "https://images.kaguya.io/dumps/kaguya-db-2026-04-26.tar.zst"
        },
        %{
          filename: "kaguya-db-2026-04-19.tar.zst",
          size: 262_144,
          last_modified: "2026-04-19T00:00:00Z",
          url: "https://images.kaguya.io/dumps/kaguya-db-2026-04-19.tar.zst"
        }
      ]
    }
  end

  defp restore_env(key, nil), do: Application.delete_env(:kaguya, key)
  defp restore_env(key, value), do: Application.put_env(:kaguya, key, value)
end
