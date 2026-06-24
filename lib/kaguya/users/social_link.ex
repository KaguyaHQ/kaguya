defmodule Kaguya.Users.SocialLinks do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :twitter, :string
    field :tiktok, :string
    field :instagram, :string
    field :website, :string
  end

  @doc false
  def changeset(social_links, attrs) do
    social_links
    |> cast(attrs, [:twitter, :tiktok, :instagram, :website])
    # Example validations:
    |> validate_format(:website, ~r/^https?:\/\/[\S]+$/, message: "must be a valid URL")
    |> validate_length(:twitter, max: 20)
    |> validate_length(:tiktok, max: 25)
    |> validate_length(:instagram, max: 30)
    |> validate_length(:website, max: 255)
  end
end
