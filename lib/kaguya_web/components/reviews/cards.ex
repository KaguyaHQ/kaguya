defmodule KaguyaWeb.Components.Reviews.Cards do
  @moduledoc """
  Function components for "review row" atoms shared across surfaces that
  list a user's reviews (profile reviews tab, profile overview tab,
  single-review more-from-author grid).

  The two visible variants are:

    * `user_review_card/1` — `hideUser` variant: VN cover on the left,
      VN title + rating + review preview on the right. Used on the
      `/@:username/reviews` tab.

  The card is intentionally stateless. Callers wire `phx-click="toggle_like"`
  events (and friends) on the live view that hosts the list so optimistic
  state lives in one place. The card receives the normalized review map
  produced by `KaguyaWeb.ProfileLive.Reviews.Data` (or any equivalent) —
  it never touches Ecto schemas.

  ## Expected review map

      %{
        id: "uuid",
        rating: 4.5,
        likes_count: 12,
        comments_count: 3,
        liked_by_me: false,
        is_spoiler: false,
        inserted_at: ~U[...],
        content: "<p>review html…</p>",
        user: %{username: "alice", display_name: "Alice"},
        visual_novel: %{
          slug: "ever17",
          title: "Ever17",
          images: %{small: ..., medium: ..., large: ..., xl: ...}
        }
      }
  """

  use KaguyaWeb, :html

  alias KaguyaWeb.Components.VN.Cards, as: VNCards

  # ---------------------------------------------------------------------------
  # Profile reviews tab — `hideUser` variant
  # ---------------------------------------------------------------------------

  attr :review, :map, required: true
  attr :class, :any, default: nil

  @doc """
  Renders a single review row for the user's reviews tab.

  Mirrors `VnReviewCard` with `hideUser` and `fullWidth alignLeft`:
    * VN cover on the left.
    * VN title (links to `/vn/:slug`) and date in the header.
    * Optional rating row.
    * Review content preview (5-line clamp, spoiler-gated).
    * Like + comments action row at the bottom.
  """
  def user_review_card(assigns) do
    ~H"""
    <VNCards.vn_review_card
      review={@review}
      class={@class}
      full_width
      align_left
      hide_user
      like_event="toggle_review_like"
    />
    """
  end
end
