This is a public export of the Kaguya database.


Format
======

Each table is exported as a separate file in PostgreSQL's COPY format
(TSV with escape sequences).

To load the dump into a fresh PostgreSQL database:

  createdb kaguya_dump
  psql -d kaguya_dump -f import.sql

The included schema is a public-facing subset of Kaguya's live schema.

What's included
===============

Catalog:
  visual_novels, vn_titles, vn_images, vn_external_links,
  vn_relations, vn_releases, vn_release_extlinks, vn_screenshots,
  vn_quotes, vn_engines, vn_series, vn_series_items

Producers:
  producers, producer_external_links, vn_producers

Tags:
  tags, tag_parents, vn_tags, vn_tag_votes

Characters:
  characters, character_images, vn_characters, character_likes,
  character_favorites

User engagement (per-user, per-thing -- attribution is preserved):
  vn_image_likes, vn_screenshot_likes, vn_quote_likes,
  producer_follows, vn_ratings, vn_reading_statuses,
  vn_similarities, vn_similarity_votes

Synthesized:
  entry_meta -- per-entity audit summary (entity_type, entity_id,
  created, last_modified, revision, num_edits, num_users), aggregated
  from the changes log. Replaces per-revision history.

Filtered:
  users -- only public contributors are included. Columns: id,
  username, display_name, ratings_suppressed.

Privacy notes
=============

  - Users with no public contributions don't appear, the
    `users` table contains only contributors.
  - User IDs of contributors who appear are real internal UUIDs,
    joinable across tables in the dump.
  - If you republish data from this dump, please resync regularly so
    rows that have been deleted or hidden upstream don't linger
    downstream.


Catalog data attribution
========================

Most catalog metadata (visual novels, producers, characters, tags,
etc.) is derived from VNDB.org under ODbL. Cross-reference IDs back
to VNDB are preserved as `vndb_id`, `vndb_tag_id`, `vndb_cv_id`,
`vndb_image_id`, `vndb_sf_id` where applicable. See
https://vndb.org/d14 for VNDB's source dump.


License
=======
This database is made available under the Open Database License [ODbL].
Any rights in individual contents of the database are licensed under the
Database Contents License [DbCL].

LICENSE-ODBL.txt; http://opendatacommons.org/licenses/odbl/1.0/
LICENSE-DBCL.txt; http://opendatacommons.org/licenses/dbcl/1.0/

