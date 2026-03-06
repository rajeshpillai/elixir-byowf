# Production Readiness TODO

Items derived from a full security, reliability, and code quality audit. These are the gaps between "teaching framework" and "production-grade framework."

## Critical — Must Fix

**Input Validation & DoS Prevention**

- [ ] `parser.ex:34` — Add recv timeout to `read_request_line/1` (blocks forever; enables Slowloris DoS)
- [ ] `parser.ex:40-48` — Add error clause to `read_headers/1` for `{:error, :closed}` / `{:error, :timeout}`
- [ ] `parser.ex:60` — Validate `Content-Length` is numeric and enforce upper bound (e.g. 8MB) before `recv`
- [ ] `parser.ex:34-35` — Handle malformed HTTP requests gracefully instead of crashing on pattern match
- [ ] `cowboy.ex:145-159` — Set explicit `max_body_size` option on `cowboy_req.read_body/2`
- [ ] `cowboy.ex:167-201` — Add max iteration count to multipart `read_part_body_to_file`

**Resource Leaks**

- [ ] `server.ex:67-76` — Wrap `serve/1` in `try/after` to ensure socket is always closed on error
- [ ] `cowboy.ex:176-178` — Wrap file upload I/O in `try/after` to close file handle on exception
- [ ] `upload.ex:56-69` — Add timeout to cleanup monitor process (lives forever if parent is long-lived)

**Security**

- [ ] `controller.ex render/3` — Validate template_name to prevent path traversal (`../` sequences)
- [ ] `session.ex:30` — Remove hardcoded default secret; require explicit config or raise on boot in prod
- [ ] `rate_limiter.ex` — Don't blindly trust `x-forwarded-for`; make proxy trust configurable
- [ ] `upload.ex` — Add server-side file type validation (MIME sniffing), not just client-provided type

## Important — Should Fix

**State Management**

- [ ] `rate_limiter.ex:125-136` — Cap ETS entries per IP between cleanup cycles
- [ ] `presence.ex` — Add TTL / max entries to prevent unbounded state growth
- [ ] `presence.ex:81-108` — Handle race condition: DOWN arriving between check and demonitor in `track`
- [ ] `live_view/handler.ex:99-108` — Add `try/rescue` around `handle_event` to prevent state loss on crash
- [ ] `live_view/stream.ex:114-129` — Wrap stream reduce so partial `id_fn` failures don't corrupt state

**Error Handling**

- [ ] `parser.ex:69-70` — Log socket read errors instead of silently returning empty params
- [ ] `live_view/handler.ex:69` — Log malformed WebSocket frames instead of silently ignoring
- [ ] `live_view.ex:88-93` — Handle component `mount/1` returning unexpected values
- [ ] `live_view/handler.ex:96-121` — Add fallback for `handle_event` returning something other than `{:noreply, _}`

**Configuration**

- [ ] `rate_limiter.ex` — Cache `Application.get_env` in GenServer state instead of reading 4x per request
- [ ] Create `Ignite.Config` module to centralize 14 scattered `Application.get_env` calls
- [ ] `hsts.ex:31-32` — Cache HSTS config at boot instead of reading per-request

## Moderate — Nice to Have

**Test Coverage (~35% currently)**

- [ ] Parser — Unit tests for malformed requests, missing headers, oversized bodies
- [ ] Server — Tests for TCP accept loop lifecycle, socket cleanup on error
- [ ] Cowboy adapter — Tests for request conversion, multipart, error handling, session cookie flow
- [ ] LiveView.Handler — Tests for WebSocket mount, event dispatch, stream payloads, exceptions
- [ ] Static — Tests for manifest build, cache-busting, concurrent rebuild/lookup
- [ ] Upload — Tests for file I/O errors, cleanup scheduling, temp file lifecycle
- [ ] SSL/HSTS — Tests for TLS config, cert validation, HSTS header generation
- [ ] Integration — End-to-end test: Parser -> Router -> Controller -> Response

**Code Quality**

- [ ] `csp.ex:95` — Make `build_header/1` private (only used internally)
- [ ] `session.ex:102` — Add `@doc` to `build_cookie_header/1`
- [ ] `csrf.ex` — Log CSRF validation failures for monitoring/alerting
- [ ] `csp.ex` — Replace `style-src 'unsafe-inline'` with nonce-based style loading

**Resilience**

- [ ] `pub_sub.ex:37-42` — Handle dead processes in broadcast loop
- [ ] `live_view/handler.ex` — Add backpressure for WebSocket message floods
- [ ] `cowboy.ex` — Configure Cowboy idle/request timeouts explicitly
- [ ] `static.ex:23-27` — Make ETS manifest updates atomic
- [ ] `upload.ex` — Use `:crypto.strong_rand_bytes` for temp filenames instead of `:rand`
