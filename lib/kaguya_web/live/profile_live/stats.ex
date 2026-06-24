defmodule KaguyaWeb.ProfileLive.Stats do
  @moduledoc """
  `/@:username/stats` — detailed reading stats dashboard.

  The charts are intentionally server-rendered: CSS/SVG bars and donuts for
  stable first paint, with the shared ratings surfaces reused where parity
  depends on the existing app-wide treatment.
  """

  use KaguyaWeb.ProfileLive, tab: :stats, title_suffix: "Stats"

  import KaguyaWeb.Components.Profile.Stats.Distributions
  import KaguyaWeb.Components.Profile.Stats.Hero
  import KaguyaWeb.Components.Profile.Stats.ListProgress
  import KaguyaWeb.Components.Profile.Stats.MostLiked
  import KaguyaWeb.Components.Profile.Stats.Primitives
  import KaguyaWeb.Components.Profile.Stats.YearChart

  alias Kaguya.Users
  alias KaguyaWeb.Components.Profile.Placeholder
  alias KaguyaWeb.ProfileLive.StatsData

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> Phoenix.Component.assign(:state, :loading)
     |> Phoenix.Component.assign(:profile, nil)
     |> Phoenix.Component.assign(:stats, nil)
     |> Phoenix.Component.assign(:permissions, %{any?: false})
     |> Phoenix.Component.assign(:chart_metrics, %{release_year: :titles, read_year: :titles})
     |> Phoenix.Component.assign(:page_title, "Profile · Kaguya")
     |> Phoenix.Component.assign(:current_tab, :stats)
     |> Phoenix.Component.assign(:root?, false)}
  end

  @impl Phoenix.LiveView
  def handle_params(%{"username" => raw_username}, _uri, socket) do
    username = Data.parse_username(raw_username)
    viewer = socket.assigns[:current_user]

    with {:ok, profile} <- Data.load_header(username, viewer),
         {:ok, user} <- Users.get_user(profile.id) do
      {:noreply,
       socket
       |> Phoenix.Component.assign(:state, :ready)
       |> Phoenix.Component.assign(:profile, profile)
       |> Phoenix.Component.assign(:stats, StatsData.load_stats(user, profile, viewer))
       |> Phoenix.Component.assign(:permissions, Data.viewer_permissions(viewer))
       |> Phoenix.Component.assign(:page_title, Data.page_title(profile, "Stats"))
       |> Phoenix.Component.assign(KaguyaWeb.SEO.noindex())}
    else
      {:error, :not_found} ->
        {:noreply,
         socket
         |> Phoenix.Component.assign(:state, :not_found)
         |> Phoenix.Component.assign(:page_title, "User not found · Kaguya")}
    end
  end

  @impl Phoenix.LiveView
  def handle_event("set_stats_metric", %{"chart" => chart, "metric" => metric}, socket) do
    with {:ok, chart_key} <- parse_chart_key(chart),
         {:ok, metric_key} <- parse_metric_key(metric) do
      {:noreply,
       Phoenix.Component.update(socket, :chart_metrics, fn metrics ->
         Map.put(metrics || %{}, chart_key, metric_key)
       end)}
    else
      _ -> {:noreply, socket}
    end
  end

  defp parse_chart_key("release_year"), do: {:ok, :release_year}
  defp parse_chart_key("read_year"), do: {:ok, :read_year}
  defp parse_chart_key(_), do: :error

  defp parse_metric_key("titles"), do: {:ok, :titles}
  defp parse_metric_key("hours"), do: {:ok, :hours}
  defp parse_metric_key("scores"), do: {:ok, :scores}
  defp parse_metric_key(_), do: :error

  @impl Phoenix.LiveView
  def render(%{state: :not_found} = assigns), do: Placeholder.not_found(assigns)
  def render(%{state: :loading} = assigns), do: Placeholder.loading(assigns)

  def render(assigns) do
    ~H"""
    <main class="min-h-screen bg-[rgb(var(--surface-base))] pb-[110px] text-[rgb(var(--foreground-primary))] sm:pb-32 lg:pb-[99px]">
      <div class="mx-auto w-full md:max-lg:max-w-[768px] md:max-lg:px-6 lg:px-8 2xl:max-w-screen-2xl">
        <.stats_hero profile={@profile} stats={@stats} />

        <section class="mx-auto mt-10 flex flex-col gap-10 px-4 sm:px-8 lg:mt-0 lg:max-w-[902px] lg:gap-20 lg:px-0">
          <div class="space-y-10 lg:space-y-20">
            <.year_chart
              title="Release Year"
              color="#06D6A0"
              username={@profile.username}
              year_param="releaseYear"
              chart_key="release_year"
              active_metric={@chart_metrics.release_year}
              chart={@stats.release_year_chart}
            />
            <.year_chart
              title="Read Year"
              color="#00BBF9"
              username={@profile.username}
              year_param="readYear"
              chart_key="read_year"
              active_metric={@chart_metrics.read_year}
              chart={@stats.read_year_chart}
            />
          </div>

          <div class="grid grid-cols-1 gap-10 lg:grid-cols-2 lg:gap-20">
            <.ratings_section profile={@profile} />
            <.length_section
              username={@profile.username}
              items={@stats.length_items}
            />
          </div>

          <div class="grid grid-cols-1 gap-8 lg:grid-cols-2 lg:gap-20">
            <.bar_list_section
              title="VNs by Tags"
              items={@stats.most_read_tags}
              value_key={:count}
              color="#06D6A0"
              username={@profile.username}
              filter_key="tag"
            />
            <.bar_list_section
              title="Highest Rated Tags"
              items={@stats.highest_rated_tags}
              value_key={:rating}
              color="#00BBF9"
              username={@profile.username}
              filter_key="tag"
              rating
            />
          </div>

          <div class="grid grid-cols-1 gap-8 lg:grid-cols-2 lg:gap-20">
            <.bar_list_section
              title="Most Read Developers"
              items={@stats.most_read_producers}
              value_key={:count}
              color="#06D6A0"
              username={@profile.username}
              filter_key="producer"
              limit={8}
            />
            <.bar_list_section
              title="Highest Rated Developers"
              items={@stats.highest_rated_producers}
              value_key={:rating}
              color="#00BBF9"
              username={@profile.username}
              filter_key="producer"
              limit={8}
              rating
            />
          </div>

          <div class="grid grid-cols-1 gap-10 lg:grid-cols-2 lg:gap-20">
            <.donut_section
              title="Languages"
              username={@profile.username}
              filter_key="language"
              center_label="VNs"
              items={@stats.language_items}
            />
            <.donut_section
              title="Age Rating"
              username={@profile.username}
              filter_key="ageRating"
              center_label="VNs"
              items={@stats.age_items}
            />
          </div>

          <.list_progress_section items={@stats.curated_progress} />

          <.most_liked_section
            username={@profile.username}
            review={@stats.most_liked_review}
            list={@stats.most_liked_list}
          />

          <.empty_stats :if={!@stats.has_content?} />
        </section>
      </div>
    </main>
    """
  end
end
