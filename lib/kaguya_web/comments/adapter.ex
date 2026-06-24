defmodule KaguyaWeb.Comments.Adapter do
  @moduledoc """
  Behaviour for LiveView comment resources.

  Adapters keep the reusable comments component independent from a specific
  context while still using Phoenix contexts directly for mutations.
  """

  @type resource_id :: binary()
  @type user :: map() | nil
  @type comment :: map()
  @type pagination :: map()

  @callback resource_type() :: atom()
  @callback load(resource_id(), user(), map()) ::
              {:ok,
               %{items: [comment()], pagination: pagination(), comments_count: non_neg_integer()}}
              | {:error, term()}
  @callback create(resource_id(), user(), map()) :: {:ok, comment()} | {:error, term()}
  @callback update(binary(), user(), map()) :: {:ok, comment()} | {:error, term()}
  @callback delete(binary(), user()) :: {:ok, true} | {:error, term()}
  @callback like(binary(), user()) :: {:ok, true} | {:error, term()}
  @callback unlike(binary(), user()) :: {:ok, true} | {:error, term()}
  @callback hide(binary(), user(), map()) :: {:ok, non_neg_integer()} | {:error, term()}
  @callback unhide(binary(), user()) :: {:ok, non_neg_integer()} | {:error, term()}
  @callback can_comment?(resource_id(), user()) :: boolean()
  @callback can_moderate?(user()) :: boolean()

  @doc """
  Pin a comment. Only adapters that surface pinnable comments (currently
  post comments) implement this; others can leave it unimplemented and the
  comments component will hide the Pin action.
  """
  @callback pin(binary(), user()) :: {:ok, map()} | {:error, term()}
  @callback unpin(binary(), user()) :: {:ok, map()} | {:error, term()}

  @optional_callbacks pin: 2, unpin: 2
end
