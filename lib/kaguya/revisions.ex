defmodule Kaguya.Revisions do
  @moduledoc """
  Context for the revision/edit history system.

  Every edit to a database entry creates a numbered revision stored as a row
  in the `changes` table (metadata) + corresponding `_hist` tables (entity state).
  Edits apply immediately. Moderators can revert to any previous revision.
  """

  import Ecto.Query
  require Logger
  alias Kaguya.Activities
  alias Kaguya.Authorization
  alias Kaguya.Repo
  alias Kaguya.Revisions.Change
  alias Kaguya.Revisions.Diff
  alias Kaguya.Revisions.Enrichment

  # Mod-controlled columns that non-mods can never set, even by forging form
  # params. Mirrors vndb's `if(!auth->permDbmod) { ... }` reset in
  # `Producers/Edit.pm`. Stripped from `changes` before any context-side
  # apply_edit runs.
  @mod_fields [:hidden_at, :is_locked]

  # Maps entity types to their context modules. Every module listed here
  # implements `Kaguya.Revisions.EntityContext`, which is the source of
  # truth for the required callback surface.
  @entity_config %{
    visual_novel: Kaguya.VisualNovels,
    character: Kaguya.Characters,
    producer: Kaguya.Producers,
    release: Kaguya.Releases,
    series: Kaguya.Series
  }

  # ============================================================================
  # Submit Edit
  # ============================================================================

  @doc """
  Submits an edit to an entity. In a single transaction:
  1. Loads entity, checks locks and conflicts
  2. Computes which field groups changed
  3. Applies changes to live tables
  4. Writes entity state to _hist tables
  5. Creates a change record

  Returns `{:ok, change}` or `{:error, reason}`.
  """
  def submit_edit(entity_type, entity_id, changes, summary, user, opts \\ []) do
    base_revision = Keyword.get(opts, :base_revision)
    source = Keyword.get(opts, :source, :user)
    action_override = Keyword.get(opts, :action)

    with {:ok, context} <- fetch_context(entity_type) do
      result =
        Repo.transact(fn ->
          with {:ok, original} <- fetch_entity(context, entity_id),
               changes <- sanitize_mod_fields(changes, user),
               :ok <- check_not_hidden(original, user),
               :ok <- check_not_locked(original, user),
               :ok <- check_base_revision(entity_type, entity_id, base_revision),
               changed <- compute_changed_fields(entity_type, original, changes),
               :ok <- validate_has_changes(changed),
               :ok <- ensure_initial_revision(entity_type, entity_id, context),
               {:ok, entity} <- apply_mod_field_changes(original, changes),
               {:ok, entity} <- context.apply_edit(entity, changes),
               action <- action_override || classify_action(changed, original, changes),
               {:ok, change} <-
                 create_change(entity_type, entity_id, action, changed, summary, source, user) do
            # Reload with preloads for accurate _hist snapshot
            entity = context.get_for_edit(entity.id)
            context.write_hist(change.id, entity)
            increment_edit_count(user)
            record_revision_activity(change, user)
            {:ok, change}
          end
        end)

      maybe_update_search_index_after_mod(entity_type, entity_id, result)
      maybe_recompute_content_score(entity_type, entity_id, result)
      result
    end
  end

  # apply_edit/2 in each context already reindexes its own search row for
  # the common edit path. This extra hop covers two cases the context-side
  # reindex misses: (a) Releases.apply_edit does not touch the parent VN's
  # search payload even though hide/unhide of a release changes its
  # available_on_stores / free_on_stores filter values, and (b) belt-and-
  # suspenders in case the in-transaction reindex hit Meilisearch before
  # the row was visible. Only fires for hide/unhide — lock/unlock doesn't
  # affect visibility in the search index.
  defp maybe_update_search_index_after_mod(entity_type, entity_id, {:ok, %Change{action: action}})
       when action in [:hide, :unhide] do
    update_search_index(entity_type, entity_id)
  end

  defp maybe_update_search_index_after_mod(_entity_type, _entity_id, _result), do: :ok

  # Mirrors vndb's `if(!auth->permDbmod) { ... reset hidden/locked ... }` in
  # Producers/Edit.pm. Stripping is equivalent to overwriting with the
  # current value — both produce "no change to this field" downstream in
  # changed_field_groups, so a forged form submission from a non-mod cannot
  # escalate.
  defp sanitize_mod_fields(changes, user) do
    if Authorization.can_moderate_db?(user) do
      changes
    else
      Map.drop(changes, @mod_fields)
    end
  end

  # Applied separately from context.apply_edit/2 because each context's edit
  # changeset only casts content fields — hidden_at/is_locked would be
  # silently dropped if threaded through. The entity returned here carries
  # the new mod state into the downstream apply_edit so its internal
  # reindex_search sees the right hidden_at.
  defp apply_mod_field_changes(entity, changes) do
    mod_changes = Map.take(changes, @mod_fields)

    if mod_changes == %{} do
      {:ok, entity}
    else
      entity |> Ecto.Changeset.change(mod_changes) |> Repo.update()
    end
  end

  # When the only field group that changed is "moderation", tag the change
  # row with the specific mod action so the audit log and history surfaces
  # keep their semantics. Everything else stays :edit.
  defp classify_action(["moderation"], original, changes) do
    cond do
      Map.has_key?(changes, :hidden_at) and
          Map.get(changes, :hidden_at) != Map.get(original, :hidden_at) ->
        if is_nil(Map.get(original, :hidden_at)), do: :hide, else: :unhide

      Map.has_key?(changes, :is_locked) and
          Map.get(changes, :is_locked) != Map.get(original, :is_locked, false) ->
        if Map.get(changes, :is_locked), do: :lock, else: :unlock

      true ->
        :edit
    end
  end

  defp classify_action(_changed, _original, _changes), do: :edit

  # Emit an activity entry for user-authored revisions. System / VNDB-sync
  # writes are skipped — they get aggregated via the dedicated
  # `:imported_vndb` activity instead, and would otherwise flood the feed
  # on every dump sync.
  defp record_revision_activity(change, user)
  defp record_revision_activity(_change, nil), do: :ok

  defp record_revision_activity(%Change{source: :user} = change, user) do
    activity_action =
      case change.action do
        :create -> :created_entity
        :revert -> :reverted_entity
        :edit -> :edited_entity
        # :hide / :unhide / :lock / :unlock — mod audit only, skip the social feed.
        _ -> nil
      end

    if activity_action do
      metadata = %{
        revision_id: change.id,
        revision_number: change.revision_number,
        target_entity_id: change.entity_id,
        summary: change.summary,
        changed_fields: change.changed_fields
      }

      Activities.record_activity(%{
        user_id: user.id,
        action: activity_action,
        entity_type: to_string(change.entity_type),
        entity_id: change.id,
        metadata: metadata
      })
    end

    :ok
  end

  defp record_revision_activity(_change, _user), do: :ok

  # If an entity has no prior revisions (e.g. created by a pre-fix dump sync
  # that didn't write a :create), synthesize one with the pre-edit snapshot
  # before the user's edit lands. Otherwise the user's first edit becomes r1
  # and the diff page shows it as "initial import" — misleading, and leaves
  # no reversible state.
  defp ensure_initial_revision(entity_type, entity_id, context) do
    # Serialize with any other writer on the same entity. Reentrant within the
    # txn, so create_change/7's own lock call below is a no-op.
    Repo.query!(
      "SELECT pg_advisory_xact_lock(hashtext($1))",
      [advisory_lock_key(entity_type, entity_id)]
    )

    has_any =
      from(c in Change,
        where: c.entity_type == ^entity_type and c.entity_id == ^entity_id,
        limit: 1
      )
      |> Repo.exists?()

    if has_any do
      :ok
    else
      preloaded = context.get_for_edit(entity_id)

      inserted_at =
        (preloaded && Map.get(preloaded, :inserted_at)) ||
          DateTime.utc_now() |> DateTime.truncate(:second)

      changeset =
        Change.changeset(%Change{}, %{
          entity_type: entity_type,
          entity_id: entity_id,
          revision_number: 1,
          action: :create,
          changed_fields: [],
          summary: "Imported from VNDB dump",
          source: :vndb_sync,
          user_id: nil
        })

      with {:ok, change} <- Repo.insert(changeset) do
        # Backdate inserted_at to the entity's creation so the feed
        # chronology stays honest.
        from(c in Change, where: c.id == ^change.id)
        |> Repo.update_all(set: [inserted_at: DateTime.truncate(inserted_at, :second)])

        if preloaded, do: context.write_hist(change.id, preloaded)
        :ok
      end
    end
  end

  @doc """
  Reverts an entity to the state captured in a previous revision.
  Loads the _hist data from the target change, applies it as a new edit.
  """
  def revert_to_revision(change_id, summary, user) do
    with {:ok, change} <- get_change(change_id),
         {:ok, context} <- fetch_context(change.entity_type) do
      hist_data = context.load_hist(change.id)

      result =
        Repo.transact(fn ->
          Repo.query!("SELECT pg_advisory_xact_lock(hashtext($1))", [
            advisory_lock_key(change.entity_type, change.entity_id)
          ])

          with {:ok, entity} <- fetch_entity(context, change.entity_id),
               :ok <- check_not_hidden(entity, user),
               :ok <- check_not_locked(entity, user),
               {:ok, entity} <- context.apply_hist(entity, hist_data),
               {:ok, new_change} <-
                 create_change(
                   change.entity_type,
                   change.entity_id,
                   :revert,
                   [],
                   summary,
                   :user,
                   user
                 ) do
            entity = context.get_for_edit(entity.id)
            context.write_hist(new_change.id, entity)
            increment_edit_count(user)
            record_revision_activity(new_change, user)
            {:ok, new_change}
          end
        end)

      maybe_recompute_content_score(change.entity_type, change.entity_id, result)
      result
    end
  end

  @doc """
  Creates a new entity with revision 1.
  """
  def create_entity(entity_type, attrs, summary, user) do
    with {:ok, context} <- fetch_context(entity_type) do
      result =
        Repo.transact(fn ->
          with {:ok, entity} <- context.create_from_edit(attrs) do
            entity = context.get_for_edit(entity.id)

            with {:ok, change} <-
                   create_change(entity_type, entity.id, :create, [], summary, :user, user) do
              context.write_hist(change.id, entity)
              increment_edit_count(user)
              record_revision_activity(change, user)
              {:ok, %{change: change, entity: entity}}
            end
          end
        end)

      case result do
        {:ok, %{entity: %{id: id}}} -> maybe_recompute_content_score(entity_type, id, {:ok, nil})
        _ -> :ok
      end

      result
    end
  end

  @doc """
  Creates a change for system/sync operations (no user, no conflict check).
  """
  def create_system_change(entity_type, entity_id, summary, opts \\ []) do
    source = Keyword.get(opts, :source, :system)
    action = Keyword.get(opts, :action, :create)
    changed_fields = Keyword.get(opts, :changed_fields, [])

    with {:ok, context} <- fetch_context(entity_type) do
      Repo.transact(fn ->
        with {:ok, change} <-
               create_change(entity_type, entity_id, action, changed_fields, summary, source, nil) do
          entity = context.get_for_edit(entity_id)
          context.write_hist(change.id, entity)
          {:ok, change}
        end
      end)
    end
  end

  @doc """
  Writes many system change rows + hist snapshots in one pass. Intended for
  bulk sync paths (dump_sync, backfills) that would otherwise trip the
  per-row `create_system_change/4` latency into unworkable territory.

  `entries` is a list of maps:

      %{entity_type: :visual_novel, entity_id: uuid,
        changed_fields: ["cover"], summary: "…", action: :edit (optional),
        source: :vndb_sync (optional), inserted_at: DateTime (optional)}

  Defaults: action `:create`, source `:vndb_sync`. Entries are processed
  in chunks of 500 by entity_type; each chunk shares a single transaction.

  Returns `{:ok, count}` on success.
  """
  @bulk_chunk_size 500

  def bulk_create_system_changes(entries, opts \\ [])

  def bulk_create_system_changes([], _opts), do: {:ok, 0}

  def bulk_create_system_changes(entries, opts) when is_list(entries) do
    entries
    |> Enum.group_by(& &1.entity_type)
    |> Enum.reduce_while({:ok, 0}, fn {entity_type, group}, {:ok, acc} ->
      with {:ok, context} <- fetch_context(entity_type),
           {:ok, count} <- bulk_write_group(entity_type, context, group, opts) do
        {:cont, {:ok, acc + count}}
      else
        err -> {:halt, err}
      end
    end)
  end

  defp bulk_write_group(entity_type, context, entries, opts) do
    entries
    |> Enum.chunk_every(@bulk_chunk_size)
    |> Enum.reduce_while({:ok, 0}, fn chunk, {:ok, acc} ->
      case write_bulk_chunk(entity_type, context, chunk, opts) do
        {:ok, n} -> {:cont, {:ok, acc + n}}
        err -> {:halt, err}
      end
    end)
  end

  defp write_bulk_chunk(entity_type, context, chunk, opts) do
    try do
      do_write_bulk_chunk(entity_type, context, chunk, opts)
    rescue
      error in [Ecto.ConstraintError, Postgrex.Error] ->
        if retry_bulk_chunk_with_locks?(error, opts) do
          do_write_bulk_chunk(
            entity_type,
            context,
            chunk,
            opts
            |> Keyword.put(:advisory_locks, true)
            |> Keyword.put(:retried_with_locks, true)
          )
        else
          reraise error, __STACKTRACE__
        end
    end
  end

  defp do_write_bulk_chunk(entity_type, context, chunk, opts) do
    Repo.transact(fn ->
      # Sorted + deduped entity ids. Sorting is important for deadlock
      # avoidance: if another writer takes advisory locks in the same
      # order, we can't deadlock on overlapping sets.
      entity_ids = chunk |> Enum.map(& &1.entity_id) |> Enum.uniq() |> Enum.sort()

      # Serialize against concurrent writers on the same entity. Without
      # this, two transactions (e.g. a weekly vndb_sync racing a user
      # edit) can read the same max(revision_number) below and collide
      # on the (entity_type, entity_id, revision_number) unique index —
      # the insert_all then raises and rolls back the whole chunk.
      # Matches the lock key used by create_change/7 so the bulk and
      # single-row paths exclude each other on the same entity.
      if Keyword.get(opts, :advisory_locks, true) do
        lock_advisory_entities(entity_type, entity_ids)
      end

      # Load current max revision number per entity in one query.
      current_max_map =
        from(c in Change,
          where: c.entity_type == ^entity_type and c.entity_id in ^entity_ids,
          group_by: c.entity_id,
          select: {c.entity_id, max(c.revision_number)}
        )
        |> Repo.all()
        |> Map.new()

      # Build change rows with per-entity incremented revision numbers.
      # If the same entity appears twice in the chunk, we give them
      # consecutive numbers — tracked via local map update.
      {change_rows, _final_map} =
        Enum.map_reduce(chunk, current_max_map, fn entry, acc ->
          current = Map.get(acc, entry.entity_id, 0)
          next = current + 1
          acc = Map.put(acc, entry.entity_id, next)

          row = %{
            id: UUIDv7.generate(),
            entity_type: entity_type,
            entity_id: entry.entity_id,
            revision_number: next,
            action: Map.get(entry, :action, :create),
            changed_fields: Map.get(entry, :changed_fields, []),
            summary: Map.fetch!(entry, :summary),
            source: Map.get(entry, :source, :vndb_sync),
            user_id: nil,
            inserted_at:
              Map.get(entry, :inserted_at, DateTime.utc_now() |> DateTime.truncate(:second))
          }

          {{row, entry}, acc}
        end)

      {rows, _entries} = Enum.unzip(change_rows)

      # Insert all change rows in one shot.
      {count, _} = Repo.insert_all(Change, rows)

      # Now write hist snapshots — one per row. The context's
      # batch_load_for_hist/1 mirrors get_for_edit/1's preload surface
      # but in one round-trip per preload regardless of chunk size.
      entities_by_id =
        context.batch_load_for_hist(entity_ids)
        |> Map.new(&{&1.id, &1})

      write_bulk_hist(context, change_rows, entities_by_id)

      {:ok, count}
    end)
  end

  defp retry_bulk_chunk_with_locks?(error, opts) do
    Keyword.get(opts, :advisory_locks, true) == false and
      Keyword.get(opts, :retried_with_locks, false) == false and
      revision_number_conflict?(error)
  end

  defp revision_number_conflict?(%Ecto.ConstraintError{constraint: constraint}) do
    constraint == "changes_entity_type_entity_id_revision_number_index"
  end

  defp revision_number_conflict?(%Postgrex.Error{postgres: %{constraint: constraint}}) do
    constraint == "changes_entity_type_entity_id_revision_number_index"
  end

  defp revision_number_conflict?(_error), do: false

  defp lock_advisory_entities(_entity_type, []), do: :ok

  defp lock_advisory_entities(entity_type, entity_ids) do
    keys = Enum.map(entity_ids, &advisory_lock_key(entity_type, &1))

    Repo.query!(
      """
      SELECT pg_advisory_xact_lock(hashtext(k))
      FROM unnest($1::text[]) AS locks(k)
      """,
      [keys]
    )

    :ok
  end

  defp advisory_lock_key(entity_type, entity_id) do
    "#{entity_type}:#{normalize_lock_entity_id(entity_id)}"
  end

  defp normalize_lock_entity_id(entity_id) when is_binary(entity_id) do
    cond do
      byte_size(entity_id) == 16 ->
        case Ecto.UUID.load(entity_id) do
          {:ok, uuid} -> uuid
          :error -> Base.encode16(entity_id, case: :lower)
        end

      String.valid?(entity_id) ->
        entity_id

      true ->
        Base.encode16(entity_id, case: :lower)
    end
  end

  defp normalize_lock_entity_id(entity_id), do: to_string(entity_id)

  defp write_bulk_hist(context, change_rows, entities_by_id) do
    pairs =
      change_rows
      |> Enum.flat_map(fn {row, _entry} ->
        case Map.get(entities_by_id, row.entity_id) do
          nil -> []
          entity -> [{row.id, entity}]
        end
      end)

    context.bulk_write_hist(pairs)
  end

  @doc """
  Hides/unhides/locks/unlocks an entity. Thin wrapper around `submit_edit/6`
  that supplies the mod-flag change for callers (LiveView/controllers, internal
  flows) that prefer an action-named entry point. The actual permission
  boundary and write path live inside `submit_edit/6`.
  """
  def record_mod_action(entity_type, entity_id, action, summary, user)
      when action in [:hide, :unhide, :lock, :unlock] do
    submit_edit(entity_type, entity_id, mod_changes_for(action), summary, user, action: action)
  end

  defp mod_changes_for(:hide),
    do: %{hidden_at: DateTime.utc_now() |> DateTime.truncate(:second)}

  defp mod_changes_for(:unhide), do: %{hidden_at: nil}
  defp mod_changes_for(:lock), do: %{is_locked: true}
  defp mod_changes_for(:unlock), do: %{is_locked: false}

  # ============================================================================
  # Queries
  # ============================================================================

  def get_change(id) do
    case Repo.one(from c in Change, where: c.id == ^id) do
      nil -> {:error, :not_found}
      change -> {:ok, change}
    end
  end

  @doc """
  Gets a change with its full _hist data loaded as a map.
  """
  def get_revision(id) do
    with {:ok, change} <- get_change(id),
         {:ok, context} <- fetch_context(change.entity_type) do
      hist_data = context.load_hist(change.id)
      {:ok, Map.put(change, :snapshot, Diff.serialize_hist(hist_data))}
    end
  end

  @doc """
  Compares two revisions of the same entity side by side.
  Returns both snapshots + a list of field-level differences.

  Diffs are identity-aware: sub-entity rows are matched by their natural key
  (e.g. `cover_id` for covers, `lang` for titles) so a single-field edit shows
  as one `changed` row, not as a remove + add pair. Image-id fields on both
  the main entity and sub-entity rows are augmented with public URLs.
  """
  def diff_revisions(change_id) do
    with {:ok, change} <- get_change(change_id),
         {:ok, context} <- fetch_context(change.entity_type) do
      current = context.load_hist(change.id)

      previous_change =
        from(c in Change,
          where:
            c.entity_type == ^change.entity_type and c.entity_id == ^change.entity_id and
              c.revision_number < ^change.revision_number,
          order_by: [desc: c.revision_number],
          limit: 1
        )
        |> Repo.one()

      previous =
        if previous_change do
          context.load_hist(previous_change.id)
        else
          nil
        end

      current_serialized = Diff.serialize_hist(current)
      previous_serialized = Diff.serialize_hist(previous)
      diff = Diff.compute_diff(previous, current)

      # Enrich VN UUIDs → titles and image IDs → URLs across snapshots + diff.
      {current_serialized, previous_serialized, diff} =
        Enrichment.enrich_one(change.entity_type, current_serialized, previous_serialized, diff)

      {:ok,
       %{
         change: change,
         previous_change: previous_change,
         current: current_serialized,
         previous: previous_serialized,
         diff: diff
       }}
    end
  end

  @doc """
  Batched diff loader for the activity log feed. Computes the diff for a
  list of change_ids in O(entity_types) round-trips instead of O(N×7).

  For 25 changes spanning all 4 entity types: ~12 queries total (1 for
  current + previous change rows, 1 per entity_type for hist tables × 7
  related-table queries per VN, less for others). For 25 same-type changes:
  ~10 queries.

  Returns `%{change_id => %{change, previous_change, current, previous, diff}}`.
  Used by feed/page callers that need revision diffs without N+1 queries.
  """
  def batch_load_diffs(_key, []), do: %{}

  def batch_load_diffs(_key, change_ids) when is_list(change_ids) do
    ids = Enum.uniq(change_ids)

    current_changes =
      Repo.all(from c in Change, where: c.id in ^ids)
      |> Map.new(&{&1.id, &1})

    # Find previous revision for each change. Load all revisions for each
    # involved (entity_type, entity_id) pair (typically only 2-3 revisions
    # per entity in the orphan-fix-era data), then pick the immediate
    # predecessor in Elixir.
    by_entity =
      current_changes
      |> Map.values()
      |> Enum.group_by(&{&1.entity_type, &1.entity_id})

    entity_revs_by_type =
      by_entity
      |> Map.keys()
      |> Enum.group_by(fn {et, _} -> et end, fn {_, id} -> id end)

    all_revs_per_entity =
      Enum.reduce(entity_revs_by_type, %{}, fn {entity_type, entity_ids}, acc ->
        entity_ids = Enum.uniq(entity_ids)

        revs =
          Repo.all(
            from c in Change,
              where: c.entity_type == ^entity_type and c.entity_id in ^entity_ids
          )

        revs_grouped = Enum.group_by(revs, &{&1.entity_type, &1.entity_id})
        Map.merge(acc, revs_grouped)
      end)

    prev_for_each =
      Map.new(current_changes, fn {id, change} ->
        candidates = Map.get(all_revs_per_entity, {change.entity_type, change.entity_id}, [])

        prev =
          candidates
          |> Enum.filter(&(&1.revision_number < change.revision_number))
          |> Enum.max_by(& &1.revision_number, fn -> nil end)

        {id, prev}
      end)

    # Collect every change_id we need to load hist for (current + previous),
    # grouped by entity_type so each context's bulk_load_hist gets one call.
    hist_ids_by_type =
      Enum.reduce(current_changes, %{}, fn {_id, c}, acc ->
        acc = Map.update(acc, c.entity_type, [c.id], &[c.id | &1])

        case Map.get(prev_for_each, c.id) do
          nil -> acc
          prev -> Map.update(acc, prev.entity_type, [prev.id], &[prev.id | &1])
        end
      end)

    hist_by_change_id =
      Enum.reduce(hist_ids_by_type, %{}, fn {entity_type, change_ids}, acc ->
        case fetch_context(entity_type) do
          {:ok, context} ->
            type_hists = context.bulk_load_hist(Enum.uniq(change_ids))
            Map.merge(acc, type_hists)

          {:error, _} ->
            acc
        end
      end)

    # Build serialized + diff for each change, then enrich the whole batch in
    # one set of lookup queries — Enrichment.enrich_many/1 collects every
    # referenced id across the batch so each entry doesn't re-issue lookups.
    raw_entries =
      Enum.map(current_changes, fn {id, change} ->
        prev = Map.get(prev_for_each, id)
        current_hist = Map.get(hist_by_change_id, id)
        prev_hist = if prev, do: Map.get(hist_by_change_id, prev.id), else: nil

        current_serialized = Diff.serialize_hist(current_hist)
        prev_serialized = Diff.serialize_hist(prev_hist)
        diff = Diff.compute_diff(prev_hist, current_hist)

        {id, change, prev, current_serialized, prev_serialized, diff}
      end)

    enriched =
      raw_entries
      |> Enum.map(fn {id, change, _prev, current, previous, diff} ->
        {id, change.entity_type, current, previous, diff}
      end)
      |> Enrichment.enrich_many()

    Map.new(raw_entries, fn {id, change, prev, _current, _previous, _diff} ->
      {current, previous, diff} = Map.fetch!(enriched, id)

      {id,
       %{
         change: change,
         previous_change: prev,
         current: current,
         previous: previous,
         diff: diff
       }}
    end)
  end

  @list_fields [
    :id,
    :entity_type,
    :entity_id,
    :revision_number,
    :action,
    :changed_fields,
    :summary,
    :source,
    :user_id,
    :inserted_at
  ]

  def list_revisions(entity_type, entity_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 25)
    offset = Keyword.get(opts, :offset, 0)

    from(c in Change,
      where: c.entity_type == ^entity_type and c.entity_id == ^entity_id,
      order_by: [desc: c.revision_number],
      select: map(c, ^@list_fields),
      limit: ^limit,
      offset: ^offset
    )
    |> Repo.all()
  end

  # Global recent-changes feed defaults to user-authored revisions only —
  # matches VNDB's `m=1` default on Misc/History (system imports + sync edits
  # would otherwise drown out user activity, especially right after a
  # 400k-entity seed). Per-entity history (list_revisions/3) is unfiltered.
  # Callers can still pass `sources: [:user, :system, :vndb_sync]` to see
  # everything.
  def recent_changes(opts \\ []) do
    limit = Keyword.get(opts, :limit, 25)
    offset = Keyword.get(opts, :offset, 0)
    opts = Keyword.put_new(opts, :sources, [:user])

    from(c in Change,
      order_by: [desc: c.inserted_at],
      select: map(c, ^@list_fields),
      limit: ^limit,
      offset: ^offset
    )
    |> apply_feed_filters(opts)
    |> exclude_hidden_revision_targets()
    |> Repo.all()
  end

  def recent_changes_count(opts \\ []) do
    opts = Keyword.put_new(opts, :sources, [:user])

    from(c in Change, select: count())
    |> apply_feed_filters(opts)
    |> exclude_hidden_revision_targets()
    |> Repo.one()
  end

  def user_revisions(user_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 25)
    offset = Keyword.get(opts, :offset, 0)

    from(c in Change,
      where: c.user_id == ^user_id,
      order_by: [desc: c.inserted_at],
      select: map(c, ^@list_fields),
      limit: ^limit,
      offset: ^offset
    )
    |> apply_feed_filters(opts)
    |> exclude_hidden_revision_targets()
    |> Repo.all()
  end

  def user_revisions_count(user_id, opts \\ []) do
    from(c in Change, where: c.user_id == ^user_id, select: count())
    |> apply_feed_filters(opts)
    |> exclude_hidden_revision_targets()
    |> Repo.one()
  end

  @doc """
  Returns the most recently edited entities for a user, with per-entity edit
  count and last-edited timestamp. Powers the "Recent Activity" cards on the
  profile contributions tab. Filtered to `source = :user` so dump-sync /
  system-authored revisions don't show up in personal stats.

  Returns: `[%{entity_type, entity_id, edit_count, last_edited_at}]`.
  """
  def recent_edited_entities(user_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 5)

    base =
      from c in Change,
        where: c.user_id == ^user_id and c.source == :user,
        group_by: [c.entity_type, c.entity_id],
        order_by: [desc: max(c.inserted_at)],
        limit: ^limit,
        select: %{
          entity_type: c.entity_type,
          entity_id: c.entity_id,
          edit_count: count(c.id),
          last_edited_at: max(c.inserted_at)
        }

    base = maybe_filter_entity_type(base, Keyword.get(opts, :entity_type))

    base
    |> exclude_hidden_revision_targets()
    |> Repo.all()
  end

  @doc """
  Returns daily edit counts for a user over a date range, grouped by
  entity_type. Powers the activity chart on the profile contributions tab.
  Defaults: last 30 days, all entity types. Filtered to `source = :user`.

  Returns: `[%{day, entity_type, count}]` sorted by day ascending.
  """
  def edit_timeseries(user_id, opts \\ []) do
    today = Date.utc_today()
    from_date = Keyword.get(opts, :from_date, Date.add(today, -29))
    to_date = Keyword.get(opts, :to_date, today)

    # Range is half-open [from, to_exclusive) on inserted_at.
    from_dt = DateTime.new!(from_date, ~T[00:00:00], "Etc/UTC")
    to_exclusive_dt = DateTime.new!(Date.add(to_date, 1), ~T[00:00:00], "Etc/UTC")

    base =
      from c in Change,
        where:
          c.user_id == ^user_id and c.source == :user and
            c.inserted_at >= ^from_dt and c.inserted_at < ^to_exclusive_dt,
        group_by: [fragment("(?)::date", c.inserted_at), c.entity_type],
        order_by: [asc: fragment("(?)::date", c.inserted_at)],
        select: %{
          day: fragment("(?)::date", c.inserted_at),
          entity_type: c.entity_type,
          count: count(c.id)
        }

    base = maybe_filter_entity_types(base, Keyword.get(opts, :entity_types))

    base
    |> exclude_hidden_revision_targets()
    |> Repo.all()
  end

  # Shared filter composition for the recent-changes / user-revisions feeds.
  # nil or [] means "no filter on this dimension". `entity_type` (singular,
  # legacy) is still accepted so older callers keep working.
  defp apply_feed_filters(query, opts) do
    query
    |> maybe_filter_entity_type(Keyword.get(opts, :entity_type))
    |> maybe_filter_entity_types(Keyword.get(opts, :entity_types))
    |> maybe_filter_actions(Keyword.get(opts, :actions))
    |> maybe_filter_sources(Keyword.get(opts, :sources))
    |> maybe_filter_user(Keyword.get(opts, :user_id))
  end

  # Filter semantics: `nil` (arg omitted) = no filter; `[]` (explicitly
  # empty) = match nothing. This matters for the UI — if a user hides every
  # action type, we should return zero rows, not everything.
  defp maybe_filter_entity_types(query, nil), do: query
  defp maybe_filter_entity_types(query, []), do: from(c in query, where: false)

  defp maybe_filter_entity_types(query, types) when is_list(types) do
    from(c in query, where: c.entity_type in ^types)
  end

  defp maybe_filter_actions(query, nil), do: query
  defp maybe_filter_actions(query, []), do: from(c in query, where: false)

  defp maybe_filter_actions(query, actions) when is_list(actions) do
    from(c in query, where: c.action in ^actions)
  end

  defp maybe_filter_sources(query, nil), do: query
  defp maybe_filter_sources(query, []), do: from(c in query, where: false)

  defp maybe_filter_sources(query, sources) when is_list(sources) do
    from(c in query, where: c.source in ^sources)
  end

  defp maybe_filter_user(query, nil), do: query

  defp maybe_filter_user(query, user_id) do
    from(c in query, where: c.user_id == ^user_id)
  end

  defp exclude_hidden_revision_targets(query) do
    hidden_target_types = [
      {:visual_novel, Kaguya.VisualNovels.VisualNovel},
      {:character, Kaguya.Characters.Character},
      {:producer, Kaguya.Producers.Producer},
      {:release, Kaguya.Releases.Release},
      {:series, Kaguya.VisualNovels.Series}
    ]

    query = from(c in query, as: :change)

    Enum.reduce(hidden_target_types, query, fn {entity_type, schema}, acc ->
      hidden_target_exists =
        from(e in schema,
          where: not is_nil(e.hidden_at),
          where: e.id == parent_as(:change).entity_id,
          select: 1
        )

      from(c in acc,
        where: not (c.entity_type == ^entity_type and exists(subquery(hidden_target_exists)))
      )
    end)
  end

  @doc """
  Batch loads the parent entities referenced by a set of `{entity_type,
  entity_id}` pairs. Used to render entity titles/links on the recent-changes
  feed with one query per
  entity type regardless of how many revisions are in the list.

  Returns a map of `{entity_type, entity_id} => entity_struct`. Hidden or
  deleted entities are omitted — callers must handle missing entries.
  """
  def batch_load_entities(pairs) when is_list(pairs) do
    pairs
    |> Enum.group_by(fn {type, _id} -> type end, fn {_type, id} -> id end)
    |> Enum.reduce(%{}, fn {type, ids}, acc ->
      entities = load_entities_of_type(type, Enum.uniq(ids))

      Enum.reduce(entities, acc, fn entity, inner ->
        Map.put(inner, {type, entity.id}, entity)
      end)
    end)
  end

  defp load_entities_of_type(:visual_novel, ids) do
    from(v in Kaguya.VisualNovels.VisualNovel, where: v.id in ^ids) |> Repo.all()
  end

  defp load_entities_of_type(:character, ids) do
    from(c in Kaguya.Characters.Character, where: c.id in ^ids) |> Repo.all()
  end

  defp load_entities_of_type(:producer, ids) do
    from(p in Kaguya.Producers.Producer, where: p.id in ^ids) |> Repo.all()
  end

  defp load_entities_of_type(:release, ids) do
    from(r in Kaguya.Releases.Release, where: r.id in ^ids, preload: [:visual_novel])
    |> Repo.all()
  end

  defp load_entities_of_type(:series, ids) do
    from(s in Kaguya.VisualNovels.Series, where: s.id in ^ids) |> Repo.all()
  end

  defp load_entities_of_type(_, _), do: []

  def revision_count(entity_type, entity_id) do
    from(c in Change,
      where: c.entity_type == ^entity_type and c.entity_id == ^entity_id,
      select: count()
    )
    |> Repo.one()
  end

  def latest_revision_number(entity_type, entity_id) do
    from(c in Change,
      where: c.entity_type == ^entity_type and c.entity_id == ^entity_id,
      select: max(c.revision_number)
    )
    |> Repo.one()
    |> Kernel.||(0)
  end

  # ============================================================================
  # Private
  # ============================================================================

  defp fetch_entity(context, entity_id) do
    case context.get_for_edit(entity_id) do
      nil -> {:error, :not_found}
      entity -> {:ok, entity}
    end
  end

  defp check_not_hidden(entity, user) do
    cond do
      is_nil(Map.get(entity, :hidden_at)) -> :ok
      Authorization.can_moderate_db?(user) -> :ok
      true -> {:error, "Entry is hidden"}
    end
  end

  defp check_not_locked(entity, user) do
    cond do
      not Map.get(entity, :is_locked, false) -> :ok
      Authorization.can_moderate_db?(user) -> :ok
      true -> {:error, "Entry is locked for editing"}
    end
  end

  defp check_base_revision(_entity_type, _entity_id, nil), do: :ok

  defp check_base_revision(entity_type, entity_id, base_revision) do
    if latest_revision_number(entity_type, entity_id) == base_revision do
      :ok
    else
      {:error, :edit_conflict}
    end
  end

  defp compute_changed_fields(entity_type, entity, changes) do
    context = Map.fetch!(@entity_config, entity_type)
    context.changed_field_groups(entity, changes)
  end

  defp validate_has_changes([]), do: {:error, "No changes detected"}
  defp validate_has_changes(_changed), do: :ok

  defp create_change(entity_type, entity_id, action, changed_fields, summary, source, user) do
    Repo.query!("SELECT pg_advisory_xact_lock(hashtext($1))", [
      advisory_lock_key(entity_type, entity_id)
    ])

    next_number =
      from(c in Change,
        where: c.entity_type == ^entity_type and c.entity_id == ^entity_id,
        select: max(c.revision_number)
      )
      |> Repo.one()
      |> Kernel.||(0)
      |> Kernel.+(1)

    %Change{}
    |> Change.changeset(%{
      entity_type: entity_type,
      entity_id: entity_id,
      revision_number: next_number,
      action: action,
      changed_fields: changed_fields,
      summary: summary,
      source: source,
      user_id: user && user.id
    })
    |> Repo.insert()
  end

  defp increment_edit_count(nil), do: :ok

  defp increment_edit_count(user) do
    from(u in Kaguya.Users.User, where: u.id == ^user.id)
    |> Repo.update_all(inc: [edit_count: 1])

    :ok
  end

  defp fetch_context(entity_type) do
    case Map.fetch(@entity_config, entity_type) do
      {:ok, context} -> {:ok, context}
      :error -> {:error, "Editing #{entity_type} is not yet supported"}
    end
  end

  defp maybe_filter_entity_type(query, nil), do: query

  defp maybe_filter_entity_type(query, entity_type) do
    from(c in query, where: c.entity_type == ^entity_type)
  end

  # Recompute the VN's content score after a successful edit/create/revert.
  # Runs outside the txn because the score is derived and non-critical — a
  # ContentScore bug must not roll back a real user edit. Currently scoped
  # to :visual_novel; extend per-entity-type when other entities get scored.
  defp maybe_recompute_content_score(:visual_novel, vn_id, {:ok, _}) when is_binary(vn_id) do
    Kaguya.ContentScore.recompute_visual_novel(vn_id)
  rescue
    e ->
      Logger.error(
        "ContentScore recompute failed for #{vn_id}: " <>
          Exception.format(:error, e, __STACKTRACE__)
      )

      :ok
  end

  defp maybe_recompute_content_score(_, _, _), do: :ok

  defp update_search_index(:visual_novel, entity_id) do
    vn =
      Kaguya.VisualNovels.VisualNovel
      |> Repo.get(entity_id)
      |> Repo.preload([:primary_image, :vn_titles, vn_producers: :producer])

    cond do
      is_nil(vn) -> :ok
      vn.hidden_at != nil -> Kaguya.SearchIndex.remove_visual_novel(entity_id)
      true -> Kaguya.SearchIndex.index_visual_novels(vn)
    end
  rescue
    e -> log_search_index_failure(:visual_novel, entity_id, e, __STACKTRACE__)
  end

  defp update_search_index(:character, entity_id) do
    char = Repo.get(Kaguya.Characters.Character, entity_id)

    cond do
      is_nil(char) -> :ok
      char.hidden_at != nil -> Kaguya.SearchIndex.remove_character(entity_id)
      true -> Kaguya.SearchIndex.index_characters(char)
    end
  rescue
    e -> log_search_index_failure(:character, entity_id, e, __STACKTRACE__)
  end

  defp update_search_index(:producer, entity_id) do
    producer = Repo.get(Kaguya.Producers.Producer, entity_id)

    cond do
      is_nil(producer) -> :ok
      producer.hidden_at != nil -> Kaguya.SearchIndex.remove_producer(entity_id)
      true -> Kaguya.SearchIndex.index_producers(producer)
    end
  rescue
    e -> log_search_index_failure(:producer, entity_id, e, __STACKTRACE__)
  end

  # Releases aren't indexed as their own document — their data feeds the
  # parent VN's search payload (release_date, etc.) and the
  # `available_on_stores` / `free_on_stores` SQL filters via release extlinks.
  # Editing or hiding a release can change either, so we reindex the parent
  # VN here. Lookup is best-effort — if the release was already deleted,
  # fall through.
  defp update_search_index(:release, entity_id) do
    case Repo.get(Kaguya.Releases.Release, entity_id) do
      %{visual_novel_id: vn_id} when not is_nil(vn_id) ->
        update_search_index(:visual_novel, vn_id)

      _ ->
        :ok
    end
  rescue
    e -> log_search_index_failure(:release, entity_id, e, __STACKTRACE__)
  end

  defp update_search_index(_entity_type, _entity_id), do: :ok

  # Search-index updates run after the edit transaction has committed, so
  # they must never crash the calling process. Catch broadly to preserve
  # that guarantee, but log with full stacktrace so typos and upstream API
  # changes surface in error tracking instead of disappearing.
  defp log_search_index_failure(entity_type, entity_id, exception, stacktrace) do
    Logger.error(
      "Search index update failed for #{entity_type} #{entity_id}: " <>
        Exception.format(:error, exception, stacktrace)
    )

    :ok
  end
end
