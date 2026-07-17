defmodule Kaguya.ShelvesTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Kaguya.Repo
  alias Kaguya.Shelves
  alias Kaguya.Shelves.ReadingStatus
  alias Kaguya.Test.UserFixtures
  alias Kaguya.VisualNovels.VisualNovel

  setup do
    :ok = Sandbox.checkout(Repo)
    :ok
  end

  describe "set_reading_status/3 — date_started auto-fill" do
    test "stamps today when transitioning a new entry to :currently_reading" do
      user = UserFixtures.insert_user!()
      vn = insert_vn!("autofill-new")

      assert {:ok, _} =
               Shelves.set_reading_status(user.id, vn.id, %{status: :currently_reading})

      assert %ReadingStatus{date_started: %Date{} = d} = get_status(user.id, vn.id)
      assert d == Date.utc_today()
    end

    test "fills date_started when an existing entry without one moves to :currently_reading" do
      user = UserFixtures.insert_user!()
      vn = insert_vn!("autofill-existing")

      {:ok, _} = Shelves.set_reading_status(user.id, vn.id, %{status: :want_to_read})
      assert %ReadingStatus{date_started: nil} = get_status(user.id, vn.id)

      {:ok, _} = Shelves.set_reading_status(user.id, vn.id, %{status: :currently_reading})

      assert %ReadingStatus{date_started: d} = get_status(user.id, vn.id)
      assert d == Date.utc_today()
    end

    test "preserves an existing date_started when re-setting status to :currently_reading" do
      user = UserFixtures.insert_user!()
      vn = insert_vn!("autofill-preserve")
      manual = ~D[2024-03-01]

      {:ok, _} =
        Shelves.set_reading_status(user.id, vn.id, %{
          status: :currently_reading,
          date_started: manual
        })

      {:ok, _} = Shelves.set_reading_status(user.id, vn.id, %{status: :currently_reading})

      assert %ReadingStatus{date_started: ^manual} = get_status(user.id, vn.id)
    end

    test "does not fill date_started for other statuses" do
      user = UserFixtures.insert_user!()
      vn = insert_vn!("autofill-other")

      {:ok, _} = Shelves.set_reading_status(user.id, vn.id, %{status: :want_to_read})

      assert %ReadingStatus{date_started: nil} = get_status(user.id, vn.id)
    end

    test "respects an explicit :date_started key passed by importers (even when nil)" do
      user = UserFixtures.insert_user!()
      vn = insert_vn!("autofill-importer")

      {:ok, _} =
        Shelves.set_reading_status(user.id, vn.id, %{
          status: :currently_reading,
          date_started: nil
        })

      assert %ReadingStatus{date_started: nil} = get_status(user.id, vn.id)
    end

    test "auto-fills across a bulk call only for rows without an existing date_started" do
      user = UserFixtures.insert_user!()
      vn1 = insert_vn!("autofill-bulk-a")
      vn2 = insert_vn!("autofill-bulk-b")
      manual = ~D[2023-12-25]

      {:ok, _} =
        Shelves.set_reading_status(user.id, vn1.id, %{
          status: :currently_reading,
          date_started: manual
        })

      {:ok, _} =
        Shelves.set_reading_status(user.id, [vn1.id, vn2.id], %{status: :currently_reading})

      assert %ReadingStatus{date_started: ^manual} = get_status(user.id, vn1.id)
      assert %ReadingStatus{date_started: today} = get_status(user.id, vn2.id)
      assert today == Date.utc_today()
    end
  end

  describe "set_reading_status/3 — date_finished auto-fill" do
    test "stamps today when marking a VN read without a date" do
      user = UserFixtures.insert_user!()
      vn = insert_vn!("finished-autofill-new")

      assert {:ok, _} = Shelves.set_reading_status(user.id, vn.id, %{status: :read})

      assert %ReadingStatus{date_finished: d} = get_status(user.id, vn.id)
      assert d == Date.utc_today()
    end

    test "never overwrites a read date the user already set" do
      user = UserFixtures.insert_user!()
      vn = insert_vn!("finished-autofill-preserve")
      manual = ~D[2019-06-02]

      {:ok, _} =
        Shelves.set_reading_status(user.id, vn.id, %{status: :read, date_finished: manual})

      {:ok, _} = Shelves.set_reading_status(user.id, vn.id, %{status: :read})

      assert %ReadingStatus{date_finished: ^manual} = get_status(user.id, vn.id)
    end

    test "respects an explicit :date_finished key passed by importers (even when nil)" do
      user = UserFixtures.insert_user!()
      vn = insert_vn!("finished-autofill-importer")

      {:ok, _} =
        Shelves.set_reading_status(user.id, vn.id, %{status: :read, date_finished: nil})

      assert %ReadingStatus{date_finished: nil} = get_status(user.id, vn.id)
    end

    test "does not fill date_finished for other statuses" do
      user = UserFixtures.insert_user!()
      vn = insert_vn!("finished-autofill-other")

      {:ok, _} = Shelves.set_reading_status(user.id, vn.id, %{status: :currently_reading})

      assert %ReadingStatus{date_finished: nil} = get_status(user.id, vn.id)
    end
  end

  describe "set_reading_status/3 — explicit clears" do
    test "an explicit nil clears a date that was previously set" do
      user = UserFixtures.insert_user!()
      vn = insert_vn!("clear-explicit")

      {:ok, _} =
        Shelves.set_reading_status(user.id, vn.id, %{
          status: :read,
          date_started: ~D[2024-01-01],
          date_finished: ~D[2024-01-10]
        })

      {:ok, _} =
        Shelves.set_reading_status(user.id, vn.id, %{
          status: :read,
          date_started: nil,
          date_finished: ~D[2024-01-10]
        })

      assert %ReadingStatus{date_started: nil, date_finished: ~D[2024-01-10]} =
               get_status(user.id, vn.id)
    end

    test "an omitted key leaves the stored date alone" do
      user = UserFixtures.insert_user!()
      vn = insert_vn!("clear-omitted")

      {:ok, _} =
        Shelves.set_reading_status(user.id, vn.id, %{
          status: :read,
          date_started: ~D[2024-01-01],
          date_finished: ~D[2024-01-10]
        })

      {:ok, _} = Shelves.set_reading_status(user.id, vn.id, %{status: :read})

      assert %ReadingStatus{date_started: ~D[2024-01-01], date_finished: ~D[2024-01-10]} =
               get_status(user.id, vn.id)
    end
  end

  describe "set_reading_status/3 — inferring :read from a finish date" do
    test "a finish date with no status at all implies :read" do
      user = UserFixtures.insert_user!()
      vn = insert_vn!("coerce-implied")

      {:ok, _} = Shelves.set_reading_status(user.id, vn.id, %{date_finished: ~D[2024-02-02]})

      assert %ReadingStatus{status: :read} = get_status(user.id, vn.id)
    end

    test "a newly set finish date implies :read even against an explicit status" do
      user = UserFixtures.insert_user!()
      vn = insert_vn!("coerce-newly-set")

      {:ok, _} = Shelves.set_reading_status(user.id, vn.id, %{status: :currently_reading})

      # Picking a started→finished range in the library grid sends the item's
      # own status alongside a finish date it did not have before.
      {:ok, _} =
        Shelves.set_reading_status(user.id, vn.id, %{
          status: :currently_reading,
          date_started: ~D[2024-01-01],
          date_finished: ~D[2024-01-10]
        })

      assert %ReadingStatus{status: :read, date_finished: ~D[2024-01-10]} =
               get_status(user.id, vn.id)
    end

    test "an unchanged finish date riding along does not drag a reread back to :read" do
      user = UserFixtures.insert_user!()
      vn = insert_vn!("coerce-reread")
      finished = ~D[2024-02-02]

      {:ok, _} =
        Shelves.set_reading_status(user.id, vn.id, %{status: :read, date_finished: finished})

      # The review dialog round-trips date_finished as a hidden input, so the
      # stored date rides along unchanged when the user starts a reread.
      {:ok, _} =
        Shelves.set_reading_status(user.id, vn.id, %{
          status: :currently_reading,
          date_finished: finished
        })

      assert %ReadingStatus{status: :currently_reading, date_finished: ^finished} =
               get_status(user.id, vn.id)
    end

    test "clearing the finish date leaves an explicit status alone" do
      user = UserFixtures.insert_user!()
      vn = insert_vn!("coerce-cleared")

      {:ok, _} =
        Shelves.set_reading_status(user.id, vn.id, %{status: :read, date_finished: ~D[2024-02-02]})

      {:ok, _} =
        Shelves.set_reading_status(user.id, vn.id, %{
          status: :currently_reading,
          date_finished: nil
        })

      assert %ReadingStatus{status: :currently_reading, date_finished: nil} =
               get_status(user.id, vn.id)
    end
  end

  defp insert_vn!(title) do
    Repo.insert!(%VisualNovel{
      id: Ecto.UUID.generate(),
      title: title,
      slug: "vn-" <> title,
      title_category: :vn,
      ratings_count: 0,
      reviews_count: 0
    })
  end

  defp get_status(user_id, vn_id) do
    Repo.get_by!(ReadingStatus, user_id: user_id, visual_novel_id: vn_id)
  end
end
