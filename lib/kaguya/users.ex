defmodule Kaguya.Users do
  @moduledoc """
  The Users context.
  """

  import Ecto.Query
  alias Ecto.Changeset
  alias Kaguya.Repo

  alias Kaguya.Users.{User, UserLibraryExport, VndbImport, UsernameGenerator}
  alias Kaguya.Characters.{Character, CharacterFavorite, Quote, QuoteFavorite}
  alias Kaguya.Shelves.ReadingStatus
  alias Kaguya.Reviews.{Rating, Review, ReviewComment}
  alias Kaguya.Similarities.{Similarity, SimilarityVote}
  alias Kaguya.Lists.{List, ListComment}
  alias Kaguya.Social.Notification
  alias Kaguya.Activities.UserActivity
  alias Kaguya.Shelves.Shelf
  alias Kaguya.Reviews.RatingUpdater

  @doc """
  Returns `true` when the local Phoenix-auth user has an email address.
  """
  def has_email_provider?(%{email: email}) when is_binary(email) and email != "", do: true
  def has_email_provider?(_), do: false

  @doc """
  Gets a single user.
  """
  def get_user(id) do
    case Repo.get(User, id) do
      nil -> {:error, :not_found}
      user -> {:ok, user}
    end
  end

  @doc """
  Gets a user by username.
  """
  def get_user_by_username(username) do
    case Repo.get_by(User, username: username) do
      nil -> {:error, :not_found}
      user -> {:ok, user}
    end
  end

  @doc """
  Searches for users by username or display name.
  Case-insensitive, ranked: exact > prefix > infix.
  """
  def search_users(query) when is_binary(query) do
    q = String.downcase(query)
    prefix = "#{q}%"
    infix = "%#{q}%"

    User
    |> where([u], ilike(u.username, ^infix) or ilike(u.display_name, ^infix))
    |> order_by([u],
      asc:
        fragment(
          """
          CASE
            WHEN lower(?) = ? THEN 0
            WHEN lower(?) = ? THEN 1
            WHEN lower(?) LIKE ? THEN 2
            WHEN lower(?) LIKE ? THEN 3
            ELSE 4
          END
          """,
          u.display_name,
          ^q,
          u.username,
          ^q,
          u.display_name,
          ^prefix,
          u.username,
          ^prefix
        )
    )
    |> limit(10)
    |> Repo.all()
  end

  def build_avatar_urls(nil), do: %{}

  def build_avatar_urls(image_id) do
    base_url = "https://images.kaguya.io/users/avatars"

    %{
      # Default avatar size
      small: "#{base_url}/#{image_id}-120w.webp",
      # High-DPI (3x) version
      medium: "#{base_url}/#{image_id}-360w.webp"
    }
  end

  def build_banner_urls(nil), do: %{}

  def build_banner_urls(image_id) do
    base_url = "https://images.kaguya.io/users/banners"

    %{
      # Main image: Used for both mobile and desktop, cropped dynamically via CSS.
      medium: "#{base_url}/#{image_id}-1280w.webp",
      # Desktop 2x
      large: "#{base_url}/#{image_id}-2560w.webp"
    }
  end

  @doc """
  Creates a user with default avatar and banner IDs if not provided.
  """
  def create_user(attrs \\ %{}) do
    default_attrs = %{
      :avatar_id => Kaguya.Images.random_default_avatar()
    }

    # Merge defaults; user-supplied attrs will override defaults if present.
    attrs = Map.merge(default_attrs, attrs)

    base = UsernameGenerator.base_segment(attrs)
    autogen? = not UsernameGenerator.username_present?(attrs)

    attrs = normalize_display_name(attrs)

    attempt_create_user(%User{}, attrs, autogen?, base)
  end

  defp attempt_create_user(user, attrs, false, _base) do
    user
    |> User.create_changeset(attrs)
    |> Repo.insert()
  end

  defp attempt_create_user(user, attrs, true, base) do
    base
    |> with_generated_username(fn candidate ->
      if UsernameGenerator.taken?(candidate) do
        :retry
      else
        Repo.insert(User.create_changeset(user, Map.put(attrs, :username, candidate)))
      end
    end)
    |> case do
      :exhausted ->
        {:error,
         Changeset.change(%User{})
         |> Changeset.add_error(:username, "could not generate a unique username")}

      result ->
        result
    end
  end

  # Shared username-generation retry loop for the create and onboarding-update
  # paths. `op_fun` receives a candidate username and returns either an
  # `{:ok, _}` result, an `{:error, changeset}` (retried only when the error is
  # a username unique-constraint violation, otherwise returned as-is), or the
  # `:retry` atom to skip a candidate proactively. Returns `:exhausted` when no
  # unique candidate is found within `max_attempts`.
  defp with_generated_username(base, op_fun, attempt \\ 0) do
    if attempt < UsernameGenerator.max_attempts() do
      candidate = UsernameGenerator.candidate(base, attempt)

      case op_fun.(candidate) do
        :retry ->
          with_generated_username(base, op_fun, attempt + 1)

        {:error, %Ecto.Changeset{} = changeset} = error ->
          if UsernameGenerator.unique_constraint_error?(changeset),
            do: with_generated_username(base, op_fun, attempt + 1),
            else: error

        result ->
          result
      end
    else
      :exhausted
    end
  end

  # Matches Unicode separators, format chars, braille blank, hangul filler
  @invisible_chars Regex.compile!("[\\p{Z}\\p{Cf}\\x{2800}\\x{3164}]+", "u")

  defp normalize_display_name(attrs) do
    raw =
      Map.get(attrs, :display_name) ||
        Map.get(attrs, "display_name")

    if is_binary(raw) do
      sanitized =
        raw
        |> String.replace(@invisible_chars, " ")
        |> String.trim()

      cond do
        sanitized == "" ->
          attrs
          |> Map.delete("display_name")
          |> Map.delete(:display_name)

        String.length(sanitized) >= 2 ->
          attrs
          |> Map.delete("display_name")
          |> Map.put(:display_name, sanitized)

        true ->
          attrs
          |> Map.delete("display_name")
          |> Map.delete(:display_name)
      end
    else
      attrs
      |> Map.delete("display_name")
      |> Map.delete(:display_name)
    end
  end

  @doc """
  Updates a user.

  - If given a `%User{}` struct, updates the user directly.
  - If given a user ID (binary), fetches the user and then updates it.
  """
  def update_user(%User{} = user, attrs) do
    # favorite_characters and favorite_quotes both live in their own join
    # tables, not on the user row. Pop them off the attrs so the user-row
    # changeset never sees them, then apply each diff against its join
    # table in the same transaction. This keeps the join-table rows and
    # the denormalized *.favorites_count counters consistent — either
    # everything commits or nothing does. Adding a third favorite domain
    # is a 5-line entry in `favorite_spec/1` plus two calls below.
    {fav_chars_attr, attrs} = pop_favorite_field(attrs, :favorite_characters)
    {fav_quotes_attr, other_attrs} = pop_favorite_field(attrs, :favorite_quotes)

    Repo.transact(fn ->
      with :ok <- validate_favorite_limit(user, :favorite_characters, fav_chars_attr),
           :ok <- validate_favorite_limit(user, :favorite_quotes, fav_quotes_attr),
           {:ok, updated} <-
             user
             |> User.changeset(other_attrs)
             |> Repo.update() do
        replace_favorite_field(updated, :favorite_characters, fav_chars_attr)
        replace_favorite_field(updated, :favorite_quotes, fav_quotes_attr)
        {:ok, updated}
      end
    end)
  end

  def update_user(id, attrs) when is_binary(id) do
    with {:ok, user} <- get_user(id) do
      if is_nil(user.username) do
        # New user without username — generate one during onboarding
        create_username_and_update(user, attrs)
      else
        update_user(user, attrs)
      end
    end
  end

  # ── Generic favorites helpers ────────────────────────────────────────────
  #
  # Three favorite domains today (visual novels live on the user row, the
  # other two on join tables) and we'll likely add more (scenes, OSTs).
  # Per-domain logic was originally copy-pasted, which made each new
  # domain a multi-hundred-line mechanical change with drift risk.
  # The spec map below is the single source of truth: a new domain is a
  # 5-line entry plus two callers in `update_user/2`.

  defp favorite_spec(:favorite_characters) do
    %{
      join_table: CharacterFavorite,
      join_fk: :character_id,
      target_table: Character,
      limit_fn: &User.favorites_limit/1
    }
  end

  defp favorite_spec(:favorite_quotes) do
    %{
      join_table: QuoteFavorite,
      join_fk: :vn_quote_id,
      target_table: Quote,
      limit_fn: &User.quote_favorites_limit/1
    }
  end

  # Map.pop with string-or-atom key support — LiveView/controllers usually
  # hand us atom-keyed maps today, but other call sites (admin tools,
  # tests) sometimes pass string-keyed attrs. A sentinel `:unset`
  # distinguishes "caller didn't touch favorites" from "caller set
  # favorites to []"; the former skips the join-table write entirely.
  defp pop_favorite_field(attrs, field) when is_atom(field) do
    string_key = Atom.to_string(field)

    cond do
      Map.has_key?(attrs, field) ->
        {cleaned_ids(Map.get(attrs, field)), Map.delete(attrs, field)}

      Map.has_key?(attrs, string_key) ->
        {cleaned_ids(Map.get(attrs, string_key)), Map.delete(attrs, string_key)}

      true ->
        {:unset, attrs}
    end
  end

  defp cleaned_ids(nil), do: []
  defp cleaned_ids(list) when is_list(list), do: Enum.reject(list, &is_nil/1)

  # Limit enforced here (was a changeset validation on the old array
  # column). Patron status determines the cap. The error changeset is
  # derived from the `%User{}` struct so downstream error formatters see
  # `data: %User{}` and can associate the error back to the input field.
  defp validate_favorite_limit(_user, _field, :unset), do: :ok

  defp validate_favorite_limit(user, field, ids) when is_list(ids) do
    spec = favorite_spec(field)
    max = spec.limit_fn.(user)

    if length(ids) > max do
      {:error, limit_exceeded_changeset(user, field, max)}
    else
      :ok
    end
  end

  defp limit_exceeded_changeset(user, field, max) do
    user
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.add_error(
      field,
      "should have at most %{count} item(s)",
      count: max,
      validation: :length,
      kind: :max
    )
  end

  # :unset means the caller didn't pass this field; leave the join table
  # untouched.
  defp replace_favorite_field(_user, _field, :unset), do: :ok

  # Applies the diff between "what's currently in the table for this user"
  # and "what the caller wants". Sequence:
  #   1. SELECT existing (user, target_id) pairs.
  #   2. Compute added / removed sets.
  #   3. DELETE removed rows; decrement their target favorites_count.
  #   4. UPSERT the full desired set with positions — new rows insert,
  #      existing rows get their position updated via ON CONFLICT.
  #   5. Increment target favorites_count for added rows.
  # All in one transaction (the caller wraps us); zero-floor guard on
  # decrement prevents underflow from any external drift.
  defp replace_favorite_field(user, field, new_ids) when is_list(new_ids) do
    spec = favorite_spec(field)
    fk = spec.join_fk

    # Serialize bulk editor saves with inline pin/unpin mutations so the
    # diff is computed from a stable snapshot of the join rows.
    lock_user_favorites(user.id)

    existing_ids =
      from(j in spec.join_table,
        where: j.user_id == ^user.id,
        select: field(j, ^fk)
      )
      |> Repo.all()
      |> MapSet.new()

    new_set = MapSet.new(new_ids)
    added = MapSet.difference(new_set, existing_ids) |> MapSet.to_list()
    removed = MapSet.difference(existing_ids, new_set) |> MapSet.to_list()

    if removed != [] do
      from(j in spec.join_table,
        where: j.user_id == ^user.id and field(j, ^fk) in ^removed
      )
      |> Repo.delete_all()

      from(t in spec.target_table, where: t.id in ^removed and t.favorites_count > 0)
      |> Repo.update_all(inc: [favorites_count: -1])
    end

    if new_ids != [] do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      rows =
        new_ids
        |> Enum.with_index()
        |> Enum.map(fn {target_id, idx} ->
          %{user_id: user.id, position: idx, inserted_at: now}
          |> Map.put(fk, target_id)
        end)

      # Replace-on-conflict updates `position` for rows that already
      # existed (reordering), while inserting genuinely new rows. The
      # original inserted_at on existing rows is preserved — only the
      # columns listed in `:replace` are touched.
      Repo.insert_all(spec.join_table, rows,
        on_conflict: {:replace, [:position]},
        conflict_target: [:user_id, fk]
      )
    end

    if added != [] do
      from(t in spec.target_table, where: t.id in ^added)
      |> Repo.update_all(inc: [favorites_count: 1])
    end

    :ok
  end

  # ── Inline single-pin operations ────────────────────────────────────────
  #
  # The bookmark-icon flow on quote cards toggles one favorite at a time
  # without sending the whole list. Returns `{:ok, true}` for both add and
  # remove (idempotent), or `{:error, :limit_exceeded}` for typed limit
  # rejection (frontend matches on the atom string to show the upgrade
  # toast — no brittle message regex).

  @doc """
  Pin a single quote to the caller's profile favorites. Idempotent —
  re-pinning is a no-op.

  Accepts either a `%User{}` struct or any map with an `:id` field, or a
  bare user_id binary. Errors with `{:error, :limit_exceeded}` when the user
  is already at their tier limit. The bulk
  `update_user(favorite_quotes: [...])` path is for the editor's
  reorder/save flow.
  """
  def add_favorite_quote(%{id: user_id}, quote_id) when is_binary(quote_id),
    do: add_favorite_pin(user_id, :favorite_quotes, quote_id)

  def add_favorite_quote(user_id, quote_id)
      when is_binary(user_id) and is_binary(quote_id),
      do: add_favorite_pin(user_id, :favorite_quotes, quote_id)

  @doc """
  Unpin a single quote. Idempotent — unpinning when not pinned is a
  no-op. Same input flexibility as `add_favorite_quote/2`.
  """
  def remove_favorite_quote(%{id: user_id}, quote_id) when is_binary(quote_id),
    do: remove_favorite_pin(user_id, :favorite_quotes, quote_id)

  def remove_favorite_quote(user_id, quote_id)
      when is_binary(user_id) and is_binary(quote_id),
      do: remove_favorite_pin(user_id, :favorite_quotes, quote_id)

  # Locks-and-fetches the user row, then runs the limit-checked insert.
  # Working from the freshly-fetched %User{} (not the caller's stale
  # struct/map) means the limit check sees the post-lock favorites
  # state — important if a concurrent change committed between the request
  # arriving and the row lock acquiring.
  defp add_favorite_pin(user_id, field, target_id) when is_binary(user_id) do
    spec = favorite_spec(field)
    fk = spec.join_fk

    Repo.transact(fn ->
      # SELECT FOR UPDATE serializes concurrent inline-add attempts.
      # Without this lock, two parallel adds can both pass the
      # count-vs-limit check under READ COMMITTED isolation, both
      # insert, user lands at limit + 1.
      case lock_user_for_update(user_id) do
        nil ->
          {:error, :user_not_found}

        %User{} = user ->
          with {:ok, _target} <- fetch_favorite_target(spec.target_table, target_id),
               :ok <- assert_pin_room(user, field, target_id) do
            now = DateTime.utc_now() |> DateTime.truncate(:second)

            # Prepend: new pins go above existing ones. Newest-first
            # ORDER BY position ASC stays correct because we slot the
            # new row at min(position) - 1. Negative positions are
            # fine; the editor save path renumbers to [0, 1, ...] on
            # the next bulk save.
            next_pos =
              from(j in spec.join_table,
                where: j.user_id == ^user.id,
                select: coalesce(min(j.position), 1)
              )
              |> Repo.one()
              |> Kernel.-(1)

            row =
              %{user_id: user.id, position: next_pos, inserted_at: now}
              |> Map.put(fk, target_id)

            {count, _} =
              Repo.insert_all(spec.join_table, [row],
                on_conflict: :nothing,
                conflict_target: [:user_id, fk]
              )

            if count > 0 do
              from(t in spec.target_table, where: t.id == ^target_id)
              |> Repo.update_all(inc: [favorites_count: 1])
            end

            {:ok, true}
          end
      end
    end)
  end

  defp remove_favorite_pin(user_id, field, target_id) when is_binary(user_id) do
    spec = favorite_spec(field)
    fk = spec.join_fk

    Repo.transact(fn ->
      # Match add/bulk-save serialization so remove can't race the editor
      # diff and leave stale rows or counters behind.
      lock_user_favorites(user_id)

      delete_query =
        from(j in spec.join_table,
          where: j.user_id == ^user_id and field(j, ^fk) == ^target_id
        )

      {deleted, _} = Repo.delete_all(delete_query)

      if deleted > 0 do
        from(t in spec.target_table, where: t.id == ^target_id and t.favorites_count > 0)
        |> Repo.update_all(inc: [favorites_count: -1])
      end

      {:ok, true}
    end)
  end

  defp lock_user_for_update(user_id) do
    Repo.one(from u in User, where: u.id == ^user_id, lock: "FOR UPDATE")
  end

  defp lock_user_favorites(user_id) do
    Repo.one(from u in User, where: u.id == ^user_id, select: u.id, lock: "FOR UPDATE")
  end

  defp fetch_favorite_target(target_table, target_id) do
    case Repo.get(target_table, target_id) do
      nil -> {:error, :target_not_found}
      target -> {:ok, target}
    end
  end

  # Skip the count query when the target is already pinned (no growth, no
  # gate needed). Otherwise the row lock acquired by the caller serializes
  # racing adds; this count therefore reflects the post-lock-acquisition
  # state, not a stale view. `user` here is the freshly-fetched %User{}
  # struct, so `User.*_limit/1` sees current favorites state.
  defp assert_pin_room(%User{} = user, field, target_id) do
    spec = favorite_spec(field)
    fk = spec.join_fk

    already_pinned? =
      Repo.exists?(
        from j in spec.join_table,
          where: j.user_id == ^user.id and field(j, ^fk) == ^target_id
      )

    if already_pinned? do
      :ok
    else
      max = spec.limit_fn.(user)

      current =
        from(j in spec.join_table, where: j.user_id == ^user.id)
        |> Repo.aggregate(:count)

      if current >= max, do: {:error, :limit_exceeded}, else: :ok
    end
  end

  defp create_username_and_update(user, attrs) do
    base = UsernameGenerator.base_segment(attrs)

    base
    |> with_generated_username(fn candidate ->
      update_user(user, Map.put(attrs, :username, candidate))
    end)
    |> case do
      :exhausted -> {:error, "Could not generate unique username"}
      result -> result
    end
  end

  @doc """
  Resets the user's VN library by deleting all their reviews, ratings, and related data.
  """
  def reset_library(user_id, _surface \\ :vn) do
    Repo.transaction(fn ->
      # 1) Gather affected VN IDs and user's review/rating data
      user_vn_ratings = Repo.all(from r in Rating, where: r.user_id == ^user_id)
      user_vn_reviews = Repo.all(from rv in Review, where: rv.user_id == ^user_id)

      suppressed? = ratings_suppressed?(user_id)

      rating_deltas =
        Enum.map(user_vn_ratings, fn rating ->
          %{visual_novel_id: rating.visual_novel_id, old_rating: rating.rating, new_rating: nil}
        end)

      review_vn_ids = Enum.map(user_vn_reviews, & &1.visual_novel_id)

      # 2) Delete all user VN-related data
      Repo.delete_all(from rv in Review, where: rv.user_id == ^user_id)
      Repo.delete_all(from rt in Rating, where: rt.user_id == ^user_id)
      Repo.delete_all(from rs in ReadingStatus, where: rs.user_id == ^user_id)
      Repo.delete_all(from s in Shelf, where: s.user_id == ^user_id)

      # 3) Update affected VNs' stats (skip rating adjustments for suppressed users)
      unless suppressed? do
        Enum.each(rating_deltas, fn delta ->
          RatingUpdater.adjust_vn_rating(
            delta.visual_novel_id,
            delta.old_rating,
            delta.new_rating
          )
        end)
      end

      Enum.each(review_vn_ids, fn vn_id ->
        RatingUpdater.adjust_vn_review_count(vn_id, -1)
      end)

      # 4) Directly reset the user's VN stats (denormalized counters on users table)
      reset_user_vn_stats(user_id)

      # 5) Drop the user's snapshot rows in user_period_stats. Without this,
      # the stats page would render stale playtime/producers/top-tags/histograms
      # from before the reset, and the daily cron wouldn't notice (the user's
      # reading_statuses/ratings/reviews are now gone, so they won't be flagged
      # as active). On next access Stats.build_user_vn_stats handles a missing
      # snapshot by returning empty stats, so no rebuild is required.
      Repo.delete_all(from s in Kaguya.Stats.UserPeriodStat, where: s.user_id == ^user_id)

      # 6) Drop the user's precomputed recs + rec-feedback signals. The
      # training inputs (ratings / statuses) just got wiped, so any stored
      # recs are now attributed to a library the user no longer has — shown
      # as-is they'd mislead both the user (stale "because you liked X")
      # and the trainer (stale pref/mask CSVs). The user can regenerate
      # once they start building a new library.
      Kaguya.Recommendations.clear_for_user(user_id)

      true
    end)
  end

  defp reset_user_vn_stats(user_id) do
    User
    |> where(id: ^user_id)
    |> Repo.update_all(
      set: [
        vn_ratings_dist: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        vn_ratings_count: 0,
        vn_average_rating: 0.0,
        vn_reviews_count: 0
      ]
    )
  end

  @doc """
  Deletes a user and all related data. Adjusts denormalized counters
  on other entities affected by CASCADE-deleted child rows.
  """
  def delete_user(user_id) do
    with {:ok, _user} <- get_user(user_id) do
      # ── Gather before CASCADE destroys child rows ──

      review_comment_counts =
        from(rc in ReviewComment,
          where: rc.user_id == ^user_id,
          group_by: rc.vn_review_id,
          select: {rc.vn_review_id, count(rc.id)}
        )
        |> Repo.all()

      list_comment_counts =
        from(lc in ListComment,
          where: lc.user_id == ^user_id,
          group_by: lc.list_id,
          select: {lc.list_id, count(lc.id)}
        )
        |> Repo.all()

      similarity_votes =
        from(sv in SimilarityVote,
          where: sv.user_id == ^user_id,
          select: {sv.visual_novel_id, sv.similar_vn_id, sv.vote_value}
        )
        |> Repo.all()

      ratings =
        from(r in Rating,
          where: r.user_id == ^user_id,
          select: {r.visual_novel_id, r.rating}
        )
        |> Repo.all()

      review_vn_ids =
        Repo.all(from rv in Review, where: rv.user_id == ^user_id, select: rv.visual_novel_id)

      own_review_ids =
        Repo.all(from rv in Review, where: rv.user_id == ^user_id, select: rv.id)

      own_list_ids =
        Repo.all(from l in List, where: l.user_id == ^user_id, select: l.id)

      # ── Delete + adjust in transaction ──

      Repo.transaction(fn ->
        # Delete reports filed by this user (reporter_id is NOT NULL)
        from(r in Kaguya.Reports.Report, where: r.reporter_id == ^user_id) |> Repo.delete_all()
        # Nullify resolved_by on reports this user resolved
        from(r in Kaguya.Reports.Report, where: r.resolved_by == ^user_id)
        |> Repo.update_all(set: [resolved_by: nil])

        # Serialize delete against favorite-editor saves and inline
        # favorite toggles. Those paths all lock the user row before
        # diffing or mutating join rows; taking the same lock here keeps
        # the snapshot aligned with the rows CASCADE will drop.
        locked_user =
          case lock_user_for_update(user_id) do
            nil -> Repo.rollback(:not_found)
            %User{} = locked_user -> locked_user
          end

        # Snapshot the user's favorited target IDs INSIDE the transaction,
        # just before the CASCADE drops the join-table rows. A capture
        # outside the transaction would race with a concurrent update_user
        # that adds a new favorite: CASCADE would still drop that row,
        # but we'd miss decrementing the counter for it.
        favorited_char_ids =
          Repo.all(
            from cf in CharacterFavorite,
              where: cf.user_id == ^user_id,
              select: cf.character_id
          )

        favorited_quote_ids =
          Repo.all(
            from qf in QuoteFavorite,
              where: qf.user_id == ^user_id,
              select: qf.vn_quote_id
          )

        Repo.delete!(locked_user)

        # character_favorites rows were CASCADE-dropped with the user row,
        # but the denormalized characters.favorites_count counter is on
        # the character side and needs an explicit decrement.
        if favorited_char_ids != [] do
          from(c in Character,
            where: c.id in ^favorited_char_ids and c.favorites_count > 0
          )
          |> Repo.update_all(inc: [favorites_count: -1])
        end

        # quote_favorites rows are also CASCADE-dropped with the user row,
        # but vn_quotes.favorites_count is denormalized on the quote side
        # and needs the same explicit decrement.
        if favorited_quote_ids != [] do
          from(q in Quote,
            where: q.id in ^favorited_quote_ids and q.favorites_count > 0
          )
          |> Repo.update_all(inc: [favorites_count: -1])
        end

        # Review comments_count (grouped by review, fixes old -1 bug)
        Enum.each(review_comment_counts, fn {review_id, cnt} ->
          from(r in Review, where: r.id == ^review_id)
          |> Repo.update_all(inc: [comments_count: -cnt])
        end)

        # List comments_count
        Enum.each(list_comment_counts, fn {list_id, cnt} ->
          from(l in List, where: l.id == ^list_id)
          |> Repo.update_all(inc: [comments_count: -cnt])
        end)

        # Similarity vote counts
        Enum.each(similarity_votes, fn {vn_id, sim_id, vote} ->
          field = if(vote == 1, do: :upvotes_count, else: :downvotes_count)

          from(s in Similarity,
            where: s.visual_novel_id == ^vn_id and s.similar_vn_id == ^sim_id
          )
          |> Repo.update_all(inc: [{field, -1}])
        end)

        # VN reviews_count
        Enum.each(review_vn_ids, &RatingUpdater.adjust_vn_review_count(&1, -1))

        # VN rating stats (skip for suppressed users — their votes weren't counted)
        unless locked_user.ratings_suppressed do
          Enum.each(ratings, fn {vn_id, old_rating} ->
            RatingUpdater.adjust_vn_rating(vn_id, old_rating, nil)
          end)
        end

        # Stale notifications on others pointing to deleted reviews/lists
        if own_review_ids != [] do
          from(n in Notification,
            where: n.entity_type == :review and n.entity_id in ^own_review_ids
          )
          |> Repo.delete_all()
        end

        if own_list_ids != [] do
          from(n in Notification, where: n.entity_type == :list and n.entity_id in ^own_list_ids)
          |> Repo.delete_all()
        end

        # Stale activities on others pointing to deleted reviews/lists
        if own_review_ids != [] do
          from(a in UserActivity,
            where:
              a.entity_type == "review" and a.entity_id in ^own_review_ids and
                a.user_id != ^user_id
          )
          |> Repo.delete_all()
        end

        if own_list_ids != [] do
          from(a in UserActivity,
            where:
              a.entity_type == "list" and a.entity_id in ^own_list_ids and a.user_id != ^user_id
          )
          |> Repo.delete_all()
        end

        # Notifications on others where this user is an actor (likes, follows, comments, etc.)
        uid_str = Ecto.UUID.cast!(user_id)

        from(n in Notification,
          where:
            n.user_id != ^user_id and
              fragment(
                "EXISTS (SELECT 1 FROM jsonb_array_elements(?->'actor_snapshots') AS s WHERE s->>'id' = ?)",
                n.metadata,
                ^uid_str
              )
        )
        |> Repo.delete_all()
      end)
      |> case do
        {:ok, _} -> {:ok, true}
        {:error, :not_found} -> {:error, :not_found}
        error -> error
      end
    end
  end

  def get_vndb_import(id, user_id) do
    case Repo.get_by(VndbImport, id: id, user_id: user_id) do
      nil -> {:error, :not_found}
      import_record -> {:ok, import_record}
    end
  end

  def enqueue_vndb_import(upload_id, user_id) do
    import_changeset =
      %VndbImport{}
      |> VndbImport.changeset(%{id: upload_id, user_id: user_id})

    Ecto.Multi.new()
    |> Ecto.Multi.insert(:import, import_changeset)
    |> Oban.insert(
      :job,
      Kaguya.Uploads.VndbImportWorker.new(%{"upload_id" => upload_id, "user_id" => user_id})
    )
    |> Repo.transaction()
    |> case do
      {:ok, %{import: import_record}} -> {:ok, import_record}
      {:error, :import, changeset, _} -> {:error, changeset}
      {:error, :job, reason, _} -> {:error, reason}
    end
  end

  def create_user_library_export(attrs) do
    %UserLibraryExport{}
    |> UserLibraryExport.changeset(attrs)
    |> Repo.insert()
  end

  def update_user_library_export(%UserLibraryExport{} = export, attrs) do
    export
    |> UserLibraryExport.changeset(attrs)
    |> Repo.update()
  end

  def get_user_library_export!(id), do: Repo.get!(UserLibraryExport, id)

  def list_user_library_exports(user_id) do
    Repo.all(
      from e in UserLibraryExport,
        where: e.user_id == ^user_id,
        order_by: [desc: e.inserted_at],
        limit: 20
    )
  end

  # ============================================================================
  # Rating Suppression
  # ============================================================================

  alias Kaguya.Reviews.RatingRecalculator

  def ratings_suppressed?(user_id) do
    Repo.one(from u in User, where: u.id == ^user_id, select: u.ratings_suppressed) || false
  end

  @doc """
  Suppresses a user's ratings — votes silently stop counting in VN averages.
  Recalculates all affected VN stats in a single query.
  """
  def suppress_ratings(user_id) do
    with {:ok, user} <- get_user(user_id) do
      if user.ratings_suppressed do
        {:ok, user}
      else
        User
        |> where(id: ^user_id)
        |> Repo.update_all(set: [ratings_suppressed: true])

        RatingRecalculator.recalculate_for_user(user_id)
        get_user(user_id)
      end
    end
  end

  @doc """
  Unsuppresses a user's ratings, restoring them to VN averages.
  Recalculates all affected VN stats in a single query.
  """
  def unsuppress_ratings(user_id) do
    with {:ok, user} <- get_user(user_id) do
      if user.ratings_suppressed do
        User
        |> where(id: ^user_id)
        |> Repo.update_all(set: [ratings_suppressed: false])

        RatingRecalculator.recalculate_for_user(user_id)
        get_user(user_id)
      else
        {:ok, user}
      end
    end
  end

  @permission_fields ~w(can_edit can_discuss can_review can_list mod_db mod_discussions mod_reviews mod_lists mod_users ratings_suppressed)a

  @doc """
  Updates user permission flags. Admin-only, or mod_users for non-mod targets.
  """
  def update_permissions(target_id, attrs) do
    case get_user(target_id) do
      {:ok, user} ->
        updates =
          attrs
          |> Map.take(@permission_fields)
          |> Enum.reject(fn {_k, v} -> is_nil(v) end)
          |> Map.new()

        if updates == %{} do
          {:ok, user}
        else
          from(u in User, where: u.id == ^target_id)
          |> Repo.update_all(set: Enum.to_list(updates))

          get_user(target_id)
        end

      error ->
        error
    end
  end
end
