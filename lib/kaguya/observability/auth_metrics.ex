defmodule Kaguya.Observability.AuthMetrics do
  @moduledoc "Bounded outcome metrics for Turnstile verification and login-email requests."
  use PromEx.Plugin

  @impl true
  def event_metrics(_opts) do
    [
      Event.build(:auth_email, [
        counter([:kaguya, :prom_ex, :auth, :email, :requests, :total],
          event_name: [:kaguya, :auth, :email, :request],
          tags: [:result, :reason],
          description: "Login-email send and rejection outcomes."
        )
      ]),
      Event.build(:auth_turnstile, [
        counter([:kaguya, :prom_ex, :auth, :turnstile, :requests, :total],
          event_name: [:kaguya, :auth, :turnstile, :stop],
          tags: [:result, :reason],
          description: "Turnstile verification outcomes."
        ),
        distribution([:kaguya, :prom_ex, :auth, :turnstile, :duration, :milliseconds],
          event_name: [:kaguya, :auth, :turnstile, :stop],
          measurement: :duration,
          unit: {:native, :millisecond},
          tags: [:result],
          reporter_options: [buckets: [50, 100, 250, 500, 1000, 2500, 5000]],
          description: "Turnstile verification duration."
        )
      ])
    ]
  end
end
