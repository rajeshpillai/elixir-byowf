defmodule Ignite.Adapters.Cowboy do
  @moduledoc """
  Bridges Cowboy's request format with Ignite's %Conn{} struct.

  Cowboy calls `init/2` for every HTTP request. We convert the Cowboy
  request into an %Ignite.Conn{}, run it through the router, and send
  the response back through Cowboy.
  """

  @behaviour :cowboy_handler

  require Logger

  @impl true
  def init(req, state) do
    # Generate a unique request ID for log correlation and tracing.
    # 16 random bytes → base64url gives a short, URL-safe identifier.
    request_id = :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)

    # Attach request_id to Logger metadata so ALL downstream Logger calls
    # in this process automatically include it — no explicit passing needed.
    Logger.metadata(request_id: request_id)

    # Start the timer — monotonic_time is immune to clock adjustments.
    start_time = System.monotonic_time()

    # Build conn outside the try so it's available in the rescue block
    # for the debug error page to display request context.
    conn = cowboy_to_conn(req)
    conn = put_in(conn.private[:request_id], request_id)

    Logger.info("#{conn.method} #{conn.path}")

    req =
      try do
        # 1. Route through our framework
        conn = MyApp.Router.call(conn)

        # 2. Set session cookie via Cowboy's cookie API
        #    conn.session contains only NEW flash (if put_flash was called).
        #    Inherited flash was already popped into conn.private in cowboy_to_conn.
        cookie_value = Ignite.Session.encode(conn.session)

        req =
          :cowboy_req.set_resp_cookie(
            Ignite.Session.cookie_name(),
            cookie_value,
            req,
            %{path: "/", http_only: true, same_site: :lax}
          )

        # 3. Add request ID to response headers for client-side correlation
        resp_headers = Map.put(conn.resp_headers, "x-request-id", request_id)

        # 4. Log the completion with timing
        duration = log_duration(start_time)
        Logger.info("Sent #{conn.status} in #{duration}")

        # 5. Send response back through Cowboy
        :cowboy_req.reply(conn.status, resp_headers, conn.resp_body, req)
      rescue
        exception ->
          duration = log_duration(start_time)

          # Log the error with full stacktrace for debugging
          Logger.error("""
          [Ignite] Request crashed (#{duration}):
          #{Exception.format(:error, exception, __STACKTRACE__)}
          """)

          # Render a debug error page (rich in dev, generic in prod)
          :cowboy_req.reply(
            500,
            %{"content-type" => "text/html", "x-request-id" => request_id},
            Ignite.DebugPage.render(exception, __STACKTRACE__, conn),
            req
          )
      end

    {:ok, req, state}
  end

  # Calculates elapsed time since `start_time` and formats it as a human-readable string.
  # Uses native time units for maximum precision, then converts to the most appropriate unit.
  defp log_duration(start_time) do
    diff = System.monotonic_time() - start_time
    micro = System.convert_time_unit(diff, :native, :microsecond)

    cond do
      micro < 1_000 -> "#{micro}µs"
      micro < 1_000_000 -> "#{Float.round(micro / 1_000, 1)}ms"
      true -> "#{Float.round(micro / 1_000_000, 2)}s"
    end
  end

  defp cowboy_to_conn(req) do
    # Read the body if present (POST/PUT/PATCH)
    {body_params, _req} = read_cowboy_body(req)

    # Convert Cowboy headers (list of tuples) to a map
    headers =
      req.headers
      |> Enum.into(%{}, fn {k, v} -> {String.downcase(k), v} end)

    # Parse cookies from the Cookie header
    cookies = Ignite.Session.parse_cookies(Map.get(headers, "cookie"))

    # Decode session from the signed session cookie
    raw_session =
      case Ignite.Session.decode(Map.get(cookies, Ignite.Session.cookie_name())) do
        {:ok, data} -> data
        :error -> %{}
      end

    # Pop flash from session → store in private for get_flash to read.
    # This gives us one-time semantics: the flash is available to the controller
    # via get_flash, but won't be echoed back unless put_flash is called again.
    {flash, session} = Map.pop(raw_session, "_flash", %{})

    # Ensure a CSRF token exists in the session.
    # Generated once per session, reused until the session expires.
    session =
      if Map.has_key?(session, "_csrf_token") do
        session
      else
        Map.put(session, "_csrf_token", Ignite.CSRF.generate_token())
      end

    # Extract the peer (client) IP address from Cowboy for rate limiting.
    # :cowboy_req.peer/1 returns {{a,b,c,d}, port} for IPv4.
    {peer_ip_tuple, _peer_port} = :cowboy_req.peer(req)
    peer_ip = peer_ip_tuple |> :inet.ntoa() |> to_string()

    %Ignite.Conn{
      method: req.method,
      path: req.path,
      headers: headers,
      params: body_params,
      cookies: cookies,
      session: session,
      private: %{flash: flash, peer_ip: peer_ip}
    }
  end

  defp read_cowboy_body(req) do
    case :cowboy_req.has_body(req) do
      true ->
        content_type = :cowboy_req.header("content-type", req, "")

        if String.starts_with?(content_type, "multipart/form-data") do
          read_multipart(req, %{})
        else
          {:ok, body, req} = :cowboy_req.read_body(req)
          {parse_body(body, content_type), req}
        end

      false ->
        {%{}, req}
    end
  end

  # --- Multipart parsing ---

  # Loops through all parts of a multipart/form-data request.
  # File parts are streamed to disk as %Ignite.Upload{} structs.
  # Regular fields are stored as strings.
  defp read_multipart(req, params) do
    case :cowboy_req.read_part(req) do
      {:ok, headers, req} ->
        {name, filename} = parse_disposition(headers)

        if filename do
          # File part — stream to temp file
          {:ok, tmp_path} = Ignite.Upload.random_file("multipart")
          Ignite.Upload.schedule_cleanup(tmp_path)
          {:ok, file} = File.open(tmp_path, [:write, :binary, :raw])
          {:ok, req} = read_part_body_to_file(req, file)
          File.close(file)

          upload_content_type =
            case Map.get(headers, "content-type") do
              nil -> "application/octet-stream"
              ct -> ct
            end

          upload = %Ignite.Upload{
            path: tmp_path,
            filename: filename,
            content_type: upload_content_type
          }

          read_multipart(req, Map.put(params, name, upload))
        else
          # Regular field — read body as string
          {:ok, body, req} = :cowboy_req.read_part_body(req)
          read_multipart(req, Map.put(params, name, body))
        end

      {:done, req} ->
        {params, req}
    end
  end

  # Streams part body chunks to a file handle.
  # Cowboy returns {:more, data, req} for large bodies.
  defp read_part_body_to_file(req, file) do
    case :cowboy_req.read_part_body(req) do
      {:ok, data, req} ->
        IO.binwrite(file, data)
        {:ok, req}

      {:more, data, req} ->
        IO.binwrite(file, data)
        read_part_body_to_file(req, file)
    end
  end

  # Extracts "name" and "filename" from the content-disposition header.
  # Example: "form-data; name=\"file\"; filename=\"photo.jpg\""
  defp parse_disposition(headers) do
    case Map.get(headers, "content-disposition") do
      nil ->
        {nil, nil}

      disposition ->
        name = extract_header_param(disposition, "name")
        filename = extract_header_param(disposition, "filename")
        {name, filename}
    end
  end

  defp extract_header_param(header, param_name) do
    header
    |> String.split(";")
    |> Enum.find_value(fn part ->
      trimmed = String.trim(part)

      case String.split(trimmed, "=", parts: 2) do
        [^param_name, value] -> String.trim(value, "\"")
        _ -> nil
      end
    end)
  end

  defp parse_body(body, "application/x-www-form-urlencoded" <> _) do
    URI.decode_query(body)
  end

  defp parse_body(body, "application/json" <> _) when byte_size(body) > 0 do
    case Jason.decode(body) do
      {:ok, parsed} when is_map(parsed) -> parsed
      {:ok, parsed} -> %{"_json" => parsed}
      {:error, _} -> %{"_body" => body}
    end
  end

  defp parse_body(body, _) when byte_size(body) > 0 do
    %{"_body" => body}
  end

  defp parse_body(_, _), do: %{}
end
