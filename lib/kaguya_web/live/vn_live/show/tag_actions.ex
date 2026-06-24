defmodule KaguyaWeb.VNLive.Show.TagActions do
  @moduledoc false

  import Phoenix.Component, only: [assign: 2]
  import Phoenix.LiveView, only: [put_flash: 3]

  alias KaguyaWeb.VNLive.PageData
  alias KaguyaWeb.VNLive.Show.Data

  def vote_tag(socket, %{"tag-id" => tag_id, "vote" => value}) do
    case socket.assigns.current_user do
      %{id: _} = user ->
        case PageData.vote_tag(socket.assigns.slug, user, tag_id, value) do
          {:ok, {tags, votes}} ->
            {:noreply, Data.assign_tags(socket, tags, votes)}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, Data.format_error(reason))}
        end

      _ ->
        {:noreply, put_flash(socket, :error, "Sign in to vote on tags")}
    end
  end

  def clear_tag_vote(socket, %{"tag-id" => tag_id}) do
    case socket.assigns.current_user do
      %{id: _} = user ->
        case PageData.clear_tag_vote(socket.assigns.slug, user, tag_id) do
          {:ok, {tags, votes}} ->
            {:noreply, Data.assign_tags(socket, tags, votes)}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, Data.format_error(reason))}
        end

      _ ->
        {:noreply, put_flash(socket, :error, "Sign in to vote on tags")}
    end
  end

  def open_tag_dialog(socket, _params) do
    case socket.assigns.current_user do
      %{id: _} = user ->
        if Data.can_edit_content?(user) do
          {:noreply,
           assign(socket,
             tag_dialog_open: true,
             tag_query: "",
             tag_results: [],
             tag_search_error: nil
           )}
        else
          {:noreply, put_flash(socket, :error, "Your editing privileges have been revoked")}
        end

      _ ->
        {:noreply, put_flash(socket, :error, "Sign in to add tags")}
    end
  end

  def close_tag_dialog(socket, _params) do
    {:noreply,
     assign(socket,
       tag_dialog_open: false,
       tag_query: "",
       tag_results: [],
       tag_search_error: nil
     )}
  end

  def search_tags(socket, params) do
    query = get_in(params, ["tag_search", "query"]) || params["query"] || ""

    case socket.assigns.current_user do
      %{id: _} = user ->
        case PageData.search_tag_candidates(
               socket.assigns.slug,
               user,
               query,
               Data.current_tag_ids(socket)
             ) do
          {:ok, results} ->
            {:noreply,
             assign(socket, tag_query: query, tag_results: results, tag_search_error: nil)}

          {:error, reason} ->
            {:noreply,
             assign(socket,
               tag_query: query,
               tag_results: [],
               tag_search_error: Data.format_error(reason)
             )}
        end

      _ ->
        {:noreply, put_flash(socket, :error, "Sign in to add tags")}
    end
  end

  def add_tag(socket, %{"tag-id" => tag_id}) do
    case socket.assigns.current_user do
      %{id: _} = user ->
        case PageData.vote_tag(socket.assigns.slug, user, tag_id, 4) do
          {:ok, {tags, votes}} ->
            {:noreply,
             socket
             |> Data.assign_tags(tags, votes)
             |> assign(
               tag_dialog_open: false,
               tag_query: "",
               tag_results: [],
               tag_search_error: nil
             )}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, Data.format_error(reason))}
        end

      _ ->
        {:noreply, put_flash(socket, :error, "Sign in to add tags")}
    end
  end
end
