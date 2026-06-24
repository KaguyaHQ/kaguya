defmodule KaguyaWeb.Components.Activity.Verbs do
  @moduledoc """
  Inline verb-phrase function components for activity rows.

  Renders the sentence body that follows the actor link in any compact
  activity row: `<verb> <target>` for the simple cases, plus the seven
  specialty phrases (liked-review, commented-on-review, voted-tag,
  added/liked-quote, edited/reverted/created entity) that need richer
  composition than a single verb-and-target.

  Shared by `KaguyaWeb.Components.Profile.Activity` and
  `KaguyaWeb.Home.ActivityComponents`. The caller is responsible for
  rendering the actor link before the phrase, the date label after it,
  and any rating stars / preview lines around it.
  """

  use KaguyaWeb, :html

  alias KaguyaWeb.Components.Activity.Helpers

  # ---------------------------------------------------------------------------
  # Top-level dispatch
  # ---------------------------------------------------------------------------

  attr :item, :map, required: true
  attr :metadata, :map, required: true
  attr :verb, :map, required: true
  attr :target_href, :string, required: true

  attr :feed_username, :string,
    required: true,
    doc: "Used to detect when a :liked_review row is the actor liking their own review."

  attr :target_class, :string,
    default:
      "font-medium text-[rgb(var(--foreground-primary))] transition-colors hover:text-[rgb(var(--text-link-hover))]"

  attr :star_icon_class, :string,
    default: nil,
    doc:
      "Extra class for inline `DisplayRatings` stars (e.g. `text-icons-star-muted` " <>
        "in the home rail). Profile leaves this nil for the default star color."

  def verb_phrase(assigns) do
    action = assigns.item.action
    metadata = assigns.metadata

    cond do
      action == :liked_review ->
        liked_review_phrase(assigns)

      action == :commented and metadata["parent_entity_type"] == "post" ->
        ~H"""
        commented on
        <.target_link
          href={@target_href}
          text={@metadata["post_title"] || "a discussion"}
          class={@target_class}
        />
        """

      action == :commented and metadata["parent_entity_type"] == "list" ->
        ~H"""
        commented on
        <.target_link href={@target_href} text={@metadata["list_name"] || "a list"} class={@target_class} />
        """

      action == :commented and Helpers.review_comment_metadata?(metadata) ->
        commented_review_phrase(assigns)

      action == :commented ->
        generic_verb(assigns)

      action == :recommended_similar ->
        recommended_similar_phrase(assigns)

      action in [
        :voted_tag,
        :added_quote,
        :liked_quote,
        :edited_entity,
        :reverted_entity,
        :created_entity
      ] ->
        inline_verb(assigns)

      true ->
        generic_verb(assigns)
    end
  end

  # ---------------------------------------------------------------------------
  # :recommended_similar — "recommended <similar-link> on <source-link>"
  #
  # Both the similar VN and the source VN are clickable. The
  # profile feed's `recommended_similar_item/1` adds paired cover thumbs
  # below this sentence; the home rail keeps just the sentence.
  # ---------------------------------------------------------------------------

  defp recommended_similar_phrase(assigns) do
    metadata = assigns.metadata
    similar_href = Helpers.slug_href(metadata["similar_vn_slug"])
    source_href = Helpers.slug_href(metadata["source_vn_slug"])

    assigns =
      assigns
      |> assign(:similar_href, similar_href)
      |> assign(:source_href, source_href)
      |> assign(:similar_title, metadata["similar_vn_title"] || "a visual novel")
      |> assign(:source_title, metadata["source_vn_title"] || "a visual novel")

    ~H"""
    recommended <.target_link href={@similar_href} text={@similar_title} class={@target_class} /> on
    <.target_link href={@source_href} text={@source_title} class={@target_class} />
    """
  end

  # ---------------------------------------------------------------------------
  # Generic "verb + target" phrase (`%{text:, target:, suffix?}`)
  # ---------------------------------------------------------------------------

  defp generic_verb(assigns) do
    suffix = Map.get(assigns.verb, :suffix)
    assigns = assign(assigns, :suffix, suffix)

    ~H"""
    {@verb.text}
    <.target_link href={@target_href} text={@verb.target} class={@target_class} />
    <span :if={@suffix}>{" " <> @suffix}</span>
    """
  end

  # ---------------------------------------------------------------------------
  # :liked_review — "liked <user>'s ★★★★ review of <vn>"
  # ---------------------------------------------------------------------------

  defp liked_review_phrase(assigns) do
    review = Helpers.loaded(assigns.item.review)
    review_user = review && Helpers.loaded(review.user)
    review_vn = review && Helpers.loaded(review.visual_novel)
    metadata = assigns.metadata
    reviewer_username = (review_user && review_user.username) || metadata["review_username"]

    reviewer_display =
      (review_user && (review_user.display_name || review_user.username)) ||
        metadata["review_display_name"] || reviewer_username

    review_rating = (review && review.rating) || metadata["review_rating"]

    vn_slug = (review_vn && review_vn.slug) || metadata["vn_slug"]
    vn_title = (review_vn && review_vn.title) || metadata["vn_title"] || "a visual novel"
    is_own = reviewer_username == assigns.feed_username

    review_href =
      Helpers.review_url(reviewer_username, vn_slug) || (vn_slug && "/vn/#{vn_slug}") || "#"

    assigns =
      assigns
      |> assign(:reviewer_username, reviewer_username)
      |> assign(:reviewer_display, reviewer_display)
      |> assign(:review_rating, review_rating)
      |> assign(:vn_title, vn_title)
      |> assign(:is_own, is_own)
      |> assign(:review_href, review_href)

    ~H"""
    liked
    <%= cond do %>
      <% @is_own -> %>
        their own
      <% is_binary(@reviewer_username) -> %>
        <.target_link
          href={"/@" <> @reviewer_username}
          text={(@reviewer_display || @reviewer_username) <> "'s"}
          class={@target_class}
        />
      <% true -> %>
    <% end %>
    <KaguyaWeb.VN.Icons.display_ratings
      :if={is_number(@review_rating) and @review_rating > 0}
      rating={@review_rating}
      class="inline-flex align-[-2px]"
      star_class="size-3"
      icon_class={@star_icon_class}
      half_rating_class={@star_icon_class}
    /> review of <.target_link href={@review_href} text={@vn_title} class={@target_class} />
    """
  end

  # ---------------------------------------------------------------------------
  # :commented on a review — "commented on <user>'s ★★★★ review of <vn>"
  # ---------------------------------------------------------------------------

  defp commented_review_phrase(assigns) do
    review = Helpers.loaded(assigns.item.review)
    review_user = review && Helpers.loaded(review.user)
    review_vn = review && Helpers.loaded(review.visual_novel)
    metadata = assigns.metadata
    reviewer_username = (review_user && review_user.username) || metadata["review_username"]

    reviewer_display =
      (review_user && (review_user.display_name || review_user.username)) ||
        metadata["review_display_name"] || reviewer_username

    vn_slug = (review_vn && review_vn.slug) || metadata["vn_slug"]
    vn_title = (review_vn && review_vn.title) || metadata["vn_title"] || "a visual novel"
    is_own = reviewer_username == assigns.feed_username

    review_href =
      Helpers.review_url(reviewer_username, vn_slug) || (vn_slug && "/vn/#{vn_slug}") || "#"

    assigns =
      assigns
      |> assign(:reviewer_username, reviewer_username)
      |> assign(:reviewer_display, reviewer_display)
      |> assign(:vn_title, vn_title)
      |> assign(:is_own, is_own)
      |> assign(:review_href, review_href)

    ~H"""
    commented on
    <%= cond do %>
      <% @is_own -> %>
        their own
      <% is_binary(@reviewer_username) -> %>
        <.target_link
          href={"/@" <> @reviewer_username}
          text={(@reviewer_display || @reviewer_username) <> "'s"}
          class={@target_class}
        />
      <% true -> %>
    <% end %>
    review of <.target_link href={@review_href} text={@vn_title} class={@target_class} />
    """
  end

  # ---------------------------------------------------------------------------
  # Phase 1/2/3 verbs — inline-composed with extra link targets.
  # ---------------------------------------------------------------------------

  defp inline_verb(assigns) do
    action = assigns.item.action
    metadata = assigns.metadata
    entity_ref = assigns.item.entity_ref

    entity_name =
      (entity_ref && entity_ref[:name]) ||
        Helpers.entity_type_noun(entity_ref && entity_ref[:entity_type])

    entity_slug = entity_ref && entity_ref[:slug]

    assigns =
      assigns
      |> assign(:entity_name, entity_name)
      |> assign(:entity_slug, entity_slug)

    case action do
      :voted_tag ->
        tag_name = metadata["tag_name"] || "a tag"
        phrase = Helpers.tag_vote_phrase(metadata["value"])
        vn_href = if entity_slug, do: "/vn/#{entity_slug}", else: "#"
        tag_href = if entity_slug, do: "/vn/#{entity_slug}#tags", else: "#"

        assigns =
          assigns
          |> assign(:tag_name, tag_name)
          |> assign(:phrase, phrase)
          |> assign(:vn_href, vn_href)
          |> assign(:tag_href, tag_href)

        ~H"""
        voted <.target_link href={@tag_href} text={@tag_name} class={@target_class} />
        {@phrase}
        <.target_link href={@vn_href} text={@entity_name} class={@target_class} />
        """

      a when a in [:added_quote, :liked_quote] ->
        verb_word = if action == :added_quote, do: "added", else: "liked"
        quotes_href = if entity_slug, do: "/vn/#{entity_slug}/quotes", else: "#"

        assigns =
          assigns
          |> assign(:verb_word, verb_word)
          |> assign(:quotes_href, quotes_href)

        ~H"""
        {@verb_word} a quote from
        <.target_link href={@quotes_href} text={@entity_name} class={@target_class} />
        """

      a when a in [:edited_entity, :reverted_entity] ->
        verb_word = if action == :edited_entity, do: "edited", else: "reverted"
        href = Helpers.revision_diff_path(entity_ref, metadata["revision_id"])

        reverted_from =
          if action == :reverted_entity, do: metadata["reverted_from_revision"], else: nil

        assigns =
          assigns
          |> assign(:verb_word, verb_word)
          |> assign(:href, href)
          |> assign(:reverted_from, reverted_from)

        ~H"""
        {@verb_word}
        <.target_link href={@href} text={@entity_name} class={@target_class} />
        <span :if={is_integer(@reverted_from)}>to revision #{@reverted_from}</span>
        """

      :created_entity ->
        href = Helpers.entity_path(entity_ref)
        assigns = assign(assigns, :href, href)

        ~H"""
        added <.target_link href={@href} text={@entity_name} class={@target_class} /> to the database
        """
    end
  end

  # ---------------------------------------------------------------------------
  # target_link — bold, primary-foreground link to the row's target.
  # ---------------------------------------------------------------------------

  @target_link_class "font-medium text-[rgb(var(--foreground-primary))] transition-colors hover:text-[rgb(var(--text-link-hover))]"

  @doc "Default class for `target_link/1`. Exposed so callers can compose it."
  def default_target_class, do: @target_link_class

  attr :href, :string, required: true
  attr :text, :string, required: true
  attr :class, :string, default: @target_link_class

  def target_link(assigns) do
    ~H"""
    <.link navigate={@href} class={@class}>{@text}</.link>
    """
  end
end
