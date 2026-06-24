defmodule Kaguya.Stats.UserPeriodStat do
  use Kaguya.Schema

  alias Kaguya.Users.User

  alias Kaguya.Stats.{
    TagReadStat,
    TagRatingStat,
    ProducerReadStat,
    ProducerRatingStat
  }

  schema "user_period_stats" do
    belongs_to :user, User
    # nil == all-time
    field :period, :integer

    field :read_time_minutes, :integer, default: 0
    field :producers_count, :integer, default: 0

    # ---- HISTOGRAMS ----
    field :vns_hist, :map, default: %{}
    field :read_time_hist, :map, default: %{}
    field :mean_score_hist, :map, default: %{}
    field :vns_by_release_year_hist, :map, default: %{}
    field :read_time_by_release_year_hist, :map, default: %{}
    field :mean_score_by_release_year_hist, :map, default: %{}

    # Embed instead of raw maps so nested stats have stable atom keys.
    embeds_many :most_read_vn_tags, TagReadStat, on_replace: :delete
    embeds_many :highest_rated_vn_tags, TagRatingStat, on_replace: :delete

    embeds_many :most_read_producers, ProducerReadStat, on_replace: :delete
    embeds_many :highest_rated_producers, ProducerRatingStat, on_replace: :delete

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(stat, attrs) do
    stat
    |> cast(attrs, [
      :user_id,
      :period,
      :read_time_minutes,
      :producers_count,
      :vns_hist,
      :read_time_hist,
      :mean_score_hist,
      :vns_by_release_year_hist,
      :read_time_by_release_year_hist,
      :mean_score_by_release_year_hist
    ])
    |> cast_embed(:most_read_vn_tags)
    |> cast_embed(:highest_rated_vn_tags)
    |> cast_embed(:most_read_producers)
    |> cast_embed(:highest_rated_producers)
    |> validate_required([:user_id])
    |> unique_constraint([:user_id, :period])
    |> foreign_key_constraint(:user_id)
  end
end

alias Kaguya.Tags.Tag
alias Kaguya.Producers.Producer

defmodule Kaguya.Stats.TagReadStat do
  use Ecto.Schema
  import Ecto.Changeset
  @primary_key false

  embedded_schema do
    field :tag_id, :binary_id
    field :count, :integer
    belongs_to :tag, Tag, define_field: false, foreign_key: :tag_id
  end

  @doc false
  def changeset(stat, attrs) do
    stat
    |> cast(attrs, [:tag_id, :count])
    |> validate_required([:tag_id, :count])
  end
end

defmodule Kaguya.Stats.TagRatingStat do
  use Ecto.Schema
  import Ecto.Changeset
  @primary_key false

  embedded_schema do
    field :tag_id, :binary_id
    field :avg_user_rating, :float
    belongs_to :tag, Tag, define_field: false, foreign_key: :tag_id
  end

  @doc false
  def changeset(stat, attrs) do
    stat
    |> cast(attrs, [:tag_id, :avg_user_rating])
    |> validate_required([:tag_id, :avg_user_rating])
  end
end

defmodule Kaguya.Stats.ProducerReadStat do
  use Ecto.Schema
  import Ecto.Changeset
  @primary_key false

  embedded_schema do
    field :producer_id, :binary_id
    field :count, :integer
    belongs_to :producer, Producer, define_field: false, foreign_key: :producer_id
  end

  @doc false
  def changeset(stat, attrs) do
    stat
    |> cast(attrs, [:producer_id, :count])
    |> validate_required([:producer_id, :count])
  end
end

defmodule Kaguya.Stats.ProducerRatingStat do
  use Ecto.Schema
  import Ecto.Changeset
  @primary_key false

  embedded_schema do
    field :producer_id, :binary_id
    field :avg_user_rating, :float
    belongs_to :producer, Producer, define_field: false, foreign_key: :producer_id
  end

  @doc false
  def changeset(stat, attrs) do
    stat
    |> cast(attrs, [:producer_id, :avg_user_rating])
    |> validate_required([:producer_id, :avg_user_rating])
  end
end
