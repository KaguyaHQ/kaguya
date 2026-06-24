defmodule KaguyaWeb.VNLive.Show.RecommendationActions do
  @moduledoc false

  import Phoenix.Component, only: [assign: 2]
  import Phoenix.LiveView, only: [put_flash: 3]

  alias KaguyaWeb.VNLive.PageData
  alias KaguyaWeb.VNLive.Show.Data

  def open_recommendation_dialog(socket, _params) do
    case socket.assigns.current_user do
      %{id: _} ->
        {:noreply,
         assign(socket,
           recommendation_dialog_open: true,
           recommendation_slug: "",
           recommendation_query: "",
           recommendation_results: [],
           recommendation_search_error: nil
         )}

      _ ->
        {:noreply, put_flash(socket, :error, "Sign in to recommend a visual novel")}
    end
  end

  def open_recommendation_search(socket, params), do: open_recommendation_dialog(socket, params)

  def close_recommendation_dialog(socket, _params),
    do: {:noreply, assign(socket, recommendation_dialog_open: false)}

  def search_recommendations(socket, %{"recommendation_search_query" => query}),
    do: search_recommendation_results(query, socket)

  def search_recommendations(socket, %{"recommendation_search" => %{"query" => query}}),
    do: search_recommendation_results(query, socket)

  def add_recommendation(socket, %{"id" => similar_vn_id} = params) do
    cached =
      Enum.find(socket.assigns.recommendation_results || [], fn r ->
        to_string(r.id) == to_string(similar_vn_id)
      end)

    enriched = %{
      "vn-id" => to_string(similar_vn_id),
      "slug" => Map.get(params, "slug") || (cached && cached.slug),
      "title" => Map.get(params, "title") || (cached && cached.title),
      "image-url" =>
        Map.get(params, "image_url") || Map.get(params, "image-url") ||
          (cached && cached.image_url)
    }

    add_recommendation(socket, enriched)
  end

  def add_recommendation(socket, %{"vn-id" => similar_vn_id} = params) do
    case socket.assigns.current_user do
      %{id: _} = user ->
        previous = socket.assigns.recommendations
        optimistic = optimistic_recommendation_add(previous, params)
        socket = assign(socket, recommendations: optimistic, recommendation_dialog_open: false)

        case PageData.add_recommendation_by_id(socket.assigns.slug, user, similar_vn_id) do
          {:ok, recommendations} ->
            {:noreply,
             assign(socket,
               recommendations:
                 prioritize_recommendation(recommendations, optimistic, similar_vn_id)
             )}

          {:error, reason} ->
            {:noreply,
             socket
             |> assign(recommendations: previous)
             |> put_flash(:error, Data.format_error(reason))}
        end

      _ ->
        {:noreply, put_flash(socket, :error, "Sign in to recommend a visual novel")}
    end
  end

  def add_recommendation(socket, %{"recommendation" => %{"slug" => similar_slug}}) do
    case socket.assigns.current_user do
      %{id: _} = user ->
        case PageData.add_recommendation(socket.assigns.slug, user, similar_slug) do
          {:ok, recommendations} ->
            {:noreply,
             assign(socket, recommendations: recommendations, recommendation_dialog_open: false)}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, Data.format_error(reason))}
        end

      _ ->
        {:noreply, put_flash(socket, :error, "Sign in to recommend a visual novel")}
    end
  end

  def vote_recommendation(socket, %{"vn-id" => vn_id, "vote" => vote}) do
    case socket.assigns.current_user do
      %{id: _} = user ->
        previous = socket.assigns.recommendations
        {next_vote, optimistic} = optimistic_recommendation_vote(previous, vn_id, vote)

        socket = assign(socket, recommendations: optimistic)

        case PageData.vote_recommendation(socket.assigns.slug, user, vn_id, next_vote) do
          {:ok, recommendations} ->
            {:noreply, assign(socket, recommendations: recommendations)}

          {:error, reason} ->
            {:noreply,
             socket
             |> assign(recommendations: previous)
             |> put_flash(:error, Data.format_error(reason))}
        end

      _ ->
        {:noreply, put_flash(socket, :error, "Sign in to vote on recommendations")}
    end
  end

  defp search_recommendation_results(query, socket) do
    case PageData.search_recommendation_candidates(
           socket.assigns.slug,
           socket.assigns.current_user,
           query
         ) do
      {:ok, results} ->
        {:noreply,
         assign(socket,
           recommendation_query: query,
           recommendation_results:
             reject_existing_recommendations(results, socket.assigns.recommendations),
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

  defp prioritize_recommendation(recommendations, optimistic, vn_id) do
    optimistic_entry =
      Enum.find(optimistic, &(to_string(&1.visual_novel.id) == to_string(vn_id)))

    cond do
      is_nil(optimistic_entry) ->
        recommendations

      Enum.any?(recommendations, &(to_string(&1.visual_novel.id) == to_string(vn_id))) ->
        server_entry =
          Enum.find(recommendations, &(to_string(&1.visual_novel.id) == to_string(vn_id)))

        rest =
          Enum.reject(recommendations, &(to_string(&1.visual_novel.id) == to_string(vn_id)))

        [server_entry | rest]

      true ->
        [optimistic_entry | recommendations]
    end
  end

  defp reject_existing_recommendations(results, recommendations) do
    existing_ids =
      recommendations
      |> Enum.map(&to_string(&1.visual_novel.id))
      |> MapSet.new()

    Enum.reject(results, &(to_string(&1.id) in existing_ids))
  end
end
