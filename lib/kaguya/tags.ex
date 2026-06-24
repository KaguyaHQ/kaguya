defmodule Kaguya.Tags do
  @moduledoc """
  The Tags context.
  """
  alias Kaguya.Repo
  alias Kaguya.Tags.Tag
  import Ecto.Query

  @doc """
  Get a single tag by slug.
  """
  def get_tag_by_slug(slug) do
    Tag
    |> where([t], t.slug == ^slug)
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      tag -> {:ok, tag}
    end
  end

  @doc """
  Gets a single tag by ID.
  """
  def get_tag(id) do
    Tag
    |> where([t], t.id == ^id)
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      tag -> {:ok, tag}
    end
  end

  @doc """
  Lists all tags.
  """
  def list_tags do
    tags =
      Tag
      |> order_by([t], asc: t.name)
      |> Repo.all()

    {:ok, tags}
  end

  @doc """
  Search tags by name (case-insensitive prefix match).
  """
  def search_tags(query, limit \\ 20) do
    escaped = query |> String.trim() |> String.replace(~r/[%_\\]/, fn c -> "\\#{c}" end)
    pattern = "#{escaped}%"

    tags =
      from(t in Tag,
        where: ilike(t.name, ^pattern),
        order_by: [asc: t.name],
        limit: ^limit
      )
      |> Repo.all()

    {:ok, tags}
  end
end
