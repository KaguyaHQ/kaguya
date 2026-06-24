defmodule Kaguya.SentryFilterTest do
  use ExUnit.Case, async: true

  alias Kaguya.Observability.SentryFilter
  alias Sentry.Event
  alias Sentry.Interfaces.Exception, as: SentryException
  alias Sentry.Interfaces.Request

  defp base do
    %Event{
      event_id: Sentry.UUID.uuid4_hex(),
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  describe "before_send/1" do
    test "drops events whose original_exception is in the ignore list" do
      assert SentryFilter.before_send(%{
               base()
               | original_exception: %Phoenix.Router.NoRouteError{conn: nil, router: nil}
             }) ==
               nil

      assert SentryFilter.before_send(%{
               base()
               | original_exception: %Ecto.NoResultsError{message: "x"}
             }) ==
               nil
    end

    test "always passes events tagged critical=true" do
      crit = %{
        base()
        | tags: %{"critical" => "true"},
          original_exception: %RuntimeError{message: "x"}
      }

      # Run several times to make sure the sample-rate gate doesn't trip it.
      for _ <- 1..50 do
        assert %Event{} = SentryFilter.before_send(crit)
      end
    end

    test "scrubs sensitive request fields before sending" do
      event = %{
        base()
        | tags: %{"critical" => "true"},
          request: %Request{
            data: %{
              "email" => "reader@example.com",
              "password" => "secret",
              "profile" => %{"recovery_email" => "backup@example.com"},
              "safe" => "value"
            },
            query_string: "email=reader%40example.com&return_to=%2F"
          }
      }

      assert %Event{} = event = SentryFilter.before_send(event)
      assert event.request.data["email"] == "[Filtered]"
      assert event.request.data["password"] == "[Filtered]"
      assert event.request.data["profile"]["recovery_email"] == "[Filtered]"
      assert event.request.data["safe"] == "value"
      assert event.request.query_string == "email=[Filtered]&return_to=%2F"
    end

    test "samples browse DB pool exhaustion at roughly 0.1%" do
      kept =
        for event_id <- deterministic_event_ids(10_000) do
          event =
            base()
            |> Map.put(:event_id, event_id)
            |> Map.put(:original_exception, db_pool_exception())
            |> Map.put(:request, %Request{url: "https://kaguya.io/browse?tags=kinetic-novel"})

          case SentryFilter.before_send(event) do
            nil -> 0
            %Event{} -> 1
          end
        end
        |> Enum.sum()

      assert kept > 0
      assert kept < 30
    end

    test "samples non-browse DB pool exhaustion at roughly 1%" do
      kept =
        for event_id <- deterministic_event_ids(10_000) do
          event =
            base()
            |> Map.put(:event_id, event_id)
            |> Map.put(:original_exception, db_pool_exception())
            |> Map.put(:request, %Request{url: "https://kaguya.io/vn/swan-song"})

          case SentryFilter.before_send(event) do
            nil -> 0
            %Event{} -> 1
          end
        end
        |> Enum.sum()

      assert kept > 50
      assert kept < 150
    end

    test "detects DB pool exhaustion from serialized Sentry exception interfaces" do
      event = %{
        base()
        | event_id: sampled_event_id(0.01),
          exception: [
            %SentryException{
              type: "DBConnection.ConnectionError",
              value:
                "[Elixir.Kaguya.Repo] connection not available and request was dropped from queue after 112ms"
            }
          ],
          request: %Request{url: "https://kaguya.io/vn/swan-song"}
      }

      assert %Event{} = SentryFilter.before_send(event)
    end

    test "critical DB pool exhaustion bypasses route-specific sampling" do
      event = %{
        base()
        | event_id: unsampled_event_id(0.001),
          tags: %{"critical" => "true"},
          original_exception: db_pool_exception(),
          request: %Request{url: "https://kaguya.io/browse?tags=kinetic-novel"}
      }

      assert %Event{} = SentryFilter.before_send(event)
    end

    test "samples non-critical events at roughly 25%" do
      event = %{base() | tags: %{}, original_exception: %RuntimeError{message: "noise"}}

      kept =
        for _ <- 1..2000 do
          case SentryFilter.before_send(event) do
            nil -> 0
            %Event{} -> 1
          end
        end
        |> Enum.sum()

      # ~25% with a tolerance band. Bernoulli with n=2000 has stdev ≈ 19,
      # so ±150 is well outside chance.
      assert kept > 350 and kept < 650, "sampled rate out of band: #{kept}/2000"
    end
  end

  defp db_pool_exception do
    %DBConnection.ConnectionError{
      message:
        "[Elixir.Kaguya.Repo] connection not available and request was dropped from queue after 112ms"
    }
  end

  defp deterministic_event_ids(count) do
    for n <- 1..count, do: String.pad_leading(Integer.to_string(n, 16), 32, "0")
  end

  defp sampled_event_id(rate) do
    deterministic_event_ids(50_000)
    |> Enum.find(&(sampled?(&1, rate) == true))
  end

  defp unsampled_event_id(rate) do
    deterministic_event_ids(50_000)
    |> Enum.find(&(sampled?(&1, rate) == false))
  end

  defp sampled?(event_id, rate) do
    threshold = trunc(rate * 10_000)
    :erlang.phash2(event_id, 10_000) < threshold
  end
end
