defmodule KaguyaWeb.PoliciesLive.Show do
  @moduledoc """
  Static policy / about / FAQ pages.

  One LiveView serves all 10 slugs — the content map lives in
  `KaguyaWeb.Policies.Content` and is rendered through the shared
  `KaguyaWeb.PolicyComponents.policy_shell/1` shell.
  """

  use KaguyaWeb, :live_view

  import KaguyaWeb.PolicyComponents

  alias KaguyaWeb.Policies.{Content, Markdown}

  @action_to_slug %{
    about: "about",
    development: "development",
    faq: "faq",
    community_guidelines: "community-guidelines",
    review_guidelines: "review-guidelines",
    content_policy: "content-policy",
    formatting_help: "formatting-help",
    privacy_policy: "privacy-policy",
    terms: "terms"
  }

  @impl true
  def mount(_params, _session, socket), do: {:ok, socket}

  @impl true
  def handle_params(_params, _uri, %{assigns: %{live_action: action}} = socket) do
    slug = Map.fetch!(@action_to_slug, action)
    {:ok, page} = Content.fetch(slug)

    {:noreply,
     socket
     |> assign(:slug, slug)
     |> assign(:title, page.title)
     |> assign(:page_title, page.page_title)
     |> assign(:meta_description, page.description)
     |> assign(:canonical_url, "https://kaguya.io/#{slug}")
     |> assign(:body_html, Markdown.to_html(page.body))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.policy_shell title={@title} current_path={"/" <> @slug}>
      {@body_html}
    </.policy_shell>
    """
  end
end
