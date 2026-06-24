defmodule Kaguya.Tags.Tag do
  use Kaguya.Schema

  @tag_categories [content: 0, sexual: 1, technical: 2]
  @spoiler_levels [none: 0, minor: 1, major: 2]
  @kinds [
    genre: 0,
    theme: 1,
    cast: 2,
    gameplay: 3,
    format: 4,
    sexual: 5,
    meta: 6
  ]

  def kinds, do: Keyword.keys(@kinds)

  # Curated short labels for tags whose VNDB names are unwieldy.
  # Falls through to the tag's actual name.
  @display_aliases %{
    "boy-x-boy-romance-only" => "BL",
    "girl-x-girl-romance-only" => "Yuri",
    "otome-game" => "Otome",
    "science-fiction" => "Sci-Fi"
  }

  def display_name(%{slug: slug, name: name}), do: Map.get(@display_aliases, slug, name)

  schema "tags" do
    field :name, :string
    field :slug, :string
    field :description, :string
    field :source, :string

    # VNDB-specific fields
    field :vndb_tag_id, :string
    field :category, Ecto.Enum, values: @tag_categories
    field :default_spoiler_level, Ecto.Enum, values: @spoiler_levels, default: :none
    field :is_theme, :boolean, default: false
    field :kind, Ecto.Enum, values: @kinds
    field :content_warning, :boolean, default: false

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(tag, attrs) do
    tag
    |> cast(attrs, [
      :name,
      :slug,
      :description,
      :source,
      :vndb_tag_id,
      :category,
      :default_spoiler_level,
      :kind,
      :content_warning
    ])
    |> validate_required([:name, :slug])
    |> unique_constraint(:slug)
    |> unique_constraint(:name)
  end
end
