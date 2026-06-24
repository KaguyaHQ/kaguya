defmodule KaguyaWeb.VNLive.Show.Data do
  @moduledoc false

  import Phoenix.Component, only: [assign: 2, assign: 3, update: 3]
  import Phoenix.LiveView, only: [put_flash: 3]

  alias KaguyaWeb.VNLive.PageData
  alias KaguyaWeb.VNLive.Show.Filters

  def assign_viewer_bundle(socket, bundle) do
    socket =
      assign(socket,
        viewer_bundle: bundle,
        viewer: bundle.viewer,
        viewer_vn: bundle.viewer_vn,
        display_vn: build_display_vn(socket.assigns.public_vn, bundle.viewer_vn),
        pending_status: nil,
        pending_rating: nil
      )

    socket = apply_my_votes(socket, Map.get(bundle, :my_votes))

    # The first-paint async bundle carries only controls data; friend data
    # streams in separately (`assign_friends/2`). Mutation-path bundles carry
    # both, so assign the friend slice only when it's present.
    case bundle do
      %{friend_activity: friend_activity, friend_reviews: friend_reviews} ->
        assign(socket, friend_activity: friend_activity, friend_reviews: friend_reviews)

      _ ->
        socket
    end
  end

  # Overlays the viewer's own tag/recommendation votes onto the vote-less
  # public core (Phase 2a). The core is cached viewer-independently, so the
  # `:vn_viewer` bundle carries `my_votes` and re-attaches the highlights —
  # tags' `my_vote` and recommendations' `user_vote` — once it lands.
  defp apply_my_votes(socket, nil), do: socket

  defp apply_my_votes(socket, %{tags: tag_votes, recommendations: recommendation_votes}) do
    socket
    |> overlay_tag_votes(tag_votes)
    |> overlay_recommendation_votes(recommendation_votes)
  end

  defp overlay_tag_votes(socket, votes) when map_size(votes) == 0, do: socket

  defp overlay_tag_votes(socket, votes) do
    overlay = fn tags -> Enum.map(tags, &Map.put(&1, :my_vote, Map.get(votes, &1.id))) end

    socket
    |> update(:public_vn, &Map.update(&1, :tags, [], overlay))
    |> update(:display_vn, &Map.update(&1, :tags, [], overlay))
    |> update(:tabs, fn tabs ->
      Map.update(tabs, :tags, {:ok, []}, fn
        {:ok, tags} -> {:ok, overlay.(tags)}
        other -> other
      end)
    end)
  end

  defp overlay_recommendation_votes(socket, votes) when map_size(votes) == 0, do: socket

  defp overlay_recommendation_votes(socket, votes) do
    update(socket, :recommendations, fn recs ->
      Enum.map(recs, &Map.put(&1, :user_vote, Map.get(votes, &1.visual_novel.id)))
    end)
  end

  def assign_friends(socket, %{friend_activity: friend_activity, friend_reviews: friend_reviews}) do
    assign(socket, friend_activity: friend_activity, friend_reviews: friend_reviews)
  end

  def rollback_bundle(socket, previous, reason) do
    socket
    |> assign_viewer_bundle(previous)
    |> put_flash(:error, inspect(reason))
  end

  def build_display_vn(public_vn, nil), do: public_vn

  def build_display_vn(public_vn, viewer_vn) do
    public_vn
    |> Map.put(:average_rating, viewer_vn.average_rating || public_vn.average_rating)
    |> Map.put(:ratings_count, viewer_vn.ratings_count || public_vn.ratings_count)
    |> Map.put(:ratings_dist, viewer_vn.ratings_dist || public_vn.ratings_dist)
  end

  def build_tabs(vn, page_data) do
    %{
      tags: {:ok, vn.tags},
      covers: Map.get(page_data, :covers, :not_loaded),
      screenshots: Map.get(page_data, :screenshots, :not_loaded),
      releases: Map.get(page_data, :releases, :not_loaded),
      quotes: Map.get(page_data, :quotes, :not_loaded)
    }
  end

  # Post-mutation tag assignment (vote / clear-vote / add-tag). Sets the fresh
  # vote-less tag list, then overlays the viewer's own votes through the *same*
  # `overlay_tag_votes/2` first paint uses (`apply_my_votes/2`). `my_vote` is
  # attached in exactly one place on this page — never baked into the list.
  def assign_tags(socket, tags, votes \\ %{}) do
    public_vn = Map.put(socket.assigns.public_vn, :tags, tags)
    display_vn = Map.put(socket.assigns.display_vn, :tags, tags)

    socket
    |> assign(public_vn: public_vn, display_vn: display_vn)
    |> update(:tabs, fn tabs -> Map.put(tabs, :tags, {:ok, tags}) end)
    |> overlay_tag_votes(votes)
  end

  def current_tag_ids(socket) do
    case get_in(socket.assigns, [:tabs, :tags]) do
      {:ok, tags} when is_list(tags) -> Enum.map(tags, & &1.id)
      _ -> []
    end
  end

  def maybe_clear_rating_for_status(bundle, "NOT_INTERESTED"),
    do: put_in(bundle, [:viewer_vn, :my_rating], nil)

  def maybe_clear_rating_for_status(bundle, _), do: bundle

  def ensure_read_status(bundle) do
    if get_in(bundle, [:viewer_vn, :my_reading_status]) == nil do
      put_in(bundle, [:viewer_vn, :my_reading_status], %{status: "READ"})
    else
      bundle
    end
  end

  def liked_review_ids(nil), do: []
  def liked_review_ids(viewer_vn), do: viewer_vn.my_review_likes || []

  def can_edit_db?(%{role: role}) when role in [:admin, "admin"], do: true
  def can_edit_db?(%{mod_db: true}), do: true
  def can_edit_db?(_), do: false

  def can_edit_content?(%{can_edit: false}), do: false
  def can_edit_content?(%{id: _}), do: true
  def can_edit_content?(_), do: false

  def format_error(%Ecto.Changeset{} = changeset) do
    Enum.map_join(changeset.errors, ", ", fn {field, {message, _}} ->
      "#{Phoenix.Naming.humanize(field)} #{message}"
    end)
  end

  def format_error(reason), do: inspect(reason)

  def update_tab_items(socket, tab, fun) do
    update(socket, :tabs, fn tabs ->
      Map.update!(tabs, tab, fn
        {:ok, items} -> {:ok, fun.(items)}
        other -> other
      end)
    end)
  end

  def update_tab_item(socket, tab, id, fun) do
    items =
      case socket.assigns.tabs[tab] do
        {:ok, items} -> items
        _ -> []
      end

    Enum.reduce_while(items, {false, socket}, fn item, {_metadata, socket} ->
      if to_string(item.id) == to_string(id) do
        {metadata, updated_item} = fun.(item)

        socket =
          update_tab_items(socket, tab, fn items ->
            Enum.map(items, &if(to_string(&1.id) == to_string(id), do: updated_item, else: &1))
          end)

        {:halt, {metadata, socket}}
      else
        {:cont, {false, socket}}
      end
    end)
  end

  # Targeted refresh after a single-review write. Re-fetches only the
  # reviews list + the four denormalized VN counters that a review
  # write can change — never the unchanged sections (discussions,
  # characters, covers, recommendations, …). The clean LV idiom:
  # update the slice that mutated, leave the rest of the socket alone.
  def refresh_reviews_section(socket) do
    page = socket.assigns.reviews.pagination.page
    sort = Filters.sort_atom(socket.assigns.reviews_sort)

    case PageData.get_reviews_page(socket.assigns.slug, page: page, sort: sort) do
      {:ok, %{reviews: reviews, counters: counters}} ->
        socket
        |> assign(:reviews, reviews)
        |> update(:public_vn, &Map.merge(&1, counters))
        |> update(:display_vn, &Map.merge(&1, counters))

      _ ->
        socket
    end
  end
end
