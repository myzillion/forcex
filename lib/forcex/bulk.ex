defmodule Forcex.Bulk do
  use HTTPoison.Base
  require Logger

  @user_agent [{"User-agent", "forcex"}]
  @accept [{"Accept", "application/json"}]
  @accept_encoding [{"Accept-Encoding", "gzip"}]
  @content_type [{"Content-Type", "application/json"}]
  #  @pk_chunking [{"Sforce-Enable-PKChunking", "chunkSize=50000"}]

  @type id :: binary
  @type job :: map
  @type batch :: map

  def process_request_headers(headers), do: headers ++ @user_agent ++ @accept ++ @accept_encoding ++ @content_type

  def process_headers(headers), do: Map.new(headers)

  def process_response(%HTTPoison.Response{body: body, headers: %{"Content-Encoding" => "gzip"} = headers } = resp) do
    %{resp | body: :zlib.gunzip(body), headers: Map.drop(headers, ["Content-Encoding"])}
    |> process_response
  end
  def process_response(%HTTPoison.Response{body: body, headers: %{"Content-Type" => "application/json" <> _} = headers} = resp) do
    %{resp | body: Jason.decode!(body, keys: :atoms), headers: Map.drop(headers, ["Content-Type"])}
    |> process_response
  end
  def process_response(%HTTPoison.Response{body: body, status_code: status}) when status < 300 and status >= 200, do: body
  def process_response(%HTTPoison.Response{body: body, status_code: status}), do: {status, body}

  defp extra_options() do
    Application.get_env(:forcex, :request_options, [])
  end

  defp authorization_header(%{session_id: nil}), do: []
  defp authorization_header(%{session_id: session}) do
    [{"X-SFDC-Session", session}]
  end

  def json_request(method, url, body, headers, options) do
    raw_request(method, url, Jason.encode!(body), headers, options)
  end

  def raw_request(method, url, body, headers, options) do
    request!(method, url, body, headers, extra_options() ++ options) |> process_response
  end

  def get(path, headers \\ [], client) do
    url = "https://#{client.host}/services/async/#{client.api_version}" <> path
    raw_request(:get, url, "", headers ++ authorization_header(client), [])
  end

  def post(path, body \\ "", client) do
    url = "https://#{client.host}/services/async/#{client.api_version}" <> path
    json_request(:post, url, body, authorization_header(client), [])
  end

  @spec create_query_job(binary, map) :: job
  def create_query_job(sobject, client) do
    payload = %{"operation" => "query", "object" => sobject, "concurrencyMode" => "Parallel", "contentType" => "JSON"}
    post("/job", payload, client)
  end

  @spec close_job(job | id, map) :: job
  def close_job(job, client) when is_map(job) do
    close_job(job.id, client)
  end
  def close_job(id, client) when is_binary(id) do
    post("/job/#{id}", %{"state" => "Closed"}, client)
  end

  @spec fetch_job_status(job | id, map) :: job
  def fetch_job_status(job, client) when is_map(job), do: fetch_job_status(job.id, client)
  def fetch_job_status(id, client) when is_binary(id) do
    get("/job/#{id}", client)
  end

  @spec create_query_batch(String.t, job | id, map) :: job
  def create_query_batch(soql, job, client) when is_map(job), do: create_query_batch(soql, job.id, client)
  def create_query_batch(soql, job_id, client) when is_binary(soql) and is_binary(job_id) do
    url = "https://#{client.host}/services/async/#{client.api_version}" <> "/job/#{job_id}/batch"
    raw_request(:post, url, soql, authorization_header(client), [])
  end

  @spec fetch_batch_status(batch, map) :: batch
  def fetch_batch_status(batch, client) when is_map(batch) do
    fetch_batch_status(batch.id, batch.jobId, client)
  end
  @spec fetch_batch_status(id, job | id, map) :: batch
  def fetch_batch_status(id, job, client) when is_binary(id) and is_map(job) do
    fetch_batch_status(id, job.id, client)
  end
  def fetch_batch_status(id, job_id, client) when is_binary(id) and is_binary(job_id) do
    get("/job/#{job_id}/batch/#{id}", client)
  end

  @spec fetch_batch_result_status(batch, map) :: list(String.t)
  def fetch_batch_result_status(batch, client) when is_map(batch) do
    fetch_batch_result_status(batch.id, batch.jobId, client)
  end
  @spec fetch_batch_result_status(id, id, map) :: list(String.t)
  def fetch_batch_result_status(batch_id, job_id, client)  when is_binary(batch_id) and is_binary(job_id) do
    get("/job/#{job_id}/batch/#{batch_id}/result", client)
  end

  @spec fetch_results(id, batch, map) :: list(map)
  def fetch_results(id, batch, client) when is_binary(id) and is_map(batch) do
    fetch_results(id, batch.id, batch.jobId, client)
  end
  @spec fetch_results(id, id, id, map) :: list(map)
  def fetch_results(id, batch_id, job_id, client) when is_binary(id) and is_binary(batch_id) and is_binary(job_id) do
    get("/job/#{job_id}/batch/#{batch_id}/result/#{id}", client)
  end

end
