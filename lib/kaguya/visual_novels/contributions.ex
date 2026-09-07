defmodule Kaguya.VisualNovels.Contributions do
  @moduledoc "Atomic VN contributions with release-specific producer credits."
  import Ecto.Query
  alias Kaguya.{Authorization, Repo, Revisions, VisualNovels}
  alias Kaguya.Releases.Release
  alias Kaguya.Producers.Producer

  def create(attrs, release_edits, summary, user) do
    with :ok <- editable_user(user) do
      result =
        Repo.transact(fn ->
          with {:ok, result} <- Revisions.create_entity(:visual_novel, attrs, summary, user),
               :ok <- save_releases(result.entity, release_edits, summary, user) do
            {:ok, result}
          end
        end)

      refresh(result)
    end
  end

  def update(vn_id, changes, release_edits, summary, user, base_revision) do
    with :ok <- editable_user(user) do
      result =
        Repo.transact(fn ->
          lock_entity(:visual_novel, vn_id)
          vn = VisualNovels.get_visual_novel(vn_id, include_hidden: true)

          with :ok <- editable_vn(vn, user),
               true <- Revisions.latest_revision_number(:visual_novel, vn_id) == base_revision,
               :ok <- update_vn(vn_id, changes, summary, user, base_revision),
               :ok <-
                 save_releases(
                   VisualNovels.get_visual_novel(vn.id, include_hidden: true),
                   release_edits,
                   summary,
                   user
                 ) do
            {:ok, %{entity: vn}}
          else
            false -> {:error, :edit_conflict}
            error -> error
          end
        end)

      refresh(result)
    end
  end

  defp update_vn(_, changes, _, _, _) when map_size(changes) == 0, do: :ok

  defp update_vn(id, changes, summary, user, base) do
    case Revisions.submit_edit(:visual_novel, id, changes, summary, user, base_revision: base) do
      {:ok, _} -> :ok
      error -> error
    end
  end

  defp save_releases(vn, edits, summary, user) do
    ids = Enum.flat_map(edits, &if(&1.id, do: [&1.id], else: [])) |> Enum.sort()
    Enum.each(ids, &lock_entity(:release, &1))

    releases =
      Repo.all(from(r in Release, where: r.id in ^ids and r.visual_novel_id == ^vn.id))
      |> Map.new(&{&1.id, &1})

    Enum.reduce_while(edits, :ok, fn edit, :ok ->
      result =
        if edit.id do
          case Map.get(releases, edit.id) do
            nil ->
              {:error, "Release does not belong to this VN."}

            release ->
              with :ok <- validate_producers(edit.attrs, release.producers || []) do
                Revisions.submit_edit(:release, edit.id, release_title(edit.attrs), summary, user,
                  base_revision: edit.base_revision
                )
              end
          end
        else
          attrs =
            edit.attrs
            |> Map.put(:visual_novel_id, vn.id)
            |> Map.put(
              :title,
              if(edit.attrs[:title] in [nil, ""], do: vn.title, else: edit.attrs.title)
            )
            |> Map.put(:original_language, vn.original_language)
            |> Map.put(:languages, if(vn.original_language, do: [vn.original_language], else: []))
            |> Map.put(:has_ero, vn.has_ero)

          with :ok <- validate_producers(attrs, []) do
            Revisions.create_entity(:release, release_title(attrs), summary, user)
          end
        end

      case result do
        {:ok, _} -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp release_title(%{title: title} = attrs), do: Map.put(attrs, :display_title, title)
  defp release_title(attrs), do: attrs

  defp validate_producers(%{producers: credits}, previous) when is_list(credits) do
    ids =
      Enum.flat_map(credits, fn c ->
        case Ecto.UUID.cast(c["producer_id"]) do
          {:ok, id} -> [id]
          _ -> []
        end
      end)

    vndb_ids = Enum.map(credits, & &1["vndb_id"])
    producers = Repo.all(from(p in Producer, where: p.id in ^ids or p.vndb_id in ^vndb_ids))
    by_id = Map.new(producers, &{&1.id, &1})
    by_vndb = producers |> Enum.reject(&is_nil(&1.vndb_id)) |> Map.new(&{&1.vndb_id, &1})
    resolved = Enum.map(credits, fn c -> by_id[c["producer_id"]] || by_vndb[c["vndb_id"]] end)

    valid =
      Enum.zip(credits, resolved)
      |> Enum.all?(fn {c, p} ->
        # Retain unresolved legacy credits verbatim; never allow a new invalid reference.
        (c in previous or (not is_nil(p) and is_nil(p.hidden_at))) and c["invalid_role"] != true and
          is_boolean(c["developer"]) and is_boolean(c["publisher"]) and
          (c["developer"] or c["publisher"])
      end)

    keys = Enum.map(credits, &(&1["producer_id"] || &1["vndb_id"]))
    resolved_ids = Enum.map(resolved, &if(&1, do: &1.id)) |> Enum.reject(&is_nil/1)

    if valid and length(Enum.uniq(keys)) == length(keys) and
         length(Enum.uniq(resolved_ids)) == length(resolved_ids),
       do: :ok,
       else: {:error, "Choose available producers with valid, non-duplicate roles."}
  end

  defp validate_producers(attrs, _),
    do: if(Map.has_key?(attrs, :producers), do: {:error, "Invalid producer credits."}, else: :ok)

  defp lock_entity(type, id),
    do: Repo.query!("SELECT pg_advisory_xact_lock(hashtext($1))", ["#{type}:#{id}"])

  defp editable_user(%{can_edit: false}), do: {:error, "Editing is disabled for this account."}
  defp editable_user(%{id: _}), do: :ok
  defp editable_user(_), do: {:error, "Sign in to contribute."}
  defp editable_vn(nil, _), do: {:error, "Visual novel not found."}

  defp editable_vn(vn, user) do
    if (vn.is_locked or not is_nil(vn.hidden_at)) and not Authorization.can_moderate_db?(user),
      do: {:error, "This visual novel cannot be edited."},
      else: :ok
  end

  defp refresh({:ok, %{entity: vn}} = result) do
    VisualNovels.VNPageCache.invalidate(vn.id)
    VisualNovels.reindex_search(vn.id)
    result
  end

  defp refresh(error), do: error
end
