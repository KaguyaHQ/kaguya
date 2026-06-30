defmodule Kaguya.PublicDump.Tables do
  @moduledoc """
  Single source of truth for what's included in the public DB dump.

  Mirror of VNDB's `%tables` map in `util/dbdump.pl`. Each entry is a
  `Kaguya.PublicDump.Spec`. The pipeline reads this list, applies the
  WHERE / ORDER BY / column transforms uniformly, and writes one TSV file
  per table.

  ## Timestamp policy (matching VNDB)

    * **Entity tables** and **catalog junctions** drop timestamps. Per-entity
      created/last-modified comes from `entry_meta`.
    * **Per-user signal tables** (votes, likes, ratings, favorites, reading
      statuses) keep `{:inserted_at, :date}` (and `:updated_at` where the
      table tracks edits). The date *is* the signal — when did this user
      vote / like / favorite. Mirrors VNDB's `tags_vn.date`,
      `image_votes.date`, etc.

  ## Adding a new table

  Append a `defp` returning a `%Spec{}`, register it in `all/0`. The
  pipeline picks up the columns, WHERE, primary key, and foreign keys
  automatically. If the new table has a `user_id` column that should count
  toward "user has a public contribution", also extend `users/0`'s WHERE.
  """

  alias Kaguya.PublicDump.Spec

  @doc "Ordered list of table specs included in the dump."
  def all do
    [
      # ── VN core ──
      visual_novels(),
      vn_titles(),
      vn_images(),
      vn_external_links(),
      vn_relations(),
      vn_releases(),
      vn_release_extlinks(),
      vn_screenshots(),
      vn_quotes(),
      vn_engines(),
      vn_series(),
      vn_series_items(),

      # ── Producers ──
      producers(),
      producer_images(),
      producer_external_links(),
      vn_producers(),

      # ── Tags ──
      tags(),
      tag_parents(),
      vn_tags(),
      vn_tag_votes(),

      # ── Characters ──
      characters(),
      character_images(),
      vn_characters(),
      character_favorites(),

      # ── Engagement (likes + follows) ──
      vn_image_likes(),
      vn_screenshot_likes(),
      vn_quote_likes(),
      producer_follows(),

      # ── User-VN tracking ──
      vn_ratings(),
      vn_reading_statuses(),

      # ── Community similarities ──
      vn_similarities(),
      vn_similarity_votes(),

      # ── Synthesized + filtered ──
      entry_meta(),
      users()
    ]
  end

  # ── VN core ────────────────────────────────────────────────────────────────

  defp visual_novels do
    %Spec{
      name: :visual_novels,
      primary_key: "id",
      columns: [
        :id,
        :title,
        :description,
        :slug,
        :vndb_id,
        :development_status,
        :length_category,
        :length_minutes,
        :original_language,
        :release_date,
        :min_age,
        :has_ero,
        :is_avn,
        :is_image_nsfw,
        :is_image_suggestive,
        :title_category,
        :average_rating,
        :ratings_count,
        :ratings_dist,
        :reviews_count,
        :vndb_rating,
        :vndb_vote_count,
        :aliases,
        :primary_image_id,
        :featured_screenshot_id,
        :primary_vn_series_id,
        :primary_series_position
      ],
      where: "hidden_at IS NULL",
      foreign_keys: [
        {:primary_image_id, :vn_images, :id},
        {:featured_screenshot_id, :vn_screenshots, :id},
        {:primary_vn_series_id, :vn_series, :id}
      ]
    }
  end

  defp vn_titles do
    %Spec{
      name: :vn_titles,
      primary_key: "id",
      columns: [:id, :visual_novel_id, :lang, :official, :title, :latin],
      where: "visual_novel_id IN (SELECT id FROM visual_novels WHERE hidden_at IS NULL)",
      foreign_keys: [{:visual_novel_id, :visual_novels, :id}]
    }
  end

  defp vn_images do
    %Spec{
      name: :vn_images,
      primary_key: "id",
      columns: [
        :id,
        :visual_novel_id,
        :vndb_cv_id,
        :width,
        :height,
        :language,
        :release_date,
        :is_image_nsfw,
        :is_image_suggestive,
        :vndb_votes,
        {:uploaded_by, :user_fk}
      ],
      where: "visual_novel_id IN (SELECT id FROM visual_novels WHERE hidden_at IS NULL)",
      foreign_keys: [
        {:visual_novel_id, :visual_novels, :id},
        {:uploaded_by, :users, :id}
      ]
    }
  end

  defp vn_external_links do
    %Spec{
      name: :vn_external_links,
      primary_key: "vn_id, site, value",
      columns: [:vn_id, :site, :value],
      where: "vn_id IN (SELECT id FROM visual_novels WHERE hidden_at IS NULL)",
      foreign_keys: [{:vn_id, :visual_novels, :id}]
    }
  end

  defp vn_relations do
    %Spec{
      name: :vn_relations,
      primary_key: "visual_novel_id, related_vn_id",
      columns: [:visual_novel_id, :related_vn_id, :relation_type, :is_official],
      where: """
      visual_novel_id IN (SELECT id FROM visual_novels WHERE hidden_at IS NULL)
      AND related_vn_id IN (SELECT id FROM visual_novels WHERE hidden_at IS NULL)\
      """,
      foreign_keys: [
        {:visual_novel_id, :visual_novels, :id},
        {:related_vn_id, :visual_novels, :id}
      ]
    }
  end

  defp vn_releases do
    %Spec{
      name: :vn_releases,
      primary_key: "id",
      columns: [
        :id,
        :visual_novel_id,
        :vndb_id,
        :title,
        :display_title,
        :latin_title,
        :original_language,
        :release_date,
        :release_type,
        :patch,
        :freeware,
        :official,
        :has_ero,
        :uncensored,
        :voiced,
        :minage,
        :engine,
        :platforms,
        :languages,
        :mtl_languages,
        :producers,
        :media,
        :notes,
        :reso_x,
        :reso_y
      ],
      where: """
      hidden_at IS NULL
      AND visual_novel_id IN (SELECT id FROM visual_novels WHERE hidden_at IS NULL)\
      """,
      foreign_keys: [{:visual_novel_id, :visual_novels, :id}]
    }
  end

  defp vn_release_extlinks do
    %Spec{
      name: :vn_release_extlinks,
      primary_key: "id",
      columns: [:id, :vn_release_id, :site, :label, :url],
      where: "vn_release_id IN (SELECT id FROM vn_releases WHERE hidden_at IS NULL)",
      foreign_keys: [{:vn_release_id, :vn_releases, :id}]
    }
  end

  defp vn_screenshots do
    %Spec{
      name: :vn_screenshots,
      primary_key: "id",
      columns: [
        :id,
        :visual_novel_id,
        :release_id,
        :vndb_sf_id,
        :width,
        :height,
        :is_nsfw,
        :is_brutal,
        {:uploaded_by, :user_fk}
      ],
      where: "visual_novel_id IN (SELECT id FROM visual_novels WHERE hidden_at IS NULL)",
      foreign_keys: [
        {:visual_novel_id, :visual_novels, :id},
        {:release_id, :vn_releases, :id},
        {:uploaded_by, :users, :id}
      ]
    }
  end

  defp vn_quotes do
    %Spec{
      name: :vn_quotes,
      primary_key: "id",
      columns: [
        :id,
        :visual_novel_id,
        :character_id,
        :quote,
        :score,
        :vndb_id,
        {:created_by, :user_fk}
      ],
      where: "visual_novel_id IN (SELECT id FROM visual_novels WHERE hidden_at IS NULL)",
      foreign_keys: [
        {:visual_novel_id, :visual_novels, :id},
        {:character_id, :characters, :id},
        {:created_by, :users, :id}
      ]
    }
  end

  defp vn_engines do
    %Spec{
      name: :vn_engines,
      primary_key: "visual_novel_id, engine",
      columns: [:visual_novel_id, :engine],
      where: "visual_novel_id IN (SELECT id FROM visual_novels WHERE hidden_at IS NULL)",
      foreign_keys: [{:visual_novel_id, :visual_novels, :id}]
    }
  end

  defp vn_series do
    %Spec{
      name: :vn_series,
      primary_key: "id",
      columns: [:id, :name, :slug, :description]
    }
  end

  defp vn_series_items do
    %Spec{
      name: :vn_series_items,
      primary_key: "visual_novel_id, vn_series_id",
      columns: [:visual_novel_id, :vn_series_id, :position],
      where: "visual_novel_id IN (SELECT id FROM visual_novels WHERE hidden_at IS NULL)",
      foreign_keys: [
        {:visual_novel_id, :visual_novels, :id},
        {:vn_series_id, :vn_series, :id}
      ]
    }
  end

  # ── Producers ──────────────────────────────────────────────────────────────

  defp producers do
    %Spec{
      name: :producers,
      primary_key: "id",
      columns: [
        :id,
        :vndb_id,
        :name,
        :description,
        :producer_type,
        :language,
        :slug,
        :primary_image_id,
        :is_image_nsfw,
        :is_image_suggestive
      ],
      where: "hidden_at IS NULL",
      foreign_keys: [{:primary_image_id, :producer_images, :id}]
    }
  end

  defp producer_images do
    %Spec{
      name: :producer_images,
      primary_key: "id",
      columns: [
        :id,
        :producer_id,
        :width,
        :height,
        :is_image_nsfw,
        :is_image_suggestive
      ],
      where: "producer_id IN (SELECT id FROM producers WHERE hidden_at IS NULL)",
      foreign_keys: [{:producer_id, :producers, :id}]
    }
  end

  defp producer_external_links do
    %Spec{
      name: :producer_external_links,
      primary_key: "producer_id, site",
      order_by: "producer_id, site, value",
      columns: [:producer_id, :site, :value],
      where: "producer_id IN (SELECT id FROM producers WHERE hidden_at IS NULL)",
      foreign_keys: [{:producer_id, :producers, :id}]
    }
  end

  defp vn_producers do
    %Spec{
      name: :vn_producers,
      primary_key: "visual_novel_id, producer_id",
      columns: [:visual_novel_id, :producer_id, :role, :earliest_release_date],
      where: """
      visual_novel_id IN (SELECT id FROM visual_novels WHERE hidden_at IS NULL)
      AND producer_id IN (SELECT id FROM producers WHERE hidden_at IS NULL)\
      """,
      foreign_keys: [
        {:visual_novel_id, :visual_novels, :id},
        {:producer_id, :producers, :id}
      ]
    }
  end

  # ── Tags ───────────────────────────────────────────────────────────────────

  defp tags do
    %Spec{
      name: :tags,
      primary_key: "id",
      columns: [
        :id,
        :name,
        :slug,
        :description,
        :vndb_tag_id,
        :category,
        :default_spoiler_level,
        :is_theme,
        :kind,
        :content_warning
      ]
    }
  end

  defp tag_parents do
    %Spec{
      name: :tag_parents,
      primary_key: "tag_id, parent_tag_id",
      columns: [:tag_id, :parent_tag_id, :is_main],
      foreign_keys: [
        {:tag_id, :tags, :id},
        {:parent_tag_id, :tags, :id}
      ]
    }
  end

  defp vn_tags do
    %Spec{
      name: :vn_tags,
      primary_key: "visual_novel_id, tag_id",
      columns: [
        :visual_novel_id,
        :tag_id,
        :vndb_vote_count,
        :vndb_avg_score,
        :relevance_score,
        :spoiler_level
      ],
      where: "visual_novel_id IN (SELECT id FROM visual_novels WHERE hidden_at IS NULL)",
      foreign_keys: [
        {:visual_novel_id, :visual_novels, :id},
        {:tag_id, :tags, :id}
      ]
    }
  end

  defp vn_tag_votes do
    %Spec{
      name: :vn_tag_votes,
      primary_key: "id",
      columns: [
        :id,
        {:user_id, :user_fk},
        :visual_novel_id,
        :tag_id,
        :value,
        :spoiler_level,
        {:inserted_at, :date}
      ],
      where: "visual_novel_id IN (SELECT id FROM visual_novels WHERE hidden_at IS NULL)",
      foreign_keys: [
        {:user_id, :users, :id},
        {:visual_novel_id, :visual_novels, :id},
        {:tag_id, :tags, :id}
      ]
    }
  end

  # ── Characters ─────────────────────────────────────────────────────────────

  defp characters do
    %Spec{
      name: :characters,
      primary_key: "id",
      columns: [
        :id,
        :vndb_id,
        :name,
        :description,
        :slug,
        :sex,
        :spoiler_sex,
        :gender,
        :spoiler_gender,
        :blood_type,
        :height,
        :weight,
        :age,
        :birthday,
        :bust,
        :waist,
        :hip,
        :cup_size,
        :vndb_image_id,
        :primary_image_id,
        :is_image_nsfw,
        :is_image_suggestive
      ],
      where: "hidden_at IS NULL"
    }
  end

  defp character_images do
    %Spec{
      name: :character_images,
      primary_key: "id",
      columns: [
        :id,
        :character_id,
        :width,
        :height,
        :is_image_nsfw,
        :is_image_suggestive,
        {:uploaded_by, :user_fk}
      ],
      where: "character_id IN (SELECT id FROM characters WHERE hidden_at IS NULL)",
      foreign_keys: [
        {:character_id, :characters, :id},
        {:uploaded_by, :users, :id}
      ]
    }
  end

  defp vn_characters do
    %Spec{
      name: :vn_characters,
      primary_key: "visual_novel_id, character_id",
      columns: [:visual_novel_id, :character_id, :role, :spoiler_level],
      where: """
      visual_novel_id IN (SELECT id FROM visual_novels WHERE hidden_at IS NULL)
      AND character_id IN (SELECT id FROM characters WHERE hidden_at IS NULL)\
      """,
      foreign_keys: [
        {:visual_novel_id, :visual_novels, :id},
        {:character_id, :characters, :id}
      ]
    }
  end

  defp character_favorites do
    %Spec{
      name: :character_favorites,
      primary_key: "user_id, character_id",
      columns: [
        {:user_id, :user_fk},
        :character_id,
        :position,
        {:inserted_at, :date}
      ],
      where: "character_id IN (SELECT id FROM characters WHERE hidden_at IS NULL)",
      foreign_keys: [
        {:user_id, :users, :id},
        {:character_id, :characters, :id}
      ]
    }
  end

  # ── Engagement (likes + follows) ────────────────────────────────────────────

  defp vn_image_likes do
    %Spec{
      name: :vn_image_likes,
      primary_key: "user_id, vn_image_id",
      columns: [{:user_id, :user_fk}, :vn_image_id, {:inserted_at, :date}],
      where: """
      vn_image_id IN (
        SELECT id FROM vn_images
         WHERE visual_novel_id IN (SELECT id FROM visual_novels WHERE hidden_at IS NULL)
      )\
      """,
      foreign_keys: [
        {:user_id, :users, :id},
        {:vn_image_id, :vn_images, :id}
      ]
    }
  end

  defp vn_screenshot_likes do
    %Spec{
      name: :vn_screenshot_likes,
      primary_key: "user_id, vn_screenshot_id",
      columns: [{:user_id, :user_fk}, :vn_screenshot_id, {:inserted_at, :date}],
      where: """
      vn_screenshot_id IN (
        SELECT id FROM vn_screenshots
         WHERE visual_novel_id IN (SELECT id FROM visual_novels WHERE hidden_at IS NULL)
      )\
      """,
      foreign_keys: [
        {:user_id, :users, :id},
        {:vn_screenshot_id, :vn_screenshots, :id}
      ]
    }
  end

  defp vn_quote_likes do
    %Spec{
      name: :vn_quote_likes,
      primary_key: "user_id, vn_quote_id",
      columns: [{:user_id, :user_fk}, :vn_quote_id, {:inserted_at, :date}],
      where: """
      vn_quote_id IN (
        SELECT id FROM vn_quotes
         WHERE visual_novel_id IN (SELECT id FROM visual_novels WHERE hidden_at IS NULL)
      )\
      """,
      foreign_keys: [
        {:user_id, :users, :id},
        {:vn_quote_id, :vn_quotes, :id}
      ]
    }
  end

  defp producer_follows do
    %Spec{
      name: :producer_follows,
      primary_key: "follower_id, producer_id",
      columns: [
        {:follower_id, :user_fk},
        :producer_id,
        {:inserted_at, :date}
      ],
      where: "producer_id IN (SELECT id FROM producers WHERE hidden_at IS NULL)",
      foreign_keys: [
        {:follower_id, :users, :id},
        {:producer_id, :producers, :id}
      ]
    }
  end

  # ── User-VN tracking ───────────────────────────────────────────────────────

  defp vn_ratings do
    %Spec{
      name: :vn_ratings,
      source_name: :ratings,
      primary_key: "user_id, visual_novel_id",
      columns: [
        {:user_id, :user_fk},
        :visual_novel_id,
        :rating,
        {:inserted_at, :date},
        {:updated_at, :date}
      ],
      where: "visual_novel_id IN (SELECT id FROM visual_novels WHERE hidden_at IS NULL)",
      foreign_keys: [
        {:user_id, :users, :id},
        {:visual_novel_id, :visual_novels, :id}
      ]
    }
  end

  defp vn_reading_statuses do
    %Spec{
      name: :vn_reading_statuses,
      source_name: :reading_statuses,
      primary_key: "user_id, visual_novel_id",
      columns: [
        {:user_id, :user_fk},
        :visual_novel_id,
        :status,
        :date_started,
        :date_finished,
        {:library_added_at, :date},
        :note,
        {:inserted_at, :date},
        {:updated_at, :date}
      ],
      where: "visual_novel_id IN (SELECT id FROM visual_novels WHERE hidden_at IS NULL)",
      foreign_keys: [
        {:user_id, :users, :id},
        {:visual_novel_id, :visual_novels, :id}
      ]
    }
  end

  # ── Community similarities ─────────────────────────────────────────────────

  defp vn_similarities do
    %Spec{
      name: :vn_similarities,
      primary_key: "visual_novel_id, similar_vn_id",
      columns: [
        :visual_novel_id,
        :similar_vn_id,
        :upvotes_count,
        :downvotes_count,
        :score
      ],
      where: """
      visual_novel_id IN (SELECT id FROM visual_novels WHERE hidden_at IS NULL)
      AND similar_vn_id IN (SELECT id FROM visual_novels WHERE hidden_at IS NULL)\
      """,
      foreign_keys: [
        {:visual_novel_id, :visual_novels, :id},
        {:similar_vn_id, :visual_novels, :id}
      ]
    }
  end

  defp vn_similarity_votes do
    %Spec{
      name: :vn_similarity_votes,
      primary_key: "visual_novel_id, similar_vn_id, user_id",
      columns: [
        :visual_novel_id,
        :similar_vn_id,
        {:user_id, :user_fk},
        :vote_value,
        {:inserted_at, :date}
      ],
      where: """
      visual_novel_id IN (SELECT id FROM visual_novels WHERE hidden_at IS NULL)
      AND similar_vn_id IN (SELECT id FROM visual_novels WHERE hidden_at IS NULL)\
      """,
      foreign_keys: [
        {:visual_novel_id, :visual_novels, :id},
        {:similar_vn_id, :visual_novels, :id},
        {:user_id, :users, :id}
      ]
    }
  end

  # ── Synthesized + filtered ─────────────────────────────────────────────────

  defp entry_meta do
    %Spec{
      name: :entry_meta,
      primary_key: "entity_type, entity_id",
      columns: [
        :entity_type,
        :entity_id,
        :created,
        :last_modified,
        :revision,
        :num_edits,
        :num_users
      ],
      sql: """
      SELECT entity_type,
             entity_id,
             min(inserted_at)::date AS created,
             max(inserted_at)::date AS last_modified,
             max(revision_number) AS revision,
             count(*) FILTER (WHERE source = 'user') AS num_edits,
             count(DISTINCT user_id) FILTER (WHERE source = 'user') AS num_users
        FROM changes
       GROUP BY entity_type, entity_id
       ORDER BY entity_type, entity_id\
      """
    }
  end

  defp users do
    %Spec{
      name: :users,
      primary_key: "id",
      columns: [:id, :username, :display_name, :ratings_suppressed],
      where: """
      username IS NOT NULL
      AND (
        id IN (SELECT user_id FROM changes WHERE source = 'user' AND user_id IS NOT NULL)
        OR id IN (
          SELECT uploaded_by FROM vn_images
           WHERE uploaded_by IS NOT NULL
             AND visual_novel_id IN (SELECT id FROM visual_novels WHERE hidden_at IS NULL)
        )
        OR id IN (
          SELECT uploaded_by FROM vn_screenshots
           WHERE uploaded_by IS NOT NULL
             AND visual_novel_id IN (SELECT id FROM visual_novels WHERE hidden_at IS NULL)
        )
        OR id IN (
          SELECT uploaded_by FROM character_images
           WHERE uploaded_by IS NOT NULL
             AND character_id IN (SELECT id FROM characters WHERE hidden_at IS NULL)
        )
        OR id IN (
          SELECT created_by FROM vn_quotes
           WHERE created_by IS NOT NULL
             AND visual_novel_id IN (SELECT id FROM visual_novels WHERE hidden_at IS NULL)
        )
        OR id IN (
          SELECT user_id FROM vn_tag_votes
           WHERE visual_novel_id IN (SELECT id FROM visual_novels WHERE hidden_at IS NULL)
        )
        OR id IN (
          SELECT user_id FROM vn_image_likes
           WHERE vn_image_id IN (
             SELECT id FROM vn_images
              WHERE visual_novel_id IN (SELECT id FROM visual_novels WHERE hidden_at IS NULL)
           )
        )
        OR id IN (
          SELECT user_id FROM vn_screenshot_likes
           WHERE vn_screenshot_id IN (
             SELECT id FROM vn_screenshots
              WHERE visual_novel_id IN (SELECT id FROM visual_novels WHERE hidden_at IS NULL)
           )
        )
        OR id IN (
          SELECT user_id FROM vn_quote_likes
           WHERE vn_quote_id IN (
             SELECT id FROM vn_quotes
              WHERE visual_novel_id IN (SELECT id FROM visual_novels WHERE hidden_at IS NULL)
           )
        )
        OR id IN (
          SELECT user_id FROM character_favorites
           WHERE character_id IN (SELECT id FROM characters WHERE hidden_at IS NULL)
        )
        OR id IN (
          SELECT user_id FROM vn_similarity_votes
           WHERE visual_novel_id IN (SELECT id FROM visual_novels WHERE hidden_at IS NULL)
        )
        OR id IN (
          SELECT user_id FROM ratings
           WHERE visual_novel_id IN (SELECT id FROM visual_novels WHERE hidden_at IS NULL)
        )
        OR id IN (
          SELECT user_id FROM reading_statuses
           WHERE visual_novel_id IN (SELECT id FROM visual_novels WHERE hidden_at IS NULL)
        )
        OR id IN (
          SELECT follower_id FROM producer_follows
           WHERE producer_id IN (SELECT id FROM producers WHERE hidden_at IS NULL)
        )
      )\
      """
    }
  end
end
