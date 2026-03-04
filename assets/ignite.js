/**
 * Ignite.js — Frontend glue for Ignite LiveView.
 *
 * Uses morphdom for efficient DOM patching:
 * - Instead of replacing innerHTML (which destroys focus, animations, etc.),
 *   morphdom compares the old and new HTML and only updates what changed.
 *
 * Protocol:
 * - On mount: server sends {s: [...statics], d: [...dynamics]}
 * - On update: server sends {d: [...dynamics]}
 * - On redirect: server sends {redirect: {live_path: "/live/x", url: "/x"}}
 * - JS zips statics + dynamics, then morphdom patches the DOM
 *
 * Supported attributes:
 * - ignite-click="event"    — sends event on click
 * - ignite-change="event"   — sends event on input change (with field name + value)
 * - ignite-submit="event"   — sends event on form submit (with all form fields)
 * - ignite-value="val"      — optional static value sent with click events
 * - ignite-navigate="/path" — client-side LiveView navigation (no full page reload)
 */

(function () {
  "use strict";

  // --- Configuration ---
  var APP_CONTAINER_ID = "ignite-app";

  // Statics are saved from the first message and reused for every update
  var statics = null;

  // Current WebSocket connection
  var socket = null;

  // Route mapping: HTTP path → WebSocket live_path (injected by server)
  var liveRoutes = {};

  // --- Initialize ---
  var appContainer = document.getElementById(APP_CONTAINER_ID);
  if (!appContainer) return;

  // Read route mapping from data attribute
  try {
    var routesJson = appContainer.dataset.liveRoutes;
    if (routesJson) {
      liveRoutes = JSON.parse(routesJson);
    }
  } catch (e) {
    // ignore parse errors
  }

  // --- Helper: send event over WebSocket ---
  function sendEvent(event, params) {
    if (socket && socket.readyState === WebSocket.OPEN) {
      socket.send(JSON.stringify({ event: event, params: params }));
    }
  }

  // --- Reconstruct HTML from statics + dynamics ---
  function buildHtml(statics, dynamics) {
    var html = "";
    for (var i = 0; i < statics.length; i++) {
      html += statics[i];
      if (i < dynamics.length) {
        html += dynamics[i];
      }
    }
    return html;
  }

  // --- Apply update to DOM ---
  // Uses morphdom if available, falls back to innerHTML
  function applyUpdate(container, newHtml) {
    if (typeof morphdom === "function") {
      // Create a temporary wrapper to morph into
      var wrapper = document.createElement("div");
      wrapper.id = APP_CONTAINER_ID;
      // Preserve data attributes
      if (container.dataset.livePath) {
        wrapper.dataset.livePath = container.dataset.livePath;
      }
      if (container.dataset.liveRoutes) {
        wrapper.dataset.liveRoutes = container.dataset.liveRoutes;
      }
      wrapper.innerHTML = newHtml;

      morphdom(container, wrapper, {
        // Preserve focused input elements
        onBeforeElUpdated: function (fromEl, toEl) {
          // Don't overwrite value if user is actively typing
          if (fromEl === document.activeElement) {
            if (fromEl.tagName === "INPUT" || fromEl.tagName === "TEXTAREA") {
              toEl.value = fromEl.value;
            }
          }
          return true;
        },
      });
    } else {
      // Fallback: replace entire content
      container.innerHTML = newHtml;
    }
  }

  // --- WebSocket connection management ---
  function connect(livePath) {
    // Close existing connection
    if (socket) {
      socket.onclose = null; // prevent disconnect log
      socket.close();
    }

    // Reset statics for new view
    statics = null;

    var container = document.getElementById(APP_CONTAINER_ID);
    if (container) {
      container.innerHTML = "Connecting...";
      container.dataset.livePath = livePath;
    }

    var protocol = window.location.protocol === "https:" ? "wss:" : "ws:";
    socket = new WebSocket(protocol + "//" + window.location.host + livePath);

    socket.onmessage = function (event) {
      var data = JSON.parse(event.data);
      var el = document.getElementById(APP_CONTAINER_ID);
      if (!el) return;

      // Handle server-initiated navigation
      if (data.redirect) {
        navigate(data.redirect.url, data.redirect.live_path);
        return;
      }

      // First message includes statics — save them
      if (data.s) {
        statics = data.s;
      }

      // Reconstruct HTML and patch the DOM
      if (statics && data.d) {
        var newHtml = buildHtml(statics, data.d);
        applyUpdate(el, newHtml);
      }
    };

    socket.onopen = function () {
      console.log(
        "[Ignite] LiveView connected to " +
          livePath +
          " (morphdom: " +
          (typeof morphdom === "function") +
          ")"
      );
    };

    socket.onclose = function () {
      console.log("[Ignite] LiveView disconnected");
    };

    socket.onerror = function (err) {
      console.error("[Ignite] WebSocket error:", err);
    };
  }

  // --- LiveView Navigation ---
  // Navigate to a new LiveView without full page reload
  function navigate(url, livePath) {
    // Resolve live_path from route mapping if not provided
    if (!livePath && liveRoutes[url]) {
      livePath = liveRoutes[url];
    }

    if (!livePath) {
      // Fallback: full page navigation for non-LiveView routes
      window.location.href = url;
      return;
    }

    // Update browser URL without reload
    history.pushState({ url: url, livePath: livePath }, "", url);

    // Connect to the new LiveView
    connect(livePath);
  }

  // --- Browser back/forward navigation ---
  window.addEventListener("popstate", function (e) {
    if (e.state && e.state.livePath) {
      connect(e.state.livePath);
    } else {
      // No state — full page reload
      window.location.reload();
    }
  });

  // --- Set initial history state ---
  var initialLivePath =
    (appContainer && appContainer.dataset.livePath) || "/live";
  history.replaceState(
    { url: window.location.pathname, livePath: initialLivePath },
    "",
    window.location.pathname
  );

  // --- Send click events to server ---
  document.addEventListener("click", function (e) {
    var target = e.target;

    while (target && target !== document) {
      // Check for navigation links first
      var navPath = target.getAttribute("ignite-navigate");
      if (navPath) {
        e.preventDefault();
        navigate(navPath);
        return;
      }

      // Check for click events
      var eventName = target.getAttribute("ignite-click");
      if (eventName) {
        e.preventDefault();

        var params = {};
        var value = target.getAttribute("ignite-value");
        if (value) {
          params.value = value;
        }

        sendEvent(eventName, params);
        return;
      }
      target = target.parentElement;
    }
  });

  // --- Send input change events to server ---
  document.addEventListener("input", function (e) {
    var target = e.target;

    // Walk up to find ignite-change (could be on the input or a parent)
    var el = target;
    while (el && el !== document) {
      var eventName = el.getAttribute("ignite-change");
      if (eventName) {
        var params = {
          field: target.getAttribute("name") || "",
          value: target.value,
        };
        sendEvent(eventName, params);
        return;
      }
      el = el.parentElement;
    }
  });

  // --- Send form submit events to server ---
  document.addEventListener("submit", function (e) {
    var form = e.target;
    if (!form || !form.getAttribute) return;

    var eventName = form.getAttribute("ignite-submit");
    if (eventName) {
      e.preventDefault();

      // Collect all form fields
      var params = {};
      var formData = new FormData(form);
      formData.forEach(function (value, key) {
        params[key] = value;
      });

      sendEvent(eventName, params);
    }
  });

  // --- Initial connection ---
  connect(initialLivePath);
})();
