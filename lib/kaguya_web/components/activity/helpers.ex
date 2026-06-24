defmodule KaguyaWeb.Components.Activity.Helpers do
  @moduledoc """
  Pure verb / href / date helpers for activity rows.

  Shared by the per-profile activity tab (`KaguyaWeb.Components.Profile.Activity`)
  and the signed-in home rail (`KaguyaWeb.Home.ActivityComponents`).

  All callers must hand in *normalized* activity rows — string-keyed
  `metadata` (as stored in the JSON column), atom-keyed `entity_ref`
  (as built by `Kaguya.Activities.build_*_ref/3`), and `followed_user` /
  `followed_producer` association maps.
  """

  # ---------------------------------------------------------------------------
  # Metadata
  # ---------------------------------------------------------------------------

  def normalize_metadata(nil), do: %{}
  def normalize_metadata(%{} = meta), do: meta

  def present?(value) when is_binary(value), do: String.trim(value) != ""
  def present?(_), do: false

  # Unwrap an Ecto association so unloaded ones short-circuit to `nil`
  # instead of crashing template field accesses.
  def loaded(%Ecto.Association.NotLoaded{}), do: nil
  def loaded(other), do: other

  # ---------------------------------------------------------------------------
  # Entity ref helpers
  # ---------------------------------------------------------------------------

  def entity_type_noun("visual_novel"), do: "a visual novel"
  def entity_type_noun("character"), do: "a character"
  def entity_type_noun("producer"), do: "a producer"
  def entity_type_noun("release"), do: "a release"
  def entity_type_noun(_), do: "an entry"

  def entity_path(nil), do: "#"

  def entity_path(%{entity_type: "visual_novel", slug: slug}) when is_binary(slug),
    do: "/vn/#{slug}"

  def entity_path(%{entity_type: "character", slug: slug}) when is_binary(slug),
    do: "/character/#{slug}"

  def entity_path(%{entity_type: "producer", slug: slug}) when is_binary(slug),
    do: "/developer/#{slug}"

  def entity_path(%{entity_type: "release", parent_vn_slug: parent_slug, entity_id: id})
      when is_binary(parent_slug) and is_binary(id),
      do: "/vn/#{parent_slug}#release-#{id}"

  def entity_path(_), do: "#"

  def entity_ref_slug_href(%{slug: slug}) when is_binary(slug) and slug != "",
    do: "/vn/#{slug}"

  def entity_ref_slug_href(_), do: "#"

  def revision_diff_path(_entity_ref, nil), do: "#"

  def revision_diff_path(entity_ref, revision_id) do
    case entity_history_path(entity_ref) do
      nil -> "#"
      root -> "#{root}/#{revision_id}"
    end
  end

  defp entity_history_path(nil), do: nil

  defp entity_history_path(%{entity_type: "visual_novel", slug: slug}) when is_binary(slug),
    do: "/vn/#{slug}/history"

  defp entity_history_path(%{entity_type: "character", slug: slug}) when is_binary(slug),
    do: "/character/#{slug}/history"

  defp entity_history_path(%{entity_type: "producer", slug: slug}) when is_binary(slug),
    do: "/developer/#{slug}/history"

  defp entity_history_path(%{entity_type: "release", parent_vn_slug: parent_slug, entity_id: id})
       when is_binary(parent_slug) and is_binary(id),
       do: "/vn/#{parent_slug}/release/#{id}/history"

  defp entity_history_path(_), do: nil

  # A tag vote is a *graded relevance* vote (0..5, see `Kaguya.VNTags.VNTagVote`),
  # not a categorical "this VN is X" claim — so the verb reads "voted <Tag> a
  # minor element of <VN>". The phrase is a connective ending in "of"/"to" that
  # always carries the grade, so a small vote never overstates. Mirrors the
  # tag-panel vote buckets; 0 is the "not relevant" downvote. Single source of
  # truth for tag-vote activity phrasing across all three feed renderers.
  def tag_vote_phrase(5), do: "the main theme of"
  def tag_vote_phrase(4), do: "a major element of"
  def tag_vote_phrase(3), do: "a moderate element of"
  def tag_vote_phrase(2), do: "a minor element of"
  def tag_vote_phrase(1), do: "a small element of"
  def tag_vote_phrase(0), do: "not relevant to"

  def tag_vote_phrase(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> tag_vote_phrase(int)
      _ -> "relevant to"
    end
  end

  def tag_vote_phrase(_), do: "relevant to"

  # ---------------------------------------------------------------------------
  # Href helpers
  # ---------------------------------------------------------------------------

  def vn_href(%{"vn_slug" => slug}) when is_binary(slug) and slug != "", do: "/vn/#{slug}"
  def vn_href(_), do: "#"

  def slug_href(slug) when is_binary(slug) and slug != "", do: "/vn/#{slug}"
  def slug_href(_), do: "#"

  def review_url(username, slug)
      when is_binary(username) and username != "" and is_binary(slug) and slug != "" do
    "/@#{username}/reviews/#{slug}"
  end

  def review_url(_, _), do: nil

  def list_href(username, slug)
      when is_binary(username) and username != "" and is_binary(slug) and slug != "" do
    "/@#{username}/list/#{slug}"
  end

  def list_href(_, _), do: "#"

  def followed_href(metadata, followed_user, followed_producer) do
    producer_slug =
      (followed_producer && followed_producer.slug) || metadata["followed_producer_slug"]

    if is_binary(producer_slug) and producer_slug != "" do
      "/developer/#{producer_slug}"
    else
      username = (followed_user && followed_user.username) || metadata["followed_username"]
      if is_binary(username) and username != "", do: "/@#{username}", else: "#"
    end
  end

  def commented_href(metadata) do
    case metadata["parent_entity_type"] do
      "post" ->
        post_comment_href(metadata)

      "list" ->
        list_href(metadata["list_username"], metadata["list_slug"]) <> "#comments"

      "review" ->
        review_comment_href(metadata)

      _ ->
        if review_comment_metadata?(metadata), do: review_comment_href(metadata), else: "#"
    end
  end

  @doc """
  Returns the navigate href for a row's bold target text.

  `feed_username` is the username for the actor whose feed/profile we're on;
  used as a fallback for `:imported_vndb` and `:created_list` when metadata
  doesn't carry the creator's username.
  """
  def target_href(action, metadata, feed_username, followed_user, followed_producer, entity_ref) do
    case action do
      :voted_tag ->
        entity_ref_slug_href(entity_ref)

      a when a in [:added_quote, :liked_quote] ->
        entity_ref_slug_href(entity_ref)

      a when a in [:edited_entity, :reverted_entity] ->
        revision_diff_path(entity_ref, metadata["revision_id"])

      :created_entity ->
        entity_path(entity_ref)

      a when a in [:rated, :status_changed, :reviewed, :liked_review] ->
        review_url(metadata["review_username"], metadata["vn_slug"]) ||
          vn_href(metadata)

      :liked_screenshot ->
        vn_tab_href(metadata, "screenshots")

      :liked_list ->
        list_href(metadata["list_username"], metadata["list_slug"])

      :created_list ->
        list_href(metadata["list_username"] || feed_username, metadata["list_slug"])

      :followed ->
        followed_href(metadata, followed_user, followed_producer)

      :commented ->
        commented_href(metadata)

      :recommended_similar ->
        slug_href(metadata["source_vn_slug"])

      :imported_vndb ->
        "/@#{feed_username}/library"

      :liked_cover ->
        vn_tab_href(metadata, "covers")

      _ ->
        "#"
    end
  end

  def vn_tab_href(%{"vn_slug" => slug}, tab)
      when is_binary(slug) and slug != "" and is_binary(tab),
      do: "/vn/#{slug}/#{tab}"

  def vn_tab_href(_, _), do: "#"

  # ---------------------------------------------------------------------------
  # Verb resolution.
  # Returns %{text: "...", target: "...", suffix: "..."} (suffix optional).
  # ---------------------------------------------------------------------------

  def activity_verb(action, metadata, followed_user, followed_producer, entity_ref) do
    case action do
      :rated ->
        %{text: "rated", target: metadata["vn_title"] || "a visual novel"}

      :status_changed ->
        status_verb(metadata)

      :liked_list ->
        %{text: "liked", target: metadata["list_name"] || "a list"}

      :liked_screenshot ->
        %{text: "liked a screenshot from", target: metadata["vn_title"] || "a visual novel"}

      :created_list ->
        %{text: "created", target: metadata["list_name"] || "a list"}

      :reviewed ->
        %{text: "reviewed", target: metadata["vn_title"] || "a visual novel"}

      :liked_review ->
        %{text: "liked a review of", target: metadata["vn_title"] || "a visual novel"}

      :created_post ->
        %{text: "posted", target: metadata["post_title"] || "a post"}

      :commented ->
        commented_verb(metadata)

      :followed ->
        followed_verb(metadata, followed_user, followed_producer)

      :recommended_similar ->
        %{
          text: "recommended",
          target: metadata["similar_vn_title"] || "a visual novel",
          suffix: "on " <> (metadata["source_vn_title"] || "a visual novel")
        }

      :imported_vndb ->
        %{text: "imported", target: "their library", suffix: "from VNDB"}

      :liked_cover ->
        %{text: "liked a cover from", target: metadata["vn_title"] || "a visual novel"}

      :voted_tag ->
        tag_name = metadata["tag_name"] || "a tag"
        vn_title = (entity_ref && entity_ref[:name]) || "a visual novel"

        %{
          text: "voted",
          target: tag_name,
          suffix: tag_vote_phrase(metadata["value"]) <> " " <> vn_title
        }

      :added_quote ->
        %{
          text: "added a quote from",
          target: (entity_ref && entity_ref[:name]) || "a visual novel"
        }

      :liked_quote ->
        %{
          text: "liked a quote from",
          target: (entity_ref && entity_ref[:name]) || "a visual novel"
        }

      :edited_entity ->
        %{
          text: "edited",
          target:
            (entity_ref && entity_ref[:name]) ||
              entity_type_noun(entity_ref && entity_ref[:entity_type])
        }

      :reverted_entity ->
        target =
          (entity_ref && entity_ref[:name]) ||
            entity_type_noun(entity_ref && entity_ref[:entity_type])

        rev = metadata["reverted_from_revision"]

        if is_integer(rev),
          do: %{text: "reverted", target: target, suffix: "to revision ##{rev}"},
          else: %{text: "reverted", target: target}

      :created_entity ->
        %{
          text: "added",
          target:
            (entity_ref && entity_ref[:name]) ||
              entity_type_noun(entity_ref && entity_ref[:entity_type]),
          suffix: "to the database"
        }

      _ ->
        %{text: "did something", target: ""}
    end
  end

  def status_verb(metadata) do
    vn_title = metadata["vn_title"] || "a visual novel"

    case String.downcase(metadata["status"] || "") do
      "read" -> %{text: "read", target: vn_title}
      "currently_reading" -> %{text: "started reading", target: vn_title}
      "want_to_read" -> %{text: "wishlisted", target: vn_title}
      "on_hold" -> %{text: "put", target: vn_title, suffix: "on hold"}
      "did_not_finish" -> %{text: "did not finish", target: vn_title}
      "not_interested" -> %{text: "is not interested in", target: vn_title}
      _ -> %{text: "updated status of", target: vn_title}
    end
  end

  def commented_verb(metadata) do
    case metadata["parent_entity_type"] do
      "post" ->
        %{text: "commented on", target: metadata["post_title"] || "a discussion"}

      "list" ->
        %{text: "commented on", target: metadata["list_name"] || "a list"}

      "review" ->
        %{text: "commented on a review of", target: metadata["vn_title"] || "a visual novel"}

      _ ->
        if(review_comment_metadata?(metadata),
          do: review_comment_verb(metadata),
          else: %{text: "commented on", target: "something"}
        )
    end
  end

  def review_comment_metadata?(metadata) do
    metadata["parent_entity_type"] == "review" or
      present?(metadata["vn_review_path"]) or
      (present?(metadata["review_username"]) and present?(metadata["vn_slug"]))
  end

  defp post_comment_href(metadata) do
    short_id = metadata["post_short_id"]

    if present?(short_id) do
      slug = metadata["post_slug"] || "post"
      base = "/discussions/p/#{short_id}/#{slug}"

      case metadata["comment_short_id"] do
        comment_short_id when is_binary(comment_short_id) and comment_short_id != "" ->
          base <> "/c/" <> comment_short_id

        _ ->
          base
      end
    else
      "#"
    end
  end

  defp review_comment_href(metadata) do
    if present?(metadata["vn_review_path"]) do
      metadata["vn_review_path"] <> "#comments"
    else
      case review_url(metadata["review_username"], metadata["vn_slug"]) do
        nil -> "#"
        url -> url <> "#comments"
      end
    end
  end

  defp review_comment_verb(metadata),
    do: %{text: "commented on a review of", target: metadata["vn_title"] || "a visual novel"}

  def followed_verb(metadata, _followed_user, followed_producer) do
    producer_name =
      (followed_producer && followed_producer.name) || metadata["followed_producer_name"]

    if is_binary(producer_name) and producer_name != "" do
      %{text: "followed", target: producer_name}
    else
      target =
        metadata["followed_display_name"] ||
          metadata["followed_username"] ||
          "a user"

      %{text: "followed", target: target}
    end
  end

  # ---------------------------------------------------------------------------
  # Status → shelf URL slug (mirrors `shelfToUrl` for grouped status_changed).
  # ---------------------------------------------------------------------------

  def status_shelf_slug("read"), do: "read"
  def status_shelf_slug("currently_reading"), do: "reading"
  def status_shelf_slug("want_to_read"), do: "want-to-read"
  def status_shelf_slug("on_hold"), do: "on-hold"
  def status_shelf_slug("did_not_finish"), do: "did-not-finish"
  def status_shelf_slug("not_interested"), do: "not-interested"
  def status_shelf_slug(_), do: nil

  def iso_string(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  def iso_string(%NaiveDateTime{} = ndt), do: NaiveDateTime.to_iso8601(ndt)
  def iso_string(value) when is_binary(value), do: value
  def iso_string(_), do: ""
end
