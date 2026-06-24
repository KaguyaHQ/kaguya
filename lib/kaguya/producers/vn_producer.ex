defmodule Kaguya.Producers.VNProducer do
  use Kaguya.Schema

  alias Kaguya.VisualNovels.VisualNovel
  alias Kaguya.Producers.Producer

  @primary_key false

  schema "vn_producers" do
    belongs_to :visual_novel, VisualNovel, primary_key: true
    belongs_to :producer, Producer, primary_key: true

    field :role, :string
    field :earliest_release_date, :date

    timestamps(type: :utc_datetime)
  end

  def changeset(vn_producer, attrs) do
    vn_producer
    |> cast(attrs, [:visual_novel_id, :producer_id, :role, :earliest_release_date])
    |> validate_required([:visual_novel_id, :producer_id])
    |> assoc_constraint(:visual_novel)
    |> assoc_constraint(:producer)
  end
end
