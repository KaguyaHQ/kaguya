defmodule KaguyaWeb.PoliciesLive.HelpTest do
  use KaguyaWeb.ConnCase, async: true

  alias KaguyaWeb.Policies.{Content, Markdown}

  test "contributor guides are public and their local links use LiveView navigation", %{
    conn: conn
  } do
    for slug <- Content.slugs(), String.starts_with?(slug, "help") do
      {:ok, view, _html} = live(conn, "/" <> slug)
      assert has_element?(view, "h1")
      assert has_element?(view, "nav[aria-label='Help and policies'] a[href='/help']")

      refute has_element?(view, "main a[href^='/']:not([data-phx-link])")
      refute has_element?(view, "main a[href^='/'][target='_blank']")
    end
  end

  test "create forms link to their specific guide without discarding an open form", %{conn: conn} do
    for {type, id, guide} <- [
          {"vn", "vn-editor-help", "visual-novels"},
          {"character", "character-editor-help", "characters"},
          {"developer", "producer-editor-help", "producers"}
        ] do
      {:ok, view, _html} = live(conn, "/contribute/" <> type)
      assert has_element?(view, "##{id}[href='/help/#{guide}'][target='_blank']")
    end
  end

  test "markdown keeps external links separate and escapes link labels" do
    html =
      Markdown.to_html("[<b>Help</b>](/help) [Source](https://example.com) [Section](#section)")
      |> Phoenix.HTML.safe_to_string()
      |> LazyHTML.from_fragment()

    assert html |> LazyHTML.query("a[href='/help'][data-phx-link='redirect']") |> Enum.count() ==
             1

    assert html
           |> LazyHTML.query("a[href='https://example.com'][target='_blank']")
           |> Enum.count() == 1

    assert html |> LazyHTML.query("a[href='#section']:not([target])") |> Enum.count() == 1
    assert html |> LazyHTML.query("b") |> Enum.count() == 0
  end
end
