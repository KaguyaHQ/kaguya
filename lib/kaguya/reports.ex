defmodule Kaguya.Reports do
  @moduledoc """
  Context for the report/moderation system.
  """

  import Ecto.Query
  alias Kaguya.Characters.Character
  alias Kaguya.Discussions.{Comment, Post}
  alias Kaguya.Lists.{ListComment, List}
  alias Kaguya.Producers.Producer
  alias Kaguya.Releases.Release
  alias Kaguya.Repo
  alias Kaguya.Reports.Report
  alias Kaguya.Reviews.{Review, ReviewComment}
  alias Kaguya.VisualNovels.Series
  alias Kaguya.Social
  alias Kaguya.Users.User
  alias Kaguya.VisualNovels.VisualNovel

  @max_reports_per_day 5

  @doc """
  Creates a report. Rate limited to 5/day per user.
  Prevents duplicate open reports from same user for same entity.
  Prevents self-reporting for user reports.
  """
  def create_report(attrs) do
    reporter_id = attrs[:reporter_id] || attrs["reporter_id"]

    with :ok <- check_not_self_report(attrs),
         :ok <- check_rate_limit(reporter_id),
         {:ok, report} <- %Report{} |> Report.changeset(attrs) |> Repo.insert() do
      {:ok, Repo.preload(report, [:reporter, :resolver])}
    end
  end

  def get_report(id) do
    case Repo.get(Report, id) do
      nil -> {:error, "Report not found"}
      report -> {:ok, report}
    end
  end

  @doc """
  Updates a report's status. Mod/admin only (enforced at resolver level).
  """
  def update_report_status(report_id, attrs) do
    case Repo.get(Report, report_id) do
      nil ->
        {:error, "Report not found"}

      report ->
        previous_status = report.status

        with {:ok, report} <- report |> Report.resolve_changeset(attrs) |> Repo.update() do
          report = Repo.preload(report, [:reporter, :resolver])
          maybe_notify_reporter(report, Map.put(attrs, :previous_status, previous_status))
          {:ok, report}
        end
    end
  end

  @doc """
  Lists reports with optional filters. For the mod queue.
  """
  def list_reports(opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    page_size = Keyword.get(opts, :page_size, 25)
    status = Keyword.get(opts, :status)
    entity_type = Keyword.get(opts, :entity_type)
    reporter_id = Keyword.get(opts, :reporter_id)
    entity_id = Keyword.get(opts, :entity_id)

    visible_types = Keyword.get(opts, :visible_entity_types, :all)

    query =
      from(r in Report,
        order_by: [desc: r.inserted_at],
        preload: [:reporter, :resolver]
      )
      |> maybe_filter(:status, status)
      |> maybe_filter(:entity_type, entity_type)
      |> maybe_filter(:reporter_id, reporter_id)
      |> maybe_filter_entity(entity_type, entity_id)
      |> filter_visible_types(visible_types)

    {reports, pagination} = Kaguya.Pagination.paginate(query, page, page_size)
    {:ok, %{items: reports, pagination: pagination}}
  end

  @doc """
  Count of unresolved reports (for nav badge). Filtered by visible types.
  """
  def unresolved_count(visible_types \\ :all) do
    from(r in Report, where: r.status in [:new, :in_progress])
    |> filter_visible_types(visible_types)
    |> Repo.aggregate(:count)
  end

  @doc "Returns the best in-app path for the report target, when one can be resolved."
  def entity_path_for_report(%Report{entity_type: entity_type, entity_id: entity_id}),
    do: entity_path(to_string(entity_type), entity_id)

  def entity_path_for_report(%{entity_type: entity_type, entity_id: entity_id}),
    do: entity_path(to_string(entity_type), entity_id)

  def entity_path_for_report(_report), do: nil

  @doc """
  Returns the entity types a mod can see reports for, based on their capabilities.
  Admins see everything (`:all`); other roles see a list filtered by their flags.
  """
  def visible_report_types(user) do
    if user.role == :admin do
      :all
    else
      types = []

      types =
        if Map.get(user, :mod_db),
          do: types ++ ~w(visual_novel character producer release series),
          else: types

      types = if Map.get(user, :mod_discussions), do: types ++ ~w(post post_comment), else: types
      types = if Map.get(user, :mod_reviews), do: types ++ ~w(review review_comment), else: types
      types = if Map.get(user, :mod_lists), do: types ++ ~w(list list_comment), else: types
      types = if Map.get(user, :mod_users), do: types ++ ~w(user), else: types
      types ++ ["other"]
    end
  end

  # Private

  defp check_not_self_report(%{entity_type: "user", entity_id: eid, reporter_id: rid})
       when eid == rid,
       do: {:error, "You cannot report yourself"}

  defp check_not_self_report(_attrs), do: :ok

  defp check_rate_limit(reporter_id) do
    one_day_ago = DateTime.utc_now() |> DateTime.add(-86_400, :second)

    count =
      from(r in Report,
        where: r.reporter_id == ^reporter_id and r.inserted_at > ^one_day_ago
      )
      |> Repo.aggregate(:count)

    if count >= @max_reports_per_day do
      {:error, "You can only submit #{@max_reports_per_day} reports per day"}
    else
      :ok
    end
  end

  defp maybe_filter(query, _field, nil), do: query
  defp maybe_filter(query, :status, status), do: where(query, [r], r.status == ^status)
  defp maybe_filter(query, :entity_type, type), do: where(query, [r], r.entity_type == ^type)
  defp maybe_filter(query, :reporter_id, id), do: where(query, [r], r.reporter_id == ^id)

  defp maybe_filter_entity(query, _type, nil), do: query
  defp maybe_filter_entity(query, _type, id), do: where(query, [r], r.entity_id == ^id)

  defp filter_visible_types(query, :all), do: query

  defp filter_visible_types(query, types) when is_list(types),
    do: where(query, [r], r.entity_type in ^types)

  defp maybe_notify_reporter(%Report{status: status} = report, attrs)
       when status in [:resolved, :dismissed] do
    previous_status = Map.get(attrs, :previous_status) || Map.get(attrs, "previous_status")

    if previous_status == status do
      :ok
    else
      Social.create_notification(%{
        user_id: report.reporter_id,
        action: :report_reviewed,
        entity_type: :report,
        entity_id: report.id,
        metadata: %{
          report_status: Atom.to_string(status),
          report_entity_type: report.entity_type,
          report_entity_name: report.entity_name,
          report_entity_path: entity_path_for_report(report),
          text_preview: report.resolution_note && String.slice(report.resolution_note, 0, 500)
        }
      })

      :ok
    end
  end

  defp maybe_notify_reporter(_report, _attrs), do: :ok

  defp entity_path(_type, entity_id) when entity_id in [nil, ""], do: nil
  defp entity_path("visual_novel", id), do: slug_path(VisualNovel, id, "/vn")
  defp entity_path("character", id), do: slug_path(Character, id, "/character")
  defp entity_path("producer", id), do: slug_path(Producer, id, "/developer")
  defp entity_path("series", id), do: slug_path(Series, id, "/series")

  defp entity_path("user", id) do
    case safe_get(User, id) do
      %{username: username} when is_binary(username) -> "/@#{username}"
      _ -> nil
    end
  end

  defp entity_path("post", id) do
    case safe_get(Post, id) do
      %Post{} = post -> post_path(post)
      _ -> nil
    end
  end

  defp entity_path("post_comment", id) do
    case safe_get(Comment, id) |> Repo.preload(:post) do
      %{post: %Post{} = post} -> post_path(post)
      _ -> nil
    end
  end

  defp entity_path("review", id) do
    case safe_get(Review, id) |> Repo.preload([:user, :visual_novel]) do
      %Review{} = review -> review_path(review)
      _ -> nil
    end
  end

  defp entity_path("review_comment", id) do
    case safe_get(ReviewComment, id) |> Repo.preload(vn_review: [:user, :visual_novel]) do
      %{vn_review: %Review{} = review} -> review_path(review)
      _ -> nil
    end
  end

  defp entity_path("list", id) do
    case safe_get(List, id) |> Repo.preload(:user) do
      %List{} = list -> list_path(list)
      _ -> nil
    end
  end

  defp entity_path("list_comment", id) do
    case safe_get(ListComment, id) |> Repo.preload(list: :user) do
      %{list: %List{} = list} -> list_path(list)
      _ -> nil
    end
  end

  defp entity_path("release", id) do
    case safe_get(Release, id) |> Repo.preload(:visual_novel) do
      %{id: release_id, visual_novel: %{slug: slug}} when is_binary(slug) ->
        "/vn/#{slug}/release/#{release_id}/edit"

      _ ->
        nil
    end
  end

  defp entity_path(_type, _id), do: nil

  defp slug_path(schema, id, prefix) do
    case safe_get(schema, id) do
      %{slug: slug} when is_binary(slug) -> "#{prefix}/#{slug}"
      _ -> nil
    end
  end

  defp safe_get(_schema, id) when id in [nil, ""], do: nil

  defp safe_get(schema, id) do
    Repo.get(schema, id)
  rescue
    Ecto.Query.CastError -> nil
    ArgumentError -> nil
  end

  defp post_path(%Post{short_id: short_id} = post) when is_binary(short_id) do
    entity_post_path(post) || standalone_post_path(post)
  end

  defp post_path(_post), do: nil

  defp entity_post_path(%Post{
         category_type: category_type,
         entity_id: entity_id,
         short_id: short_id
       }) do
    case to_string(category_type) do
      "visual_novel" ->
        case safe_get(VisualNovel, entity_id) do
          %{slug: slug} when is_binary(slug) -> "/vn/#{slug}/discussions/#{short_id}"
          _ -> nil
        end

      "producer" ->
        case safe_get(Producer, entity_id) do
          %{slug: slug} when is_binary(slug) -> "/developer/#{slug}/discussions/#{short_id}"
          _ -> nil
        end

      "character" ->
        case safe_get(Character, entity_id) do
          %{slug: slug} when is_binary(slug) -> "/character/#{slug}/discussions/#{short_id}"
          _ -> nil
        end

      "user" ->
        case safe_get(User, entity_id) do
          %{username: username} when is_binary(username) ->
            "/users/#{username}/discussions/#{short_id}"

          _ ->
            nil
        end

      _ ->
        nil
    end
  end

  defp standalone_post_path(%Post{short_id: short_id, slug: slug}) do
    "/discussions/p/#{short_id}/#{slug || "post"}"
  end

  defp review_path(%Review{user: %{username: username}, visual_novel: %{slug: slug}})
       when is_binary(username) and is_binary(slug) do
    "/@#{username}/reviews/#{slug}"
  end

  defp review_path(_review), do: nil

  defp list_path(%List{user: %{username: username}, slug: slug})
       when is_binary(username) and is_binary(slug) do
    "/@#{username}/list/#{slug}"
  end

  defp list_path(_list), do: nil
end
