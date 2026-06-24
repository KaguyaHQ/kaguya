defmodule Kaguya.Revisions.EntityContext do
  @moduledoc """
  Contract every revisable entity context must implement so
  `Kaguya.Revisions` can dispatch into it generically.

  Until this behaviour existed, the required functions were enumerated only
  in `Kaguya.Revisions`'s moduledoc, and a missing callback would surface as
  `UndefinedFunctionError` mid-transaction. With `@behaviour
  Kaguya.Revisions.EntityContext`, the compiler now warns at build time for
  any missing or mis-arity callback.

  Implementing modules: `Kaguya.VisualNovels`, `Kaguya.Characters`,
  `Kaguya.Producers`, `Kaguya.Releases`, `Kaguya.Series`.
  """

  @type entity_id :: Ecto.UUID.t()
  @type change_id :: Ecto.UUID.t()
  @type entity :: struct()
  @type changes :: map()
  @type hist_data :: map()

  @doc """
  Loads a single entity by id with every preload needed to build an accurate
  `_hist` snapshot. Returns `nil` when the entity does not exist.
  """
  @callback get_for_edit(entity_id) :: entity | nil

  @doc """
  Bulk variant of `get_for_edit/1` for the hist write path. Issues one
  query per preload across the whole id list rather than N×preloads.
  """
  @callback batch_load_for_hist([entity_id]) :: [entity]

  @doc """
  Creates a new entity from form-style attrs.
  """
  @callback create_from_edit(map()) :: {:ok, entity} | {:error, term()}

  @doc """
  Applies an edit changeset to an existing entity. Each context's changeset
  is responsible for casting only the fields it owns — `Kaguya.Revisions`
  pre-strips mod-only fields before calling.
  """
  @callback apply_edit(entity, changes) :: {:ok, entity} | {:error, term()}

  @doc """
  Applies a prior revision's `_hist` snapshot back onto the live entity, as
  part of a revert. The hist payload shape is whatever this context's
  `load_hist/1` returns.
  """
  @callback apply_hist(entity, hist_data) :: {:ok, entity} | {:error, term()}

  @doc """
  Writes a single `_hist` snapshot keyed by `change_id`.
  """
  @callback write_hist(change_id, entity) :: any()

  @doc """
  Bulk variant of `write_hist/2` used by the dump-sync and backfill paths.
  Receives `[{change_id, entity}]` pairs.
  """
  @callback bulk_write_hist([{change_id, entity}]) :: any()

  @doc """
  Loads the `_hist` snapshot for a single `change_id`. Returns a map with
  `:hist` (the main entity hist row as a struct/map) plus sub-collection
  keys (e.g. `:titles`, `:relations`) that the diff engine knows about.
  """
  @callback load_hist(change_id) :: hist_data | nil

  @doc """
  Bulk variant of `load_hist/1` for the activity-feed diff loader.
  Returns `%{change_id => hist_data}`.
  """
  @callback bulk_load_hist([change_id]) :: %{change_id => hist_data}

  @doc """
  Given the current entity and the incoming `changes` map, returns the list
  of field-group names that would change. Drives the "no-op edit" guard and
  the change row's `changed_fields` audit column.
  """
  @callback changed_field_groups(entity, changes) :: [String.t() | atom()]
end
