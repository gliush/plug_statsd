defmodule Plug.Statsd do
  require Logger

  @sample_rate Application.get_env(:plug_statsd, :sample_rate, 1)
  @timing_sample_rate Application.get_env(:plug_statsd, :timing_sample_rate, @sample_rate)
  @request_sample_rate Application.get_env(:plug_statsd, :request_sample_rate, @sample_rate)
  @response_sample_rate Application.get_env(:plug_statsd, :response_sample_rate, @sample_rate)
  @slash_replacement Application.get_env(:plug_statsd, :slash_replacement, ".")
  @period_replacement Application.get_env(:plug_statsd, :period_replacement, "_")

  def init(opts), do: Keyword.merge(default_options, opts)
  def call(conn, opts) do
    before_time = :os.timestamp()

    conn
    |> Plug.Conn.register_before_send( fn conn ->
      after_time = :os.timestamp()
      diff = div(:timer.now_diff(after_time, before_time), 1000)
      send_metrics(conn, opts, diff)
      end)
  end

  def uri(conn, opts) do
    Plug.Conn.full_path(conn)
    |> sanitize_uri(opts)
  end

  defp sanitize_uri("/", opts) do
    "[root]"
  end
  defp sanitize_uri("/"<>uri, opts) do
    period_replacement = Keyword.get(opts, :period_replacement)
    slash_replacement = Keyword.get(opts, :slash_replacement)

    uri
    |> String.replace(".", period_replacement)
    |> String.replace("/", slash_replacement)
  end
  defp default_options do
    [ sample_rate: @sample_rate,
      timing_sample_rate: @timing_sample_rate,
      request_sample_rate: @request_sample_rate,
      response_sample_rate: @response_sample_rate,
      slash_replacement: @slash_replacement,
      period_replacement: @period_replacement,
    ]
  end

  defp generalized_response_code(code) when is_integer(code), do: "#{div(code, 100)}xx"
  defp generalized_response_code(_code), do: "UNKNOWN"

  defp metric_name(:response, conn, opts) do
    [:response, generalized_response_code(conn.status), conn.status, conn.method, uri(conn, opts)]
    |> List.flatten
    |> Enum.join(".")
  end
  defp metric_name(type, conn, opts) do
    [type, conn.method, uri(conn, opts)]
    |> List.flatten
    |> Enum.join(".")
  end

  defp send_metrics(conn, opts, delay) do
    [:timing, :request, :response ]
    |> Enum.each( fn (type) -> send_metric(type, conn, opts, delay) end)
    conn
  end

  defp sample_rate(opts, type) do
    Keyword.get(opts, String.to_atom("#{type}_sample_rate"), Keyword.get(opts, :sample_rate))
  end

  defp send_metric(type = :timing, conn, opts, delay) do
    name = metric_name(type, conn, opts)
    ExStatsD.timer(delay, name, sample_rate: sample_rate(opts, type))
  end
  defp send_metric(type, conn, opts, _timing) do
    type
    |> metric_name(conn, opts)
    |> ExStatsD.increment(sample_rate: sample_rate(opts, type))
  end
end
