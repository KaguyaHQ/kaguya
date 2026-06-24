defmodule Kaguya.Users.UsernameGenerator do
  @moduledoc """
  Builds sanitized, unique-friendly usernames for new users.
  """

  import Ecto.Query, only: [from: 2]

  alias Kaguya.Repo
  alias Kaguya.Users.User

  @max_length 30
  @min_length 3
  @default_base "reader"
  @max_attempts 100
  @numeric_suffix_limit 50

  @doc """
  Returns `true` when the incoming attrs already include a non-empty username.
  Accepts both atom and string keys.
  """
  def username_present?(attrs) when is_map(attrs) do
    case get_attr(attrs, :username) do
      value when is_binary(value) and value != "" -> true
      _ -> false
    end
  end

  @doc """
  Produces a sanitized base segment from the provided attributes. Prefers
  `display_name`, falling back to the email's local part. Ensures the base
  respects the username character rules and minimum length requirements.
  """
  def base_segment(attrs) when is_map(attrs) do
    attrs
    |> preferred_source()
    |> sanitize_source()
    |> ensure_min_length()
  end

  @doc """
  Builds a candidate username using the sanitized base and the given attempt
  number. Attempt zero yields the raw base. Subsequent attempts append numeric
  or random suffixes while respecting the 30-character limit.
  """
  def candidate(base, attempt \\ 0) when is_binary(base) and attempt >= 0 do
    suffix = suffix_for_attempt(attempt)

    base
    |> truncate_for_suffix(suffix)
    |> trim_extra_underscores()
    |> append_suffix(suffix)
    |> maybe_fallback_when_blank()
  end

  @doc """
  Returns `true` when the username is already taken (case-insensitive due to citext).
  """
  def taken?(username) when is_binary(username) do
    from(u in User, where: u.username == ^username, select: 1)
    |> Repo.exists?()
  end

  @doc """
  Detects whether the changeset failure is a username unique-constraint violation.
  """
  def unique_constraint_error?(%Ecto.Changeset{errors: errors}) do
    Enum.any?(errors, fn
      {:username, {_message, opts}} ->
        Keyword.get(opts, :constraint) == :unique or
          Keyword.get(opts, :constraint_name) in ["users_username_index", "users_username_key"]

      _ ->
        false
    end)
  end

  def unique_constraint_error?(_), do: false

  @doc """
  Upper bound for generation retries before switching to random suffixes.
  """
  def max_attempts, do: @max_attempts

  # -- internal helpers ------------------------------------------------------

  defp get_attr(attrs, key) do
    Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key))
  end

  defp preferred_source(attrs) do
    case display_name_source(attrs) do
      nil ->
        attrs
        |> get_attr(:email)
        |> email_local_part()

      source ->
        source
    end
  end

  defp display_name_source(attrs) do
    attrs
    |> get_attr(:display_name)
    |> case do
      value when is_binary(value) ->
        trimmed = String.trim(value)

        if String.length(trimmed) >= 3 do
          trimmed
        else
          nil
        end

      _ ->
        nil
    end
  end

  defp email_local_part(email) when is_binary(email) do
    email
    |> String.split("@", parts: 2)
    |> List.first()
    |> to_string()
  end

  defp email_local_part(_), do: nil

  defp sanitize_source(nil), do: @default_base

  defp sanitize_source(source) when is_binary(source) do
    source
    |> String.trim()
    |> Slug.slugify(separator: "_")
    |> case do
      nil -> @default_base
      "" -> @default_base
      slug -> slug
    end
  end

  defp ensure_min_length(base) when byte_size(base) >= @min_length, do: base

  defp ensure_min_length(base) when base == @default_base, do: base

  defp ensure_min_length(base) do
    combined = "#{base}_#{@default_base}"

    if byte_size(combined) >= @min_length do
      combined
    else
      @default_base
    end
  end

  defp suffix_for_attempt(0), do: ""

  defp suffix_for_attempt(attempt) when attempt <= @numeric_suffix_limit do
    "_#{attempt + 1}"
  end

  defp suffix_for_attempt(_attempt) do
    suffix =
      System.unique_integer([:positive])
      |> Integer.to_string()
      |> String.slice(0, 6)

    "_" <> suffix
  end

  defp truncate_for_suffix(base, suffix) do
    max_len = max(@max_length - byte_size(suffix), 1)
    base |> String.slice(0, max_len)
  end

  defp trim_extra_underscores(base) do
    base
    |> String.replace(~r/_+/, "_")
    |> String.trim("_")
  end

  defp append_suffix("", suffix), do: append_suffix(@default_base, suffix)
  defp append_suffix(base, suffix), do: base <> suffix

  defp maybe_fallback_when_blank(result) do
    result
    |> case do
      "" -> @default_base
      value -> value
    end
  end
end
