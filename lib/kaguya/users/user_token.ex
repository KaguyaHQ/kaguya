defmodule Kaguya.Users.UserToken do
  use Ecto.Schema

  import Ecto.Query

  alias Kaguya.Users.User
  alias Kaguya.Users.UserToken

  @hash_algorithm :sha256
  @rand_size 32
  @magic_link_validity_in_minutes 15
  @change_email_validity_in_days 7
  @session_validity_in_days 90

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "users_tokens" do
    field :token, :binary
    field :context, :string
    field :sent_to, :string
    field :authenticated_at, :utc_datetime

    belongs_to :user, User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def build_session_token(%User{} = user) do
    token = :crypto.strong_rand_bytes(@rand_size)
    authenticated_at = user.authenticated_at || DateTime.utc_now(:second)

    {token,
     %UserToken{
       token: token,
       context: "session",
       user_id: user.id,
       authenticated_at: authenticated_at
     }}
  end

  def verify_session_token_query(token) do
    query =
      from token in by_token_and_context_query(token, "session"),
        join: user in assoc(token, :user),
        where: token.inserted_at > ago(@session_validity_in_days, "day"),
        select: {%{user | authenticated_at: token.authenticated_at}, token.inserted_at}

    {:ok, query}
  end

  def build_email_token(%User{} = user, "change:" <> _ = context, sent_to)
      when is_binary(sent_to) do
    build_hashed_token(user, context, sent_to)
  end

  def build_email_token(%User{} = user, context) do
    build_hashed_token(user, context, user.email)
  end

  def verify_magic_link_token_query(token) do
    case decode_hashed_token(token) do
      {:ok, hashed_token} ->
        query =
          from token in by_token_and_context_query(hashed_token, "login"),
            join: user in assoc(token, :user),
            where: token.inserted_at > ago(^@magic_link_validity_in_minutes, "minute"),
            where: token.sent_to == user.email,
            select: {user, token}

        {:ok, query}

      :error ->
        :error
    end
  end

  def verify_change_email_token_query(token, "change:" <> _ = context) do
    case decode_hashed_token(token) do
      {:ok, hashed_token} ->
        query =
          from token in by_token_and_context_query(hashed_token, context),
            where: token.inserted_at > ago(@change_email_validity_in_days, "day")

        {:ok, query}

      :error ->
        :error
    end
  end

  def verify_change_email_token_query(token) do
    case decode_hashed_token(token) do
      {:ok, hashed_token} ->
        query =
          from token in UserToken,
            where: token.token == ^hashed_token,
            where: token.inserted_at > ago(@change_email_validity_in_days, "day"),
            where: like(token.context, "change:%")

        {:ok, query}

      :error ->
        :error
    end
  end

  defp build_hashed_token(%User{} = user, context, sent_to) do
    token = :crypto.strong_rand_bytes(@rand_size)
    hashed_token = :crypto.hash(@hash_algorithm, token)

    {Base.url_encode64(token, padding: false),
     %UserToken{
       token: hashed_token,
       context: context,
       sent_to: sent_to,
       user_id: user.id
     }}
  end

  defp decode_hashed_token(token) when is_binary(token) do
    case Base.url_decode64(token, padding: false) do
      {:ok, decoded_token} -> {:ok, :crypto.hash(@hash_algorithm, decoded_token)}
      :error -> :error
    end
  end

  defp decode_hashed_token(_), do: :error

  defp by_token_and_context_query(token, context) do
    from UserToken, where: [token: ^token, context: ^context]
  end
end
