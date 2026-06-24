defmodule Kaguya.RateLimit do
  @moduledoc """
  Global ETS-backed rate limiter for Kaguya using Hammer.
  """

  use Hammer, backend: :ets
end
