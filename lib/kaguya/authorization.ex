defmodule Kaguya.Authorization do
  @moduledoc """
  Role and capability checks shared between server-side write paths and
  LiveView/render-side gates. Centralized so the security boundary lives in
  one place — see `lib/kaguya/revisions.ex` for the enforcement that
  ultimately matters.
  """

  @doc """
  Returns true when the user can moderate the canonical database
  (hide/unhide/lock/unlock entities, edit hidden or locked entries).

  Accepts both atom roles (`:moderator`, `:admin`) and the string forms that
  may flow in from older session payloads.
  """
  def can_moderate_db?(%{mod_db: true}), do: true

  def can_moderate_db?(%{role: role})
      when role in [:moderator, :admin, "moderator", "admin"],
      do: true

  def can_moderate_db?(_), do: false
end
