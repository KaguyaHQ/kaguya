defmodule Mix.Tasks.Kaguya.GenerateRecommendations do
  @moduledoc """
  Generate personalized VN recommendations for eligible users.

  Runs `Kaguya.Recommendations.GenerateWorker.perform/1` directly in this mix
  task's process — does NOT enqueue via Oban. That's intentional for dev/CLI
  use: skipping the queue avoids the multi-BEAM coordination issue you hit
  when your phx.server is on one port and you run a mix task in a separate
  shell on another. The same worker code runs either way; production uses
  Oban via the weekly cron, which works fine because there's only one BEAM.

  Usage:

      mix kaguya.generate_recommendations              # all eligible users (~60s)
      mix kaguya.generate_recommendations --user vas   # one user (~5s)

  Options:
      --user USERNAME     Limit to one user (by username)
      --n-final N         Recs per user (default 50)
  """
  use Mix.Task

  @requirements ["app.start"]
  @shortdoc "Generate VN recommendations (runs synchronously, no Oban)"

  import Ecto.Query

  alias Kaguya.Recommendations
  alias Kaguya.Recommendations.GenerateWorker
  alias Kaguya.Repo
  alias Kaguya.Users.User

  @impl Mix.Task
  def run(argv) do
    # Don't start the web server - allows running alongside `mix phx.server`
    Application.put_env(:kaguya, KaguyaWeb.Endpoint, server: false)

    {opts, _, _} =
      OptionParser.parse(argv, strict: [user: :string, n_final: :integer])

    args = %{"n_final" => Keyword.get(opts, :n_final, 50)}

    args =
      case Keyword.get(opts, :user) do
        nil ->
          eligible = Recommendations.list_eligible_user_ids()

          IO.puts(
            "Generating for #{length(eligible)} eligible users (method: #{Recommendations.method()})."
          )

          IO.puts("Expect ~#{round(length(eligible) * 0.07)}s.")
          Map.put(args, "user_ids", eligible)

        username ->
          user_id = lookup_user_id!(username)
          IO.puts("Generating for @#{username} (method: #{Recommendations.method()}).")
          Map.put(args, "user_ids", [user_id])
      end

    {elapsed_us, result} =
      :timer.tc(fn -> GenerateWorker.perform(%Oban.Job{args: args}) end)

    print_result(result, elapsed_us)
  end

  defp print_result({:ok, :no_eligible_users}, _t) do
    IO.puts("Nothing to do — no users have ≥3 rating-like signals yet.")
  end

  defp print_result({:ok, {:ok, multi}}, elapsed_us) do
    n =
      Enum.reduce(multi, 0, fn
        {{:insert, _}, {n, _}}, acc -> acc + n
        _, acc -> acc
      end)

    IO.puts("\nDone in #{div(elapsed_us, 1_000_000)}s — #{n} rows inserted.")
  end

  defp print_result({:ok, {:error, msg}}, _t) do
    IO.puts("ERROR — #{String.slice(to_string(msg), 0, 400)}")
  end

  defp print_result(other, _t) do
    IO.inspect(other, label: "unexpected result")
  end

  defp lookup_user_id!(username) do
    username = String.trim_leading(username, "@")

    case Repo.one(from u in User, where: u.username == ^username, select: u.id) do
      nil -> Mix.raise("No user with username #{username}")
      id -> id
    end
  end
end
