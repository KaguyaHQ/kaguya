defmodule Kaguya.SlugRedirects.SlugRedirect do
  @moduledoc """
  Schema for the `slug_redirects` table — one row per historical URL.

  Globally-scoped entity types leave `scope_id` NULL. User-scoped types
  (lists, shelves) carry the owning user's id in `scope_id`; the unique
  index uses `NULLS NOT DISTINCT` so NULL behaves like a value.
  """
  use Kaguya.Schema

  @entity_types [:vn, :character, :producer, :tag, :series, :list, :shelf]
  @reasons [:rename, :merge, :manual]

  @scoped_types [:list, :shelf]

  @type t :: %__MODULE__{}

  schema "slug_redirects" do
    field :entity_type, Ecto.Enum, values: @entity_types
    field :old_slug, :string
    field :target_id, Ecto.UUID
    field :scope_id, Ecto.UUID
    field :reason, Ecto.Enum, values: @reasons

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def entity_types, do: @entity_types
  def scoped_types, do: @scoped_types
  def scoped?(type) when is_atom(type), do: type in @scoped_types

  def changeset(redirect, attrs) do
    redirect
    |> cast(attrs, [:entity_type, :old_slug, :target_id, :scope_id, :reason])
    |> validate_required([:entity_type, :old_slug, :target_id])
    |> validate_length(:old_slug, min: 1, max: 255)
    |> validate_scope_consistency()
    |> unique_constraint([:entity_type, :scope_id, :old_slug],
      name: :slug_redirects_entity_type_scope_id_old_slug_index
    )
  end

  defp validate_scope_consistency(changeset) do
    type = get_field(changeset, :entity_type)
    scope = get_field(changeset, :scope_id)

    cond do
      is_nil(type) ->
        changeset

      type in @scoped_types and is_nil(scope) ->
        add_error(changeset, :scope_id, "is required for #{type} redirects")

      type not in @scoped_types and not is_nil(scope) ->
        add_error(changeset, :scope_id, "must be NULL for #{type} redirects")

      true ->
        changeset
    end
  end
end
