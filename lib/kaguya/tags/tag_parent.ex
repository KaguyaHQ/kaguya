defmodule Kaguya.Tags.TagParent do
  @moduledoc """
  Parent-child relationships between tags, mirroring VNDB's tag hierarchy.
  """
  use Ecto.Schema

  alias Kaguya.Tags.Tag

  @primary_key false
  @foreign_key_type :binary_id
  schema "tag_parents" do
    belongs_to :tag, Tag
    belongs_to :parent_tag, Tag
    field :is_main, :boolean, default: false
  end
end
