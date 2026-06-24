defmodule KaguyaWeb.ChangesLive.Index do
  use KaguyaWeb, :live_view

  alias KaguyaWeb.ChangesLive.{Data, IndexComponents}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(KaguyaWeb.SEO.index())
     |> assign(
       page_title: "Recent changes • Kaguya",
       meta_description: "Browse recent user-authored edits across Kaguya.",
       payload: nil
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, assign(socket, :payload, Data.load(params))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <IndexComponents.changes_page payload={@payload} />
    """
  end
end
