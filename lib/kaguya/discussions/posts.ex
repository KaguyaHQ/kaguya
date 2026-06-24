defmodule Kaguya.Discussions.Posts do
  @moduledoc false

  import Ecto.Query

  alias Kaguya.CursorPagination
  alias Kaguya.Repo
  alias Kaguya.Discussions.{Comment, Pins, Policy, Post, Query, SideEffects}
  alias Kaguya.Users.User

  @hour_ms :timer.hours(1)
  @max_pinned 6

  def create_post(user_id, attrs, opts \\ []) do
    category_type = Map.get(attrs, :category_type)

    with :ok <- Policy.check_admin_only_category(category_type, user_id, opts),
         :ok <- Policy.validate_target_entity(category_type, Map.get(attrs, :entity_id), user_id) do
      case Kaguya.RateLimit.hit("post:#{user_id}", @hour_ms, 5) do
        {:deny, _} ->
          {:error, "Rate limit exceeded. Please try again later."}

        {:allow, _} ->
          now = DateTime.utc_now() |> DateTime.truncate(:second)
          full_attrs = Map.put(attrs, :user_id, user_id)

          result =
            Repo.transact(fn ->
              %Post{last_comment_at: now}
              |> Post.changeset(full_attrs)
              |> Repo.insert()
            end)

          with {:ok, post} <- result do
            SideEffects.record_post_activity(user_id, post)
            SideEffects.notify_target_user(post, user_id)
            {:ok, post}
          end
      end
    end
  end

  def get_post(id) do
    case Repo.get(Post, id) do
      nil -> {:error, :not_found}
      post -> {:ok, post}
    end
  end

  def get_post_for_viewer(id, viewer_id, viewer \\ %{}) do
    with {:ok, post} <- get_post(id) do
      Policy.check_visible(post, viewer_id, viewer)
    end
  end

  def get_post_by_short_id(short_id) when is_binary(short_id) do
    case Repo.get_by(Post, short_id: short_id) do
      nil -> {:error, :not_found}
      post -> {:ok, post}
    end
  end

  def get_post_by_short_id_for_viewer(short_id, viewer_id, viewer \\ %{}) do
    with {:ok, post} <- get_post_by_short_id(short_id) do
      Policy.check_visible(post, viewer_id, viewer)
    end
  end

  # View-mode lookups: never 404 a hidden post — return a scrubbed copy so
  # the page renders a tombstone. Action paths must keep using the strict
  # _for_viewer variants above.
  def get_post_for_view(id, viewer_id, viewer \\ %{}) do
    with {:ok, post} <- get_post(id) do
      {:ok, Policy.scrub_for_viewer(post, viewer_id, viewer)}
    end
  end

  def get_post_by_short_id_for_view(short_id, viewer_id, viewer \\ %{}) do
    with {:ok, post} <- get_post_by_short_id(short_id) do
      {:ok, Policy.scrub_for_viewer(post, viewer_id, viewer)}
    end
  end

  def update_post(post_id, user_id, attrs) do
    with {:ok, post} <- Policy.get_post_by_owner(post_id, user_id),
         :ok <- Policy.check_not_deleted(post),
         :ok <- Policy.check_title_unlocked(post, attrs) do
      post
      |> Post.changeset(Map.put(attrs, :is_edited, true))
      |> Repo.update()
    end
  end

  def admin_moderate_post(post_id, attrs) do
    with {:ok, post} <- get_post(post_id),
         :ok <- Policy.check_not_deleted(post),
         :ok <- Pins.ensure_post_pin_capacity(attrs, post.category_type) do
      post
      |> Ecto.Changeset.change(Map.take(attrs, [:is_pinned, :is_locked]))
      |> Repo.update()
    end
  end

  def admin_lock_post(post_id) do
    with {:ok, post} <- get_post(post_id),
         :ok <- Policy.check_not_deleted(post) do
      post |> Ecto.Changeset.change(is_locked: true) |> Repo.update()
    end
  end

  def admin_unlock_post(post_id) do
    with {:ok, post} <- get_post(post_id),
         :ok <- Policy.check_not_deleted(post) do
      post |> Ecto.Changeset.change(is_locked: false) |> Repo.update()
    end
  end

  # ============================================================================
  # Post Listing
  # ============================================================================

  def list_posts(opts \\ %{}) do
    category_type = Map.get(opts, :category_type)
    entity_id = Map.get(opts, :entity_id)
    sort_by = Map.get(opts, :sort_by, :recent_activity)
    cursor = Map.get(opts, :cursor)
    limit = Map.get(opts, :limit, 20)
    viewer_id = Map.get(opts, :viewer_id)

    base =
      Post
      |> Query.maybe_filter_category(category_type)
      |> Query.maybe_filter_entity(entity_id)
      |> Query.filter_hidden(viewer_id)

    {fields, types} = Query.cursor_config(sort_by)

    {items, next_cursor, has_next} =
      CursorPagination.paginate(base, fields, types, cursor, limit, :desc)

    {:ok, %{items: items, next_cursor: next_cursor, has_next: has_next}}
  end

  def list_posts_for_entity(category_type, entity_id, opts \\ %{}) do
    opts
    |> Map.put(:category_type, category_type)
    |> Map.put(:entity_id, entity_id)
    |> list_posts()
  end

  def list_posts_for_user(user_id, opts \\ %{}) do
    cursor = Map.get(opts, :cursor)
    limit = Map.get(opts, :limit, 20)
    viewer_id = Map.get(opts, :viewer_id)

    base =
      from(t in Post,
        where:
          (t.user_id == ^user_id or (t.category_type == :user and t.entity_id == ^user_id)) and
            is_nil(t.deleted_at)
      )

    {items, next_cursor, has_next} =
      CursorPagination.paginate(
        base,
        [:inserted_at, :id],
        [:datetime, :string],
        cursor,
        limit,
        :desc
      )

    items = Enum.map(items, &Policy.scrub_hidden_for_profile(&1, viewer_id))

    {:ok, %{items: items, next_cursor: next_cursor, has_next: has_next}}
  end

  def list_pinned_posts(category_type \\ nil, viewer_id \\ nil) do
    base =
      from(t in Post,
        where: t.is_pinned == true,
        order_by: [desc: t.last_comment_at],
        limit: @max_pinned
      )
      |> Query.maybe_filter_category(category_type)
      |> Query.filter_hidden(viewer_id)

    {:ok, Repo.all(base)}
  end

  def recent_comment_users_by_post_ids(post_ids, limit \\ 3) when is_list(post_ids) do
    ids = Enum.uniq(post_ids)

    latest_per_user =
      from(c in Comment,
        join: p in assoc(c, :post),
        where:
          c.post_id in ^ids and c.user_id != p.user_id and is_nil(c.hidden_at) and
            is_nil(c.deleted_at),
        group_by: [c.post_id, c.user_id],
        select: %{
          post_id: c.post_id,
          user_id: c.user_id,
          latest_at: max(c.inserted_at)
        }
      )

    ranked =
      from(c in subquery(latest_per_user),
        windows: [post: [partition_by: c.post_id, order_by: [desc: c.latest_at, desc: c.user_id]]],
        select: %{
          post_id: c.post_id,
          user_id: c.user_id,
          position: over(row_number(), :post)
        }
      )

    rows =
      Repo.all(
        from(c in subquery(ranked),
          join: u in User,
          on: u.id == c.user_id,
          where: c.position <= ^limit,
          order_by: [asc: c.post_id, asc: c.position],
          select: {c.post_id, u}
        )
      )

    empty_results = Map.new(ids, &{&1, []})

    Enum.reduce(rows, empty_results, fn {post_id, user}, results ->
      Map.update!(results, post_id, &(&1 ++ [user]))
    end)
  end

  def title_locked?(post), do: Policy.title_locked?(post)
end
