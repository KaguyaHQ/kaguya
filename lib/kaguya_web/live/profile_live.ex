defmodule KaguyaWeb.ProfileLive do
  @moduledoc """
  Shared scaffolding for every `/@:username` tab LiveView.

  Each tab module does:

      use KaguyaWeb.ProfileLive, tab: :activity, title_suffix: "Activity"

  This injects:
    * `use KaguyaWeb, :live_view` and the right module aliases.
    * A default `mount/3` that seeds the empty assigns map.
    * A default `handle_params/3` that loads the header view-model via
      `ProfileLive.Data` and routes 404s to the not-found render.
    * A `handle_event/3` clause for `toggle_follow` (and other shared
      events as they're added) so tabs don't reimplement follow logic.

  Tab modules override `handle_params/3` and add their own per-tab
  `handle_event/3` clauses for tab-specific events. Always pattern-match
  the shared events first; tab-specific events follow.
  """

  alias KaguyaWeb.ProfileLive.{Data, Events}

  defmacro __using__(opts) do
    tab = Keyword.fetch!(opts, :tab)
    title_suffix = Keyword.get(opts, :title_suffix)

    quote do
      use KaguyaWeb, :live_view

      alias KaguyaWeb.Components.Profile.{Header, Nav, Skeletons}
      alias KaguyaWeb.ProfileLive.{Data, Events}

      @profile_tab unquote(tab)
      @profile_title_suffix unquote(title_suffix)
      @root_tab? unquote(tab) == :overview

      @impl Phoenix.LiveView
      def mount(_params, _session, socket) do
        {:ok,
         socket
         |> Phoenix.Component.assign(:state, :loading)
         |> Phoenix.Component.assign(:profile, nil)
         |> Phoenix.Component.assign(:permissions, %{any?: false})
         |> Phoenix.Component.assign(:page_title, "Profile · Kaguya")
         |> Phoenix.Component.assign(:current_tab, @profile_tab)
         |> Phoenix.Component.assign(:root?, @root_tab?)}
      end

      @impl Phoenix.LiveView
      def handle_params(%{"username" => raw_username} = _params, _uri, socket) do
        username = Data.parse_username(raw_username)
        viewer = socket.assigns[:current_user]

        case Data.load_header(username, viewer) do
          {:ok, profile} ->
            {:noreply,
             socket
             |> Phoenix.Component.assign(:state, :ready)
             |> Phoenix.Component.assign(:profile, profile)
             |> Phoenix.Component.assign(:permissions, Data.viewer_permissions(viewer))
             |> Phoenix.Component.assign(
               :page_title,
               Data.page_title(profile, @profile_title_suffix)
             )}

          {:error, :not_found} ->
            {:noreply,
             socket
             |> Phoenix.Component.assign(:state, :not_found)
             |> Phoenix.Component.assign(:page_title, "User not found · Kaguya")}
        end
      end

      @impl Phoenix.LiveView
      def handle_event("toggle_follow", params, socket) do
        Events.toggle_follow(socket, params)
      end

      defoverridable mount: 3, handle_params: 3, handle_event: 3
    end
  end
end
