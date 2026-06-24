defmodule KaguyaWeb.VNLive.Edit.FormTest do
  use KaguyaWeb.ConnCase, async: true

  alias KaguyaWeb.VNLive.Edit.Form

  describe "normalize/2" do
    test "normalizes scalar fields and booleans" do
      current = Form.empty_form()

      normalized =
        Form.normalize(
          %{
            "description" => "  Updated description  ",
            "has_ero" => "true",
            "is_avn" => "on",
            "length_category" => "short",
            "min_age" => "18",
            "release_date" => "2024-12-31",
            "titles" => %{
              "0" => %{
                "lang" => "ja",
                "title" => "  Test VN  ",
                "latin" => "",
                "official" => "true"
              }
            },
            "screenshots" => %{
              "0" => %{
                "id" => "shot-1",
                "thumbnail_url" => "/screenshots/shot-1",
                "is_nsfw" => "true",
                "is_brutal" => "false"
              }
            },
            "covers" => %{
              "0" => %{
                "id" => "cover-1",
                "thumbnail_url" => "/covers/cover-1",
                "is_image_nsfw" => "1"
              }
            }
          },
          current
        )

      assert normalized["description"] == "Updated description"
      assert normalized["has_ero"] == true
      assert normalized["is_avn"] == true
      assert normalized["length_category"] == "short"
      assert normalized["min_age"] == "18"
      assert normalized["release_date"] == "2024-12-31"

      assert normalized["titles"] == [
               %{"lang" => "ja", "title" => "Test VN", "latin" => "", "official" => true}
             ]

      assert hd(normalized["screenshots"])["is_nsfw"] == true
      assert hd(normalized["covers"])["is_image_nsfw"] == true
    end

    test "normalizes relation rows and dedupes by related VN id" do
      normalized =
        Form.normalize(
          %{
            "relations" => %{
              "0" => %{
                "related_vn_id" => "vn-1",
                "related_vn_slug" => "vn-1",
                "related_vn_title" => "VN One",
                "relation_type" => "",
                "is_official" => "false"
              },
              "1" => %{
                "related_vn_id" => "vn-1",
                "related_vn_slug" => "vn-1",
                "related_vn_title" => "VN One Duplicate",
                "relation_type" => "prequel",
                "is_official" => "true"
              },
              "2" => %{
                "related_vn_id" => "",
                "related_vn_slug" => "",
                "related_vn_title" => "",
                "relation_type" => "side_story",
                "is_official" => "true"
              }
            }
          },
          Form.empty_form()
        )

      assert [
               %{
                 "related_vn_id" => "vn-1",
                 "related_vn_slug" => "vn-1",
                 "related_vn_title" => "VN One",
                 "relation_type" => "sequel",
                 "is_official" => false,
                 "removed" => false
               }
             ] == normalized["relations"]
    end
  end

  describe "validate/1" do
    test "accepts valid form payloads with minimum title and summary" do
      form =
        Form.normalize(
          %{
            "summary" => "ok",
            "titles" => %{
              "0" => %{"lang" => "ja", "title" => "VN", "latin" => "", "official" => "true"}
            }
          },
          Form.empty_form()
        )

      assert {:ok, [_title], "ok"} = Form.validate(form)
    end

    test "returns an error when summary is too short" do
      form =
        Form.normalize(
          %{
            "summary" => "x",
            "titles" => %{
              "0" => %{"lang" => "ja", "title" => "VN", "latin" => "", "official" => "true"}
            }
          },
          Form.empty_form()
        )

      assert {:error, "Summary must be at least 2 characters."} = Form.validate(form)
    end

    test "returns an error when titles are malformed" do
      form =
        Form.normalize(
          %{"summary" => "good", "titles" => %{"0" => %{"lang" => "", "title" => "VN"}}},
          Form.empty_form()
        )

      assert {:error, "Each title row needs both a language and a title."} = Form.validate(form)
    end

    test "returns an error for missing titles" do
      form = Form.normalize(%{"summary" => "good", "titles" => %{}}, Form.empty_form())

      assert {:error, "Add at least one title before saving."} = Form.validate(form)
    end
  end

  describe "build_changes/2 and dirty_fields/2" do
    test "builds normalized changeset map for scalar and relation changes" do
      original =
        Form.empty_form()
        |> Map.put("description", "Old description")
        |> Map.put("min_age", "18")
        |> Map.put("titles", [
          %{"lang" => "ja", "title" => "Old VN", "latin" => "", "official" => true}
        ])
        |> Map.put("relations", [
          %{
            "related_vn_id" => "vn-1",
            "relation_type" => "sequel",
            "is_official" => true,
            "removed" => false
          }
        ])
        |> Map.put("covers", [
          %{"id" => "cover-1", "removed" => false, "is_image_nsfw" => false}
        ])
        |> Map.put("primary_cover_id", "cover-1")

      form =
        original
        |> Map.put("description", "New description")
        |> Map.put("min_age", "")
        |> Map.put("titles", [
          %{"lang" => "ja", "title" => "New VN", "latin" => "", "official" => true}
        ])
        |> Map.put("relations", [])
        |> Map.put("screenshots", [])
        |> Map.put("covers", [
          %{"id" => "cover-1", "removed" => true, "is_image_nsfw" => false},
          %{"id" => "cover-2", "removed" => false, "is_image_nsfw" => true}
        ])
        |> Map.put("primary_cover_id", "cover-1")

      assert %{
               description: "New description",
               min_age: nil,
               titles: [%{lang: "ja", title: "New VN", latin: nil, official: true}],
               relations: [],
               covers: [%{cover_id: "cover-2", is_image_nsfw: true}],
               removed_cover_ids: ["cover-1"]
             } = Form.build_changes(original, Form.normalize_primary_cover(form))
    end

    test "dirty_fields includes cover and primary cover change when selected cover is removed" do
      original = Form.empty_form()

      form =
        original
        |> Map.put("primary_cover_id", "cover-1")
        |> Map.put("covers", [
          %{"id" => "cover-1", "removed" => true},
          %{"id" => "cover-2", "removed" => false}
        ])

      normalized_form = Form.normalize_primary_cover(form)

      assert "cover-2" == normalized_form["primary_cover_id"]

      assert Enum.sort(["covers", "primary cover"]) ==
               Enum.sort(Form.dirty_fields(original, normalized_form))
    end
  end

  describe "relation helpers" do
    test "adds relation rows and restores removed duplicates" do
      form =
        Form.add_relation(
          [],
          %{"related_vn_id" => "vn-1", "relation_type" => "prequel", "is_official" => true},
          "vn-self"
        )

      restored =
        Form.add_relation(
          [
            %{
              "related_vn_id" => "vn-1",
              "relation_type" => "side_story",
              "is_official" => false,
              "removed" => true
            }
          ],
          %{"related_vn_id" => "vn-1", "relation_type" => "prequel", "is_official" => true},
          "vn-self"
        )

      assert form == [
               %{
                 "related_vn_id" => "vn-1",
                 "relation_type" => "prequel",
                 "is_official" => true,
                 "removed" => false
               }
             ]

      assert restored == [
               %{
                 "related_vn_id" => "vn-1",
                 "relation_type" => "side_story",
                 "is_official" => false,
                 "removed" => false
               }
             ]
    end

    test "does not add current VN as relation target" do
      assert [] =
               Form.add_relation(
                 [],
                 %{"related_vn_id" => "vn-self", "is_official" => true},
                 "vn-self"
               )

      assert [] = Form.add_relation([], %{"related_vn_id" => ""}, "vn-self")
    end
  end
end
