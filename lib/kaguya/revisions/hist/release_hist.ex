defmodule Kaguya.Revisions.Hist.ReleaseHist do
  use Ecto.Schema

  @primary_key false

  schema "releases_hist" do
    belongs_to :change, Kaguya.Revisions.Change, type: :binary_id, primary_key: true
    field :title, :string
    field :display_title, :string
    field :latin_title, :string
    field :original_language, :string
    field :release_date, :date
    field :release_type, :string
    field :patch, :boolean, default: false
    field :freeware, :boolean, default: false
    field :official, :boolean, default: true
    field :has_ero, :boolean, default: false
    field :uncensored, :boolean
    field :voiced, :integer
    field :minage, :integer
    field :engine, :string
    field :platforms, {:array, :string}, default: []
    field :languages, {:array, :string}, default: []
    field :mtl_languages, {:array, :string}, default: []
    field :producers, {:array, :map}, default: []
    field :notes, :string
    field :reso_x, :integer
    field :reso_y, :integer
    field :media, {:array, :map}, default: []
    field :hidden_at, :utc_datetime
    field :is_locked, :boolean, default: false
  end
end
