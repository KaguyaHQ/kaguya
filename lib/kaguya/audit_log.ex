defmodule Kaguya.AuditLog do
  @moduledoc """
  Logs all moderator and admin actions for auditing.
  """

  import Ecto.Query
  alias Kaguya.Repo
  alias Kaguya.AuditLog.Entry

  @doc """
  Records a mod/admin action.
  """
  def log(user_id, action, target_type, target_id, details \\ nil) do
    %Entry{}
    |> Entry.changeset(%{
      user_id: user_id,
      action: action,
      target_type: target_type,
      target_id: target_id,
      details: details
    })
    |> Repo.insert()
  end

  @doc """
  List audit log entries with optional filters.
  """
  def list(opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    page_size = Keyword.get(opts, :page_size, 50)

    query =
      from(e in Entry,
        order_by: [desc: e.inserted_at],
        preload: [:user]
      )
      |> maybe_filter_user(Keyword.get(opts, :user_id))
      |> maybe_filter_target(Keyword.get(opts, :target_type), Keyword.get(opts, :target_id))
      |> maybe_filter_action(Keyword.get(opts, :action))

    {entries, pagination} = Kaguya.Pagination.paginate(query, page, page_size)
    {:ok, %{items: entries, pagination: pagination}}
  end

  defp maybe_filter_user(query, nil), do: query
  defp maybe_filter_user(query, uid), do: where(query, [e], e.user_id == ^uid)

  defp maybe_filter_target(query, nil, _), do: query
  defp maybe_filter_target(query, type, nil), do: where(query, [e], e.target_type == ^type)

  defp maybe_filter_target(query, type, id),
    do: where(query, [e], e.target_type == ^type and e.target_id == ^id)

  defp maybe_filter_action(query, nil), do: query
  defp maybe_filter_action(query, action), do: where(query, [e], e.action == ^action)
end
