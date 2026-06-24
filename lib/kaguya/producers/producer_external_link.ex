defmodule Kaguya.Producers.ProducerExternalLink do
  use Kaguya.Schema

  alias Kaguya.Producers.Producer

  @primary_key false
  schema "producer_external_links" do
    field :site, :string
    field :value, :string

    belongs_to :producer, Producer

    timestamps(type: :utc_datetime)
  end

  def changeset(external_link, attrs) do
    external_link
    |> cast(attrs, [:site, :value, :producer_id])
    |> validate_required([:site, :value, :producer_id])
    |> validate_length(:site, max: 50)
    |> validate_length(:value, max: 1000)
    |> assoc_constraint(:producer)
  end
end
