defmodule Kaguya.Auth do
  @moduledoc """
  Centralized auth operations.
  """

  import Ecto.Query

  alias Kaguya.Repo
  alias Kaguya.Users.{User, UserIdentity, UserNotifier, UserToken}
  require Logger

  @doc """
  Finds or creates the local app user that owns an email magic-link login.

  Phoenix-created users get an explicit UUID because `users.id` remains a
  preserved binary id and does not autogenerate in the schema.
  """
  def ensure_user_by_email(email) when is_binary(email) do
    email = normalize_email(email)

    cond do
      email == "" ->
        {:error, :invalid_email}

      user = Repo.get_by(User, email: email) ->
        {:ok, user}

      true ->
        attrs = %{
          id: Ecto.UUID.generate(),
          email: email,
          avatar_id: Kaguya.Images.random_default_avatar()
        }

        %User{}
        |> User.create_changeset(attrs)
        |> Repo.insert()
        |> case do
          {:ok, user} ->
            {:ok, user}

          {:error, _changeset} ->
            case Repo.get_by(User, email: email) do
              %User{} = user -> {:ok, user}
              nil -> {:error, "Failed to create or find user"}
            end
        end
    end
  end

  def ensure_user_by_email(_), do: {:error, :invalid_email}

  def login_user_by_google_profile(%{provider: "google", provider_uid: provider_uid} = profile)
      when is_binary(provider_uid) do
    case get_identity("google", provider_uid) do
      %UserIdentity{user: %User{} = user} ->
        {:ok, user}

      nil ->
        link_or_create_google_user(profile)
    end
  end

  def login_user_by_google_profile(_), do: {:error, :invalid_google_profile}

  def get_user_by_session_token(token) when is_binary(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  def get_user_by_session_token(_), do: nil

  def generate_user_session_token(%User{} = user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  def delete_user_session_token(token) when is_binary(token) do
    Repo.delete_all(from(UserToken, where: [token: ^token, context: "session"]))
    :ok
  end

  def delete_user_session_token(_), do: :ok

  def deliver_login_instructions(%User{} = user, magic_link_url_fun)
      when is_function(magic_link_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "login")
    Repo.insert!(user_token)
    UserNotifier.deliver_login_instructions(user, magic_link_url_fun.(encoded_token))
  end

  def login_user_by_magic_link(token) do
    with {:ok, query} <- UserToken.verify_magic_link_token_query(token),
         {%User{} = user, %UserToken{} = user_token} <- Repo.one(query) do
      Repo.delete!(user_token)
      {:ok, user}
    else
      _ -> {:error, :not_found}
    end
  end

  def deliver_update_email_instructions(%User{} = user, new_email, update_email_url_fun)
      when is_binary(new_email) and is_function(update_email_url_fun, 1) do
    new_email = normalize_email(new_email)

    {encoded_token, user_token} =
      UserToken.build_email_token(user, "change:#{user.email}", new_email)

    Repo.insert!(user_token)

    UserNotifier.deliver_update_email_instructions(
      user,
      new_email,
      update_email_url_fun.(encoded_token)
    )
  end

  def update_user_email_by_token(token) do
    with {:ok, query} <- UserToken.verify_change_email_token_query(token),
         %UserToken{} = user_token <- Repo.one(query) do
      update_user_email_from_token(user_token)
    else
      _ -> {:error, :not_found}
    end
  end

  defp update_user_email_from_token(%UserToken{} = user_token) do
    Repo.transact(fn ->
      with %User{} = user <- Repo.get(User, user_token.user_id),
           {:ok, updated_user} <-
             user
             |> User.changeset(%{email: user_token.sent_to})
             |> Repo.update(),
           {_count, _} <-
             Repo.delete_all(
               from t in UserToken,
                 where:
                   t.user_id == ^user.id and
                     (t.context == "login" or t.context == ^user_token.context)
             ) do
        {:ok, updated_user}
      else
        nil -> {:error, :not_found}
        {:error, reason} -> {:error, reason}
      end
    end)
  end

  @doc "Returns whether the user needs account setup (no username yet)."
  def needs_setup?(%User{username: nil}), do: true
  def needs_setup?(%User{username: ""}), do: true
  def needs_setup?(_), do: false

  defp link_or_create_google_user(profile) do
    email = normalize_email(profile[:email] || "")

    cond do
      email == "" ->
        {:error, :invalid_email}

      not profile[:email_verified] ->
        {:error, :email_not_verified}

      true ->
        with {:ok, user} <- ensure_user_by_email(email),
             :ok <- ensure_google_available_for_user(user.id),
             {:ok, _identity} <- insert_google_identity(user, Map.put(profile, :email, email)) do
          {:ok, user}
        else
          {:error, %Ecto.Changeset{} = changeset} ->
            recover_from_google_identity_conflict(profile, changeset)

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp get_identity(provider, provider_uid) do
    Repo.one(
      from i in UserIdentity,
        where: i.provider == ^provider and i.provider_uid == ^provider_uid,
        preload: [:user]
    )
  end

  defp ensure_google_available_for_user(user_id) do
    case Repo.get_by(UserIdentity, user_id: user_id, provider: "google") do
      nil -> :ok
      %UserIdentity{} -> {:error, :provider_already_linked}
    end
  end

  defp insert_google_identity(%User{} = user, profile) do
    %UserIdentity{user_id: user.id}
    |> UserIdentity.google_changeset(%{
      provider: "google",
      provider_uid: profile.provider_uid,
      email: profile.email,
      email_verified: profile.email_verified,
      name: profile[:name],
      avatar_url: profile[:avatar_url]
    })
    |> Repo.insert()
  end

  defp recover_from_google_identity_conflict(profile, changeset) do
    cond do
      unique_error?(changeset, :provider_uid) ->
        case get_identity("google", profile.provider_uid) do
          %UserIdentity{user: %User{} = user} -> {:ok, user}
          _ -> {:error, :provider_already_linked}
        end

      unique_error?(changeset, :provider) ->
        {:error, :provider_already_linked}

      true ->
        {:error, changeset}
    end
  end

  defp unique_error?(%Ecto.Changeset{} = changeset, field) do
    Enum.any?(changeset.errors, fn
      {^field, {_message, opts}} -> opts[:constraint] == :unique
      _ -> false
    end)
  end

  defp normalize_email(email) do
    email
    |> String.trim()
    |> String.downcase()
  end
end
