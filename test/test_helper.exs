excluded_tags =
  case :os.type() do
    {:win32, _} -> [requires_image: true]
    _ -> []
  end

ExUnit.start(exclude: excluded_tags)
Ecto.Adapters.SQL.Sandbox.mode(Kaguya.Repo, :manual)
