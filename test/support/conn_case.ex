defmodule KaguyaWeb.ConnCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      @endpoint KaguyaWeb.Endpoint

      use KaguyaWeb, :verified_routes

      import Plug.Conn
      import Phoenix.ConnTest
      import Phoenix.LiveViewTest
      import KaguyaWeb.ConnCase
    end
  end

  setup tags do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Kaguya.Repo)

    unless tags[:async] do
      Ecto.Adapters.SQL.Sandbox.mode(Kaguya.Repo, {:shared, self()})
    end

    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end
