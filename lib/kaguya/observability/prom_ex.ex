defmodule Kaguya.Observability.PromEx do
  @moduledoc """
  Prometheus metrics for Grafana Cloud dashboards.

  Exposes metrics for:
  - BEAM VM (memory, CPU, processes, schedulers, GC)
  - Phoenix (request duration, count by endpoint)
  - Ecto (query time, pool checkout wait)
  - Oban (queue depth)

  Alloy filters control which metrics reach Grafana Cloud (see config.alloy).
  """

  use PromEx, otp_app: :kaguya

  alias PromEx.Plugins

  @impl true
  def plugins do
    [
      # BEAM VM metrics - memory, processes, GC (system info/limits dropped by Alloy)
      Plugins.Beam,

      # Phoenix request metrics
      {Plugins.Phoenix, router: KaguyaWeb.Router, endpoint: KaguyaWeb.Endpoint},

      # Ecto metrics - query time, queue time (idle/decode/total dropped by Alloy)
      {Plugins.Ecto, repos: [Kaguya.Repo]},

      # Oban - only queue_length_count forwarded by Alloy (job histograms dropped)
      {Plugins.Oban, oban_supervisors: [Oban]}
    ]
  end

  @impl true
  def dashboard_assigns do
    [
      datasource_id: "prometheus",
      default_selected_interval: "30s"
    ]
  end

  @impl true
  def dashboards do
    [
      {:prom_ex, "beam.json"},
      {:prom_ex, "phoenix.json"},
      {:prom_ex, "ecto.json"},
      {:prom_ex, "oban.json"}
    ]
  end
end
