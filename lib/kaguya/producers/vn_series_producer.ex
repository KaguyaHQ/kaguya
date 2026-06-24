defmodule Kaguya.Producers.VNSeriesProducer do
  use Kaguya.Schema

  alias Kaguya.Producers.Producer
  alias Kaguya.VisualNovels.Series

  @primary_key false

  schema "vn_series_producers" do
    belongs_to :vn_series, Series, primary_key: true
    belongs_to :producer, Producer, primary_key: true

    field :role, :string

    timestamps(type: :utc_datetime)
  end

  def changeset(series_producer, attrs) do
    series_producer
    |> cast(attrs, [:vn_series_id, :producer_id, :role])
    |> validate_required([:vn_series_id, :producer_id, :role])
    |> assoc_constraint(:vn_series)
    |> assoc_constraint(:producer)
  end
end
