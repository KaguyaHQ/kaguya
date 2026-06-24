defmodule Kaguya.Recommendations.Feedback do
  @moduledoc """
  Per-user signal on a recommendation.

  Stored separately from `reading_statuses` because a rec signal is
  about *rec quality* ("this was a good/bad recommendation for me"), not
  a library action ("I have evaluated this VN and added it to my
  library"). The distinction matters — dismissing a rec shouldn't
  pollute the user's public library with an explicit "not interested"
  row.

  Two values:

    * `+1` — user clicked "+Wishlist" on the rec. The same frontend
      action also writes a `want_to_read` row in `reading_statuses`;
      this row exists in addition, as provenance ("user engaged
      positively with the rec system on this VN").
    * `-1` — user dismissed via "Not for me". No library side-effect.

  Both values contribute to the user's preference vector at training
  time (see `Kaguya.Recommendations.export_prefs_csv/2`) and mask the
  VN from future recs.
  """
  use Kaguya.Schema

  alias Kaguya.Users.User
  alias Kaguya.VisualNovels.VisualNovel

  @valid_signals [1, -1]

  @primary_key false
  @foreign_key_type :binary_id

  schema "user_recommendation_feedback" do
    belongs_to :user, User, primary_key: true
    belongs_to :visual_novel, VisualNovel, primary_key: true

    field :signal, :integer

    timestamps(type: :utc_datetime_usec)
  end

  def valid_signals, do: @valid_signals

  def changeset(feedback, attrs) do
    feedback
    |> cast(attrs, [:user_id, :visual_novel_id, :signal])
    |> validate_required([:user_id, :visual_novel_id, :signal])
    |> validate_inclusion(:signal, @valid_signals)
    |> assoc_constraint(:user)
    |> assoc_constraint(:visual_novel)
    |> unique_constraint([:user_id, :visual_novel_id],
      name: :user_vn_rec_feedback_pkey
    )
  end
end
