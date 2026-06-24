defmodule Kaguya.VisualNovels.VersionTest do
  use ExUnit.Case, async: true

  alias Kaguya.VisualNovels.Version

  @valid %{
    visual_novel_id: UUIDv7.generate(),
    source: "patreon_watcher",
    version_number: "0.11.1",
    status: "published"
  }

  describe "changeset/2 enum validation" do
    test "accepts the canonical source/status/update_type/release_type values" do
      changeset =
        Version.changeset(
          %Version{},
          %{
            @valid
            | source: "patreon_watcher",
              status: "pending"
          }
          |> Map.put(:update_type, "bugfix")
          |> Map.put(:release_type, "early")
        )

      assert changeset.valid?
    end

    test "rejects an unknown source" do
      changeset = Version.changeset(%Version{}, %{@valid | source: "twitter"})
      refute changeset.valid?
      assert {"is invalid", _} = changeset.errors[:source]
    end

    test "rejects an unknown status" do
      changeset = Version.changeset(%Version{}, %{@valid | status: "draft"})
      refute changeset.valid?
      assert {"is invalid", _} = changeset.errors[:status]
    end

    test "rejects an unknown update_type" do
      changeset =
        Version.changeset(%Version{}, Map.put(@valid, :update_type, "marketing"))

      refute changeset.valid?
      assert {"is invalid", _} = changeset.errors[:update_type]
    end

    test "rejects an unknown release_type" do
      changeset =
        Version.changeset(%Version{}, Map.put(@valid, :release_type, "freebie"))

      refute changeset.valid?
      assert {"is invalid", _} = changeset.errors[:release_type]
    end

    test "allows nil update_type and release_type" do
      changeset =
        Version.changeset(%Version{}, Map.merge(@valid, %{update_type: nil, release_type: nil}))

      assert changeset.valid?
    end

    test "requires version_number, source, visual_novel_id" do
      changeset = Version.changeset(%Version{}, %{})
      refute changeset.valid?

      # status has a schema-level default of "published" so it's not flagged
      # missing on a bare struct — but if a caller actively sets it nil it
      # should be flagged. Cover both shapes.
      for field <- [:version_number, :source, :visual_novel_id] do
        assert Keyword.has_key?(changeset.errors, field), "expected error on #{field}"
      end

      explicit_nil =
        Version.changeset(%Version{}, Map.put(@valid, :status, nil))

      refute explicit_nil.valid?
      assert Keyword.has_key?(explicit_nil.errors, :status)
    end

    test "version_number is bounded at 64 chars" do
      long = String.duplicate("a", 65)
      changeset = Version.changeset(%Version{}, %{@valid | version_number: long})
      refute changeset.valid?
      assert Keyword.has_key?(changeset.errors, :version_number)
    end
  end

  describe "mod_edit_changeset/2" do
    test "casts only the user-visible content fields" do
      version = %Version{
        id: UUIDv7.generate(),
        visual_novel_id: UUIDv7.generate(),
        source: "patreon_watcher",
        version_number: "0.5.0",
        status: "pending"
      }

      changeset =
        Version.mod_edit_changeset(version, %{
          version_number: "0.5.1",
          changelog: "fixed a typo",
          # Unaccepted fields — should not appear in changes
          status: "published",
          source: "manual",
          reviewed_by_user_id: UUIDv7.generate()
        })

      assert changeset.changes.version_number == "0.5.1"
      assert changeset.changes.changelog == "fixed a typo"
      refute Map.has_key?(changeset.changes, :status)
      refute Map.has_key?(changeset.changes, :source)
      refute Map.has_key?(changeset.changes, :reviewed_by_user_id)
    end

    test "rejects unknown update_type via the same enum" do
      version = %Version{version_number: "0.5", status: "pending"}
      changeset = Version.mod_edit_changeset(version, %{update_type: "fluff"})
      refute changeset.valid?
    end
  end
end
