defmodule KaguyaWeb.VNLive.Similar do
  use KaguyaWeb, :live_view

  alias KaguyaWeb.VNLive.PageData
  alias KaguyaWeb.Components.Shared.NotFoundPage
  alias KaguyaWeb.VN.Similar

  @page_limit 72

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(KaguyaWeb.SEO.noindex())
     |> assign(
       slug: nil,
       page_title: "Similar visual novels · Kaguya",
       vn: nil,
       recommendations: [],
       recommendation_dialog_open: false,
       recommendation_query: "",
       recommendation_results: [],
       recommendation_search_error: nil,
       loading: true,
       not_found?: false
     )}
  end

  @impl true
  def handle_params(%{"slug" => slug}, _uri, socket) do
    case PageData.get_similar_page(slug, socket.assigns.current_user, limit: @page_limit) do
      {:ok, page_data} ->
        {:noreply,
         assign(socket,
           slug: slug,
           page_title: "Similar to #{page_data.vn.title} · Kaguya",
           vn: page_data.vn,
           recommendations: page_data.recommendations,
           recommendation_dialog_open: false,
           recommendation_query: "",
           recommendation_results: [],
           recommendation_search_error: nil,
           loading: false
         )}

      {:error, :not_found} ->
        {:noreply,
         assign(socket,
           slug: slug,
           page_title: "Visual novel not found · Kaguya",
           not_found?: true,
           loading: false
         )}
    end
  end

  @impl true
  def handle_event("open_recommendation_dialog", _params, socket) do
    cond do
      is_nil(socket.assigns.current_user) ->
        {:noreply, put_flash(socket, :error, "Sign in to add similar VNs")}

      !can_edit?(socket.assigns.current_user) ->
        {:noreply, put_flash(socket, :error, "Your editing privileges have been revoked")}

      true ->
        {:noreply,
         assign(socket,
           recommendation_dialog_open: true,
           recommendation_query: "",
           recommendation_results: [],
           recommendation_search_error: nil
         )}
    end
  end

  def handle_event("close_recommendation_dialog", _params, socket),
    do: {:noreply, assign(socket, recommendation_dialog_open: false)}

  def handle_event(
        "search_recommendations",
        %{"recommendation_search" => %{"query" => query}},
        socket
      ) do
    case PageData.search_recommendation_candidates(
           socket.assigns.slug,
           socket.assigns.current_user,
           query
         ) do
      {:ok, results} ->
        {:noreply,
         assign(socket,
           recommendation_query: query,
           recommendation_results: reject_existing(results, socket.assigns.recommendations),
           recommendation_search_error: nil
         )}

      {:error, _reason} ->
        {:noreply,
         assign(socket,
           recommendation_query: query,
           recommendation_results: [],
           recommendation_search_error: "Search is temporarily unavailable"
         )}
    end
  end

  def handle_event("add_recommendation", %{"vn-id" => similar_vn_id} = params, socket) do
    with {:user, %{id: _} = user} <- {:user, socket.assigns.current_user},
         :ok <- require_can_edit(user) do
      previous = socket.assigns.recommendations
      optimistic = optimistic_recommendation_add(previous, params)

      socket =
        assign(socket,
          recommendations: optimistic,
          recommendation_dialog_open: false
        )

      case PageData.add_recommendation_by_id(socket.assigns.slug, user, similar_vn_id,
             limit: @page_limit
           ) do
        {:ok, recommendations} ->
          {:noreply, assign(socket, recommendations: recommendations)}

        {:error, reason} ->
          {:noreply,
           socket
           |> assign(recommendations: previous)
           |> put_flash(:error, format_error(reason))}
      end
    else
      {:user, _} -> {:noreply, put_flash(socket, :error, "Sign in to add similar VNs")}
      {:error, reason} -> {:noreply, put_flash(socket, :error, format_error(reason))}
    end
  end

  def handle_event("vote_recommendation", %{"vn-id" => vn_id, "vote" => vote}, socket) do
    with {:user, %{id: _} = user} <- {:user, socket.assigns.current_user},
         :ok <- require_can_edit(user) do
      previous = socket.assigns.recommendations
      {next_vote, optimistic} = optimistic_recommendation_vote(previous, vn_id, vote)
      socket = assign(socket, recommendations: optimistic)

      case PageData.vote_recommendation(socket.assigns.slug, user, vn_id, next_vote,
             limit: @page_limit
           ) do
        {:ok, recommendations} ->
          {:noreply, assign(socket, recommendations: recommendations)}

        {:error, reason} ->
          {:noreply,
           socket
           |> assign(recommendations: previous)
           |> put_flash(:error, format_error(reason))}
      end
    else
      {:user, _} -> {:noreply, put_flash(socket, :error, "Sign in to vote on recommendations")}
      {:error, reason} -> {:noreply, put_flash(socket, :error, format_error(reason))}
    end
  end

  @impl true
  def render(%{not_found?: true} = assigns) do
    ~H"""
    <NotFoundPage.not_found_page variant={:overlay} />
    """
  end

  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-[rgb(var(--surface-base))] pb-20 text-[rgb(var(--foreground-primary))]">
      <%= if @loading or is_nil(@vn) do %>
        <div class="mx-auto max-w-6xl px-4 py-20 text-sm text-[rgb(var(--foreground-tertiary))]">
          Loading similar visual novels...
        </div>
      <% else %>
        <Similar.page vn={@vn} recommendations={@recommendations} />
      <% end %>

      <Similar.add_dialog
        :if={@recommendation_dialog_open}
        query={@recommendation_query}
        results={@recommendation_results}
        error={@recommendation_search_error}
      />
    </div>
    """
  end

  defp optimistic_recommendation_vote(recommendations, vn_id, vote) do
    desired = if vote in ["1", 1, "up", :up], do: 1, else: -1

    {next_vote, _current_vote} =
      recommendations
      |> Enum.find_value({desired, 0}, fn entry ->
        if to_string(entry.visual_novel.id) == to_string(vn_id) do
          current = entry.user_vote || 0
          next = if current == desired, do: 0, else: desired
          {next, current}
        end
      end)

    optimistic =
      Enum.map(recommendations, fn entry ->
        if to_string(entry.visual_novel.id) == to_string(vn_id) do
          current = entry.user_vote || 0
          %{entry | user_vote: next_vote, net_votes: entry.net_votes + next_vote - current}
        else
          entry
        end
      end)

    {next_vote, optimistic}
  end

  defp optimistic_recommendation_add(recommendations, %{"vn-id" => vn_id} = params) do
    if Enum.any?(recommendations, &(to_string(&1.visual_novel.id) == to_string(vn_id))) do
      recommendations
    else
      [
        %{
          net_votes: 1,
          user_vote: 1,
          visual_novel: %{
            id: vn_id,
            slug: params["slug"],
            title: params["title"] || "Recommended VN",
            has_ero: false,
            images: %{
              small: params["image-url"],
              medium: params["image-url"],
              large: params["image-url"]
            },
            average_rating: nil,
            vndb_rating: nil
          }
        }
        | recommendations
      ]
    end
  end

  defp reject_existing(results, recommendations) do
    existing_ids =
      recommendations
      |> Enum.map(&to_string(&1.visual_novel.id))
      |> MapSet.new()

    Enum.reject(results, &(to_string(&1.id) in existing_ids))
  end

  defp require_can_edit(%{can_edit: false}), do: {:error, :permission_denied}
  defp require_can_edit(%{id: _}), do: :ok

  defp can_edit?(%{can_edit: false}), do: false
  defp can_edit?(%{id: _}), do: true
  defp can_edit?(_), do: false

  defp format_error(:permission_denied), do: "Your editing privileges have been revoked"
  defp format_error(:same_visual_novel), do: "Choose a different visual novel"

  defp format_error(%Ecto.Changeset{} = changeset) do
    Enum.map_join(changeset.errors, ", ", fn {field, {message, _}} ->
      "#{Phoenix.Naming.humanize(field)} #{message}"
    end)
  end

  defp format_error(reason), do: inspect(reason)
end
