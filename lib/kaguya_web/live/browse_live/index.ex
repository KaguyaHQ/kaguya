defmodule KaguyaWeb.BrowseLive.Index do
  use KaguyaWeb, :live_view

  alias KaguyaWeb.BrowseLive.Data
  alias KaguyaWeb.BrowseLive.IndexComponents

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Browse • Kaguya")
     |> assign(
       :meta_description,
       "Filter and sort visual novels by rating, length, release date, tags, language, and more."
     )
     |> assign(KaguyaWeb.SEO.index())
     |> assign(:payload, nil)
     |> assign(:params, %{})}
  end

  def handle_params(params, _uri, socket) do
    mode = mode(socket.assigns.live_action, params)
    payload = Data.load(mode, params, socket.assigns.current_user)

    {:noreply,
     socket
     |> assign(:payload, payload)
     |> assign(:params, params)
     |> assign(:page_title, page_title(mode))
     |> assign(:meta_description, meta_description(mode))
     |> assign(robots_for(params))}
  end

  def render(assigns) do
    ~H"""
    <IndexComponents.browse_page payload={@payload} params={@params} />
    """
  end

  defp mode(:characters, _params), do: :characters
  defp mode(_action, %{"type" => "characters"}), do: :characters
  defp mode(_action, _params), do: :vn

  defp page_title(:characters), do: "Browse Characters • Kaguya"
  defp page_title(:vn), do: "Browse • Kaguya"

  defp meta_description(:characters),
    do: "Discover characters from visual novels — sort by popularity, name, or recency."

  defp meta_description(:vn),
    do: "Filter and sort visual novels by rating, length, release date, tags, language, and more."

  # No filters → the canonical browse page (indexable). Any filter/sort/page
  # params → a thin, near-duplicate variant: noindex, but follow through to VNs.
  defp robots_for(params) when map_size(params) == 0, do: KaguyaWeb.SEO.index()
  defp robots_for(_params), do: KaguyaWeb.SEO.noindex()
end
