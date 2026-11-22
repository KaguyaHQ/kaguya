defmodule KaguyaWeb.Markdown.VnLinks do
  @moduledoc """
  Finds Kaguya VN links (`[Title](/vn/slug)`) in user markdown and loads the
  card data `KaguyaWeb.Markdown.UserContent` needs to render them as covers.

  Callers batch: collect every body on the page, call `cards_for/1` once, then
  hand each body its subset via `cards_in/2`.
  """

  alias Kaguya.VisualNovels

  @link_pattern ~r{\]\(\s*(?:https?://(?:www\.)?kaguya\.io)?/vn/([a-z0-9-]+)/?\s*\)}

  @doc "Card data for every VN linked from `contents`, keyed by slug."
  def cards_for(contents) when is_list(contents) do
    contents
    |> Enum.flat_map(&slugs/1)
    |> VisualNovels.cards_by_slugs()
  end

  def cards_for(content), do: cards_for([content])

  @doc "The subset of `cards` linked from `content`."
  def cards_in(cards, content) when map_size(cards) == 0 or not is_binary(content), do: %{}
  def cards_in(cards, content), do: Map.take(cards, slugs(content))

  @doc """
  Puts the item's `:vn_cards`. Pass `cards` from a batched `cards_for/1`;
  without it, loads cards for this one item (create/edit responses).
  """
  def attach(%{content: content} = item, cards),
    do: Map.put(item, :vn_cards, cards_in(cards, content))

  def attach(%{content: content} = item), do: attach(item, cards_for(content))

  @doc "The slug a rendered href points at, or nil for non-VN links."
  def slug_from_href(href) when is_binary(href) do
    case Regex.run(~r{^(?:https?://(?:www\.)?kaguya\.io)?/vn/([a-z0-9-]+)/?$}, href) do
      [_, slug] -> slug
      _ -> nil
    end
  end

  def slug_from_href(_href), do: nil

  defp slugs(content) when is_binary(content) do
    @link_pattern
    |> Regex.scan(content, capture: :all_but_first)
    |> List.flatten()
  end

  defp slugs(_content), do: []
end
