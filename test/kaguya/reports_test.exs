defmodule Kaguya.ReportsTest do
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Ecto.Adapters.SQL.Sandbox
  alias Kaguya.Repo
  alias Kaguya.Reports
  alias Kaguya.Social.Notification
  alias Kaguya.Test.UserFixtures
  alias Kaguya.VisualNovels.VisualNovel

  setup do
    :ok = Sandbox.checkout(Repo)

    reporter = UserFixtures.insert_user!()
    moderator = UserFixtures.insert_user!()

    %{reporter: reporter, moderator: moderator}
  end

  describe "report review notifications" do
    test "terminal report decisions notify the reporter with the moderator note", %{
      reporter: reporter,
      moderator: moderator
    } do
      vn = insert_vn!()

      {:ok, report} =
        Reports.create_report(%{
          reporter_id: reporter.id,
          entity_type: "visual_novel",
          entity_id: vn.id,
          entity_name: vn.title,
          category: "spam",
          reason: "Looks promotional"
        })

      {:ok, resolved} =
        Reports.update_report_status(report.id, %{
          status: :resolved,
          resolved_by: moderator.id,
          resolved_at: DateTime.utc_now() |> DateTime.truncate(:second),
          mod_notes: "Internal spam-policy note.",
          resolution_note: "Thanks, we removed the spam."
        })

      notification = notification_for!(reporter.id, resolved.id)
      assert notification.action == :report_reviewed
      assert notification.entity_type == :report
      assert notification.metadata.report_status == "resolved"
      assert notification.metadata.report_entity_type == "visual_novel"
      assert notification.metadata.report_entity_name == vn.title
      assert notification.metadata.report_entity_path == "/vn/#{vn.slug}"
      assert notification.metadata.text_preview == "Thanks, we removed the spam."
    end

    test "terminal report notifications never expose internal moderator notes", %{
      reporter: reporter,
      moderator: moderator
    } do
      {:ok, report} =
        Reports.create_report(%{
          reporter_id: reporter.id,
          entity_type: "post",
          entity_id: Ecto.UUID.generate(),
          entity_name: "Suspicious discussion",
          category: "spam",
          reason: "Looks promotional"
        })

      {:ok, resolved} =
        Reports.update_report_status(report.id, %{
          status: :resolved,
          resolved_by: moderator.id,
          resolved_at: DateTime.utc_now() |> DateTime.truncate(:second),
          mod_notes: "Do not disclose this internal evidence note.",
          resolution_note: "Thanks, this has been handled."
        })

      notification = notification_for!(reporter.id, resolved.id)
      assert notification.metadata.text_preview == "Thanks, this has been handled."
      refute notification.metadata.text_preview =~ "internal evidence"
    end

    test "terminal report decisions require a resolution note", %{
      reporter: reporter,
      moderator: moderator
    } do
      {:ok, report} =
        Reports.create_report(%{
          reporter_id: reporter.id,
          entity_type: "post",
          entity_id: Ecto.UUID.generate(),
          category: "spam",
          reason: "Looks promotional"
        })

      assert {:error, changeset} =
               Reports.update_report_status(report.id, %{
                 status: :resolved,
                 resolved_by: moderator.id,
                 resolved_at: DateTime.utc_now() |> DateTime.truncate(:second),
                 mod_notes: "Internal only."
               })

      assert "can't be blank" in errors_on(changeset).resolution_note
    end

    test "non-terminal report status updates stay internal", %{reporter: reporter} do
      {:ok, report} =
        Reports.create_report(%{
          reporter_id: reporter.id,
          entity_type: "post",
          entity_id: Ecto.UUID.generate(),
          category: "spam",
          reason: "Needs review"
        })

      assert {:ok, _report} = Reports.update_report_status(report.id, %{status: :in_progress})

      assert [] ==
               Repo.all(
                 from n in Notification,
                   where: n.user_id == ^reporter.id,
                   where: n.entity_type == :report
               )
    end
  end

  describe "report entity paths" do
    test "returns a canonical path for linkable report targets" do
      vn = insert_vn!()
      expected_path = "/vn/#{vn.slug}"

      assert Reports.entity_path_for_report(%{entity_type: "visual_novel", entity_id: vn.id}) ==
               expected_path
    end

    test "returns nil instead of raising for malformed target ids" do
      assert Reports.entity_path_for_report(%{entity_type: "post", entity_id: "not-a-uuid"}) ==
               nil
    end
  end

  defp notification_for!(user_id, report_id) do
    Repo.one!(
      from n in Notification,
        where: n.user_id == ^user_id,
        where: n.entity_type == :report,
        where: n.entity_id == ^report_id,
        order_by: [desc: n.inserted_at],
        limit: 1
    )
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end

  defp insert_vn! do
    suffix = System.unique_integer([:positive])

    %VisualNovel{}
    |> VisualNovel.changeset(%{
      title: "Reported VN #{suffix}",
      original_language: "en"
    })
    |> Repo.insert!()
  end
end
