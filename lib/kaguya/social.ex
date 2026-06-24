defmodule Kaguya.Social do
  import Ecto.Query

  alias Kaguya.Repo
  alias Kaguya.Social.{Notification, ProducerFollow, UserFollow}
  alias Kaguya.Users.User
  alias Kaguya.Producers.Producer
  alias Kaguya.CursorPagination
  alias Kaguya.Activities

  # ---------------------------------
  # Following & Feed
  # ---------------------------------

  def follow_user(follower_id, followed_id) do
    result =
      Repo.transact(fn ->
        with {:ok, %User{} = followed} <- get_user(followed_id) do
          cond do
            follower_id == followed_id ->
              {:error, "A user cannot follow themselves"}

            follows?(follower_id, followed_id) ->
              {:ok, :no_activity}

            true ->
              with {:ok, _user_follow} <- create_user_follow(follower_id, followed_id),
                   {:ok, _notification} <-
                     create_notification(%{
                       user_id: followed_id,
                       action: :follow,
                       entity_type: :user,
                       entity_id: followed_id,
                       actor_id: follower_id,
                       idempotency_key: follow_idempotency_key(follower_id, followed_id)
                     }) do
                {:ok, followed}
              end
          end
        end
      end)

    with {:ok, %User{} = followed} <- result do
      record_follow_activity(follower_id, followed)
      {:ok, true}
    else
      {:ok, :no_activity} -> {:ok, true}
      other -> other
    end
  end

  @doc """
  Viewer-scoped follow state:
  - :self
  - :following
  - :not_following
  """
  def follow_state(nil, _target_id), do: :not_following
  def follow_state(viewer_id, target_id) when viewer_id == target_id, do: :self

  def follow_state(viewer_id, target_id) do
    if follows?(viewer_id, target_id), do: :following, else: :not_following
  end

  defp create_user_follow(follower_id, followed_id) do
    %UserFollow{}
    |> UserFollow.changeset(%{follower_id: follower_id, followed_id: followed_id})
    |> Repo.insert()
  end

  defp get_user(user_id) do
    case Repo.get(User, user_id) do
      nil -> {:error, :not_found}
      %User{} = user -> {:ok, user}
    end
  end

  defp follow_idempotency_key(follower_id, followed_id) do
    "follow:#{follower_id}:#{followed_id}"
  end

  @doc """
  Unfollow: deletes the follow relationship if exists.
  Returns {:ok, count} of deleted rows (0 or 1).
  """
  def unfollow_user(follower_id, followed_id) do
    query =
      from uf in UserFollow,
        where: uf.follower_id == ^follower_id and uf.followed_id == ^followed_id

    {count, _} = Repo.delete_all(query)
    Activities.delete_activity(follower_id, :followed, "user", followed_id)
    {:ok, count}
  end

  @doc """
  Checks if `follower_id` follows `followed_id`.
  Returns true/false.
  """
  def follows?(follower_id, followed_id) do
    query =
      from uf in UserFollow,
        where: uf.follower_id == ^follower_id and uf.followed_id == ^followed_id

    Repo.exists?(query)
  end

  @doc """
  Batch: given a follower_id and a list of target user IDs, returns
  a MapSet of IDs that the follower is following.
  """
  def batch_followed_ids(follower_id, target_ids) do
    target_ids = Enum.uniq(target_ids)

    from(uf in UserFollow,
      where: uf.follower_id == ^follower_id and uf.followed_id in ^target_ids,
      select: uf.followed_id
    )
    |> Repo.all()
    |> MapSet.new()
  end

  @doc """
  Lists all followers for a given username.
  Returns a list of user records who follow the username.
  """

  def list_followers(username, cursor \\ nil, limit \\ 10) do
    base_query =
      from(uf in UserFollow,
        join: target_user in User,
        on: target_user.id == uf.followed_id,
        join: follower_user in User,
        on: follower_user.id == uf.follower_id,
        where: target_user.username == ^username,
        select: %{user_id: uf.follower_id, inserted_at: uf.inserted_at}
      )

    # Wrap base_query in a subquery and paginate
    query = from(f in subquery(base_query))

    {items, next_cursor, has_next} =
      CursorPagination.paginate_by_cursor(
        query,
        :inserted_at,
        cursor,
        limit,
        :desc
      )

    # Fetch the full User records and maintain order
    user_ids = Enum.map(items, & &1.user_id)

    users_map =
      from(u in User, where: u.id in ^user_ids)
      |> Repo.all()
      |> Map.new(&{&1.id, &1})

    user_items = Enum.map(items, fn %{user_id: user_id} -> users_map[user_id] end)

    {:ok, %{items: user_items, next_cursor: next_cursor, has_next: has_next}}
  end

  @doc """
  Lists all users that a given username is following.
  Returns a list of user records the username follows.
  """
  def list_following(username, cursor \\ nil, limit \\ 10) do
    case Repo.get_by(User, username: username) do
      nil -> {:ok, %{items: [], next_cursor: nil, has_next: false}}
      user -> list_following_by_user_id(user.id, cursor, limit)
    end
  end

  def list_following_by_user_id(user_id, cursor \\ nil, limit \\ 10) do
    base_query =
      from(uf in UserFollow,
        where: uf.follower_id == ^user_id,
        select: %{user_id: uf.followed_id, inserted_at: uf.inserted_at}
      )

    # Wrap base_query in a subquery and paginate
    query = from(u in subquery(base_query))

    {items, next_cursor, has_next} =
      CursorPagination.paginate_by_cursor(
        query,
        :inserted_at,
        cursor,
        limit,
        :desc
      )

    # Fetch the full User records and maintain order
    user_ids = Enum.map(items, & &1.user_id)

    users_map =
      from(u in User, where: u.id in ^user_ids)
      |> Repo.all()
      |> Map.new(&{&1.id, &1})

    user_items = Enum.map(items, fn %{user_id: user_id} -> users_map[user_id] end)

    {:ok, %{items: user_items, next_cursor: next_cursor, has_next: has_next}}
  end

  def get_follower_count(user_id) do
    from(uf in UserFollow,
      where: uf.followed_id == ^user_id,
      select: count(uf.follower_id)
    )
    |> Repo.one()
  end

  def get_following_count(user_id) do
    from(uf in UserFollow,
      where: uf.follower_id == ^user_id,
      select: count(uf.followed_id)
    )
    |> Repo.one()
  end

  # ---------------------------------
  # Following producers
  # ---------------------------------

  @doc """
  Idempotent follow. Returns `{:ok, %{follower_count: n, was_new: bool}}` on success.

  Idempotency: uses `insert_all` with `on_conflict: :nothing` and inspects the
  affected row count — `Repo.insert/2` with `on_conflict: :nothing` returns
  `{:ok, struct}` even when nothing was inserted (see note in `lib/kaguya.ex`),
  so we cannot rely on the tuple alone. The counter is only bumped when a new
  row was actually inserted.
  """
  def follow_producer(follower_id, producer_id)
      when is_binary(follower_id) and is_binary(producer_id) do
    result =
      Repo.transact(fn ->
        with {:ok, %Producer{} = producer} <- get_producer(producer_id) do
          now = DateTime.utc_now() |> DateTime.truncate(:second)

          {inserted, _} =
            Repo.insert_all(
              ProducerFollow,
              [
                %{
                  follower_id: follower_id,
                  producer_id: producer_id,
                  inserted_at: now,
                  updated_at: now
                }
              ],
              on_conflict: :nothing,
              conflict_target: [:follower_id, :producer_id]
            )

          if inserted == 1 do
            {1, _} =
              from(p in Producer, where: p.id == ^producer_id)
              |> Repo.update_all(inc: [follower_count: 1])
          end

          count = producer_follower_count(producer_id)
          {:ok, {producer, count, inserted == 1}}
        end
      end)

    case result do
      {:ok, {producer, count, true}} ->
        record_follow_producer_activity(follower_id, producer)
        {:ok, %{follower_count: count, was_new: true}}

      {:ok, {_producer, count, false}} ->
        {:ok, %{follower_count: count, was_new: false}}

      other ->
        other
    end
  end

  @doc """
  Idempotent unfollow. Returns `{:ok, %{follower_count: n, was_removed: bool}}`.
  """
  def unfollow_producer(follower_id, producer_id)
      when is_binary(follower_id) and is_binary(producer_id) do
    result =
      Repo.transact(fn ->
        {removed, _} =
          from(f in ProducerFollow,
            where: f.follower_id == ^follower_id and f.producer_id == ^producer_id
          )
          |> Repo.delete_all()

        if removed > 0 do
          from(p in Producer, where: p.id == ^producer_id)
          |> Repo.update_all(inc: [follower_count: -1])
        end

        count = producer_follower_count(producer_id)
        {:ok, %{follower_count: count, was_removed: removed > 0}}
      end)

    with {:ok, %{was_removed: true}} = ok <- result do
      Activities.delete_activity(follower_id, :followed, "producer", producer_id)
      ok
    end
  end

  @doc "Whether `follower_id` follows `producer_id`."
  def follows_producer?(nil, _producer_id), do: false

  def follows_producer?(follower_id, producer_id) do
    Repo.exists?(
      from f in ProducerFollow,
        where: f.follower_id == ^follower_id and f.producer_id == ^producer_id
    )
  end

  @doc """
  Batch: given a follower_id and a list of producer IDs, returns a MapSet of
  the producer IDs that the follower is currently following.
  """
  def batch_followed_producer_ids(follower_id, producer_ids) when is_binary(follower_id) do
    producer_ids = Enum.uniq(producer_ids)

    from(f in ProducerFollow,
      where: f.follower_id == ^follower_id and f.producer_id in ^producer_ids,
      select: f.producer_id
    )
    |> Repo.all()
    |> MapSet.new()
  end

  def batch_followed_producer_ids(_, _), do: MapSet.new()

  @doc """
  Cursor-paginated list of users following the given producer, newest first.

  Mirrors `Kaguya.Characters.list_favoriters_of/2` so producer followers
  match character favoriters — the frontend's list components expect
  identical `{user, ..._at}` rows.
  """
  def list_producer_followers(producer_id, opts \\ []) do
    cursor = Keyword.get(opts, :cursor)
    limit = Keyword.get(opts, :limit, 20)

    # Two cursor columns (inserted_at + follower_id) so rows with identical
    # timestamps still paginate deterministically. The select must include
    # the column atoms by their real names so CursorPagination can read
    # them off the resulting rows.
    query =
      from pf in ProducerFollow,
        join: u in assoc(pf, :follower),
        where: pf.producer_id == ^producer_id,
        select: %{
          user: u,
          followed_at: pf.inserted_at,
          id: u.id,
          inserted_at: pf.inserted_at,
          follower_id: pf.follower_id
        }

    {items, next_cursor, has_next} =
      CursorPagination.paginate(
        query,
        [:inserted_at, :follower_id],
        [:datetime, :string],
        cursor,
        limit,
        :desc
      )

    {:ok, %{items: items, next_cursor: next_cursor, has_next: has_next}}
  end

  defp get_producer(producer_id) do
    case Repo.get(Producer, producer_id) do
      nil -> {:error, :not_found}
      %Producer{} = producer -> {:ok, producer}
    end
  end

  defp producer_follower_count(producer_id) do
    Repo.one(from p in Producer, where: p.id == ^producer_id, select: p.follower_count) || 0
  end

  @doc """
  Gets the list of user IDs that the given user follows.
  """
  def list_following_ids(user_id) do
    from(uf in UserFollow,
      where: uf.follower_id == ^user_id,
      select: uf.followed_id
    )
    |> Repo.all()
  end

  # ---------------------------------
  # Notifications
  # ---------------------------------

  @aggregator_actions [:like, :follow]

  # Skip notification for self-likes.
  def create_notification(%{actor_id: actor_id, user_id: user_id} = _attrs)
      when actor_id == user_id do
    {:ok, :self_notification_skipped}
  end

  @doc """
  Creates a notification or updates an existing one if the action allows aggregation.
  For actions in `@aggregator_actions`, adds the actor to an existing notification.
  For other actions (e.g., :reply, :new_comment), always creates a new notification.
  """
  def create_notification(%{action: action} = attrs) do
    enriched = ensure_idempotency_key(attrs)

    result =
      cond do
        action in @aggregator_actions -> do_aggregated_notification(enriched)
        action == :system -> do_system_notification(enriched)
        true -> do_standard_notification(enriched)
      end

    broadcast_unread_count_on_change(result)
    result
  end

  defp broadcast_unread_count_on_change({:ok, %Notification{user_id: user_id}}),
    do: broadcast_unread_count(user_id)

  defp broadcast_unread_count_on_change(_result), do: :ok

  defp do_aggregated_notification(attrs) do
    # Build base query for existing unread notifications for the user with the same action and entity type
    query =
      from n in Notification,
        where: n.user_id == ^attrs.user_id,
        where: n.action == ^attrs.action,
        where: n.entity_type == ^attrs.entity_type,
        where: n.read == false,
        where: n.entity_id == ^attrs.entity_id

    # If an existing notification is found, update it; otherwise, create a new one
    case Repo.one(query) do
      nil ->
        do_standard_notification(attrs)

      notification ->
        update_existing_notification(notification, attrs)
    end
  end

  defp update_existing_notification(notification, attrs) do
    # Build snapshot for the new actor
    new_actor = build_actor_snapshot(attrs.actor_id)

    # convert root embed and its snapshots into plain maps
    metadata =
      notification.metadata
      |> dump()
      |> Map.update(:actor_snapshots, [], fn snaps -> Enum.map(snaps, &dump/1) end)

    # Remove any snapshot with the same actor ID
    existing_snapshots = Map.get(metadata, :actor_snapshots, [])
    snapshots_without_actor = Enum.reject(existing_snapshots, &(&1.id == new_actor.id))
    actor_already_present = length(snapshots_without_actor) != length(existing_snapshots)

    # Always add the new actor at the front and limit to 5 snapshots
    updated_snapshots = [new_actor | snapshots_without_actor] |> Enum.take(5)

    # Increment only if the actor wasn't already present
    updated_count =
      Map.get(metadata, :actors_count, 0) + if(actor_already_present, do: 0, else: 1)

    # Merge the updated snapshots and count into metadata
    updated_metadata =
      metadata
      |> Map.put(:actor_snapshots, updated_snapshots)
      |> Map.put(:actors_count, updated_count)

    result =
      notification
      |> Notification.changeset(%{metadata: updated_metadata})
      |> Repo.update()

    case {result, actor_already_present} do
      {{:ok, _} = ok, false} -> ok
      _ -> result
    end
  end

  defp ensure_idempotency_key(attrs) do
    Map.put_new(attrs, :idempotency_key, nil)
  end

  defp dump(%_{} = struct), do: Map.from_struct(struct)
  defp dump(map) when is_map(map), do: map

  defp build_actor_snapshot(actor_id) do
    # Fetch user and build a snapshot with id, username, and small avatar URL
    case Repo.get(Kaguya.Users.User, actor_id) do
      nil ->
        %{}

      user ->
        avatar_urls = Kaguya.Users.build_avatar_urls(user.avatar_id)

        %{
          id: user.id,
          username: user.username,
          avatar_url: avatar_urls[:small]
        }
    end
  end

  defp ensure_actor_metadata(%{actor_id: actor_id} = attrs) do
    default_metadata = %{
      actors_count: 1,
      actor_snapshots: [build_actor_snapshot(actor_id)]
    }

    metadata = Map.get(attrs, :metadata, %{})
    Map.put(attrs, :metadata, Map.merge(default_metadata, metadata))
  end

  defp ensure_actor_metadata(attrs), do: attrs

  defp insert_notification(attrs) do
    %Notification{}
    |> Notification.changeset(Map.put(attrs, :read, false))
    |> Repo.insert(on_conflict: :nothing)
    |> normalize_insert_result()
  end

  defp normalize_insert_result({:ok, %Notification{} = notification}) do
    if notification.id do
      {:ok, notification}
    else
      {:ok, :duplicate_notification_skipped}
    end
  end

  defp normalize_insert_result({:error, %Ecto.Changeset{} = changeset}) do
    if idempotency_conflict?(changeset) do
      {:ok, :duplicate_notification_skipped}
    else
      {:error, changeset}
    end
  end

  defp normalize_insert_result(other), do: other

  defp idempotency_conflict?(%Ecto.Changeset{errors: errors}) do
    Enum.any?(errors, fn
      {:idempotency_key, {_message, opts}} -> Keyword.get(opts, :constraint) == :unique
      _ -> false
    end)
  end

  defp do_system_notification(attrs) do
    attrs
    |> Map.put_new(:metadata, %{})
    |> insert_notification()
  end

  defp do_standard_notification(attrs) do
    attrs
    |> ensure_actor_metadata()
    |> insert_notification()
  end

  @doc """
  Paginated list of notifications for a user.

  Returns {items, next_cursor}
  """
  def list_notifications_for_user(
        user_id,
        only_unread \\ false,
        cursor \\ nil,
        limit \\ 10,
        surface \\ nil
      ) do
    surface = normalize_surface(surface)

    {items, next_cursor, has_next} =
      Notification
      |> where(user_id: ^user_id)
      |> where([n], n.read == false or not (^only_unread))
      |> apply_surface_filter_to_notifications(surface)
      |> CursorPagination.paginate_by_cursor(:inserted_at, cursor, limit, :desc)

    {dedupe_notifications(items), next_cursor, has_next}
  end

  defp normalize_surface(nil), do: nil
  defp normalize_surface(:vn), do: "vn"

  defp normalize_surface(surface) when is_binary(surface) do
    case String.downcase(String.trim(surface)) do
      s when s in ["vn", "vns"] -> "vn"
      _ -> nil
    end
  end

  defp normalize_surface(_), do: nil

  defp apply_surface_filter_to_notifications(query, _), do: query

  defp dedupe_notifications(notifications) do
    # Notifications are already sorted newest-first. Keep the first occurrence.
    {_seen, out} =
      Enum.reduce(notifications, {MapSet.new(), []}, fn n, {seen, acc} ->
        key = {n.action, n.id}

        if MapSet.member?(seen, key) do
          {seen, acc}
        else
          {MapSet.put(seen, key), [n | acc]}
        end
      end)

    Enum.reverse(out)
  end

  @doc """
  Get a single notification by ID, ensuring it belongs to the user.
  Returns {:ok, notification} or {:error, reason}.
  """
  def get_notification_for_user(notification_id, user_id) do
    case Repo.get(Notification, notification_id) do
      nil ->
        {:error, :not_found}

      notification ->
        if notification.user_id == user_id do
          {:ok, notification}
        else
          {:error, "Access denied"}
        end
    end
  end

  @doc """
  Mark a single notification as read, ensuring it belongs to the user.
  Returns {:ok, updated_notification} or {:error, reason}.
  """
  def mark_notification_read(notification_id, user_id) do
    with {:ok, notification} <- get_notification_for_user(notification_id, user_id) do
      result =
        notification
        |> Notification.changeset(%{read: true})
        |> Repo.update()

      case result do
        {:ok, _} -> broadcast_unread_count(user_id)
        _ -> :ok
      end

      result
    end
  end

  @doc """
  Mark all notifications as read for the user. Returns {:ok, count} or {:error, reason}.
  """
  def mark_all_notifications_read(user_id) do
    {count, _} =
      Notification
      |> where([n], n.user_id == ^user_id and n.read == false)
      |> Repo.update_all(set: [read: true])

    if count > 0, do: broadcast_unread_count(user_id)

    {:ok, count > 0}
  end

  @doc """
  Delete a single notification, ensuring it belongs to the user.
  Returns {:ok, true} or {:error, reason}.
  """
  def delete_notification(notification_id, user_id) do
    with {:ok, notification} <- get_notification_for_user(notification_id, user_id),
         {:ok, _struct} <- Repo.delete(notification) do
      broadcast_unread_count(user_id)
      {:ok, true}
    end
  end

  @doc """
  Returns the unread notification count for a user, optionally filtered by surface.
  """
  def unread_count(user_id, surface \\ nil) do
    surface = normalize_surface(surface)

    Notification
    |> where([n], n.user_id == ^user_id and n.read == false)
    |> apply_surface_filter_to_notifications(surface)
    |> Repo.aggregate(:count, :id)
  end

  @doc """
  PubSub topic carrying a user's unread-notification count updates.

  Subscribers receive `{:unread_count, count}` whenever the user's unread
  total changes (notification created, read, or deleted).
  """
  def notifications_topic(user_id), do: "user:#{user_id}:notifications"

  defp broadcast_unread_count(user_id) do
    Phoenix.PubSub.broadcast(
      Kaguya.PubSub,
      notifications_topic(user_id),
      {:unread_count, unread_count(user_id)}
    )
  end

  # ----------------------------------------------------------------------------
  # Activity helpers
  # ----------------------------------------------------------------------------

  defp record_follow_activity(follower_id, %User{} = followed) do
    avatar_urls = Kaguya.Users.build_avatar_urls(followed.avatar_id)

    Activities.record_activity(%{
      user_id: follower_id,
      action: :followed,
      entity_type: "user",
      entity_id: followed.id,
      metadata: %{
        followed_user_id: followed.id,
        followed_username: followed.username,
        followed_display_name: followed.display_name,
        followed_avatar_url: avatar_urls[:small]
      }
    })
  end

  defp record_follow_producer_activity(follower_id, %Producer{} = producer) do
    Activities.record_activity(%{
      user_id: follower_id,
      action: :followed,
      entity_type: "producer",
      entity_id: producer.id,
      metadata: %{
        followed_producer_id: producer.id,
        followed_producer_name: producer.name,
        followed_producer_slug: producer.slug
      }
    })
  end
end

# ---------------------------------
# Like
# ---------------------------------

defmodule Kaguya.Social.Likes do
  @moduledoc """
  Handles like/unlike operations across different entities.
  """

  alias Kaguya.Repo
  import Ecto.Query

  @doc """
  Creates a like if it doesn't exist.

  Returns {:ok, true} when a new row was inserted, {:ok, false} when the
  like already existed, or {:error, changeset} if validation fails.
  """
  def create_like(schema_module, attrs) do
    changeset = schema_module.changeset(struct(schema_module), attrs)

    if changeset.valid? do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      fields = schema_module.__schema__(:fields)

      row =
        changeset
        |> Ecto.Changeset.apply_changes()
        |> Map.from_struct()
        |> Map.take(fields)
        |> Map.merge(%{inserted_at: now, updated_at: now})

      {count, _} =
        Repo.insert_all(
          schema_module,
          [row],
          on_conflict: :nothing,
          conflict_target: schema_module.__schema__(:primary_key)
        )

      {:ok, count == 1}
    else
      {:error, changeset}
    end
  end

  @doc "Deletes a like record based on the given filters."
  def delete_like(schema_module, filters) do
    Repo.delete_all(from l in schema_module, where: ^filters)
  end

  @doc "Increments the likes count for a given entity."
  def increment_likes(entity_module, id), do: update_likes(entity_module, id, 1)

  @doc "Decrements the likes count for a given entity."
  def decrement_likes(entity_module, id), do: update_likes(entity_module, id, -1)

  defp update_likes(entity_module, id, increment) do
    Repo.update_all(from(e in entity_module, where: e.id == ^id), inc: [likes_count: increment])
  end

  @doc "Checks if a like exists for a given schema and filters."
  def liked?(schema, filters) do
    {:ok, Repo.exists?(from l in schema, where: ^filters)}
  end
end
