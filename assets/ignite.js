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
 * - JS zips statics + dynamics, then morphdom patches the DOM
 *
 * Supported attributes:
 * - ignite-click="event"    — sends event on click
 * - ignite-change="event"   — sends event on input change (with field name + value)
 * - ignite-submit="event"   — sends event on form submit (with all form fields)
 * - ignite-value="val"      — optional static value sent with click events
 */

(function () {
  "use strict";

  // --- Configuration ---
  var APP_CONTAINER_ID = "ignite-app";

  // Read WebSocket path from data attribute, fallback to "/live"
  var appContainer = document.getElementById(APP_CONTAINER_ID);
  var LIVE_PATH = (appContainer && appContainer.dataset.livePath) || "/live";

  // Statics are saved from the first message and reused for every update
  var statics = null;

  // --- WebSocket Connection ---
  var protocol = window.location.protocol === "https:" ? "wss:" : "ws:";
  var socket = new WebSocket(protocol + "//" + window.location.host + LIVE_PATH);

  // --- Helper: send event over WebSocket ---
  function sendEvent(event, params) {
    if (socket.readyState === WebSocket.OPEN) {
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
      if (container.dataset.livePath) {
        wrapper.dataset.livePath = container.dataset.livePath;
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

  // --- Receive updates from server ---
  socket.onmessage = function (event) {
    var data = JSON.parse(event.data);
    var container = document.getElementById(APP_CONTAINER_ID);
    if (!container) return;

    // First message includes statics — save them
    if (data.s) {
      statics = data.s;
    }

    // Reconstruct HTML and patch the DOM
    if (statics && data.d) {
      var newHtml = buildHtml(statics, data.d);
      applyUpdate(container, newHtml);
    }
  };

  // --- Send click events to server ---
  document.addEventListener("click", function (e) {
    var target = e.target;

    while (target && target !== document) {
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

  // --- Connection lifecycle ---
  socket.onopen = function () {
    console.log(
      "[Ignite] LiveView connected (morphdom: " +
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
})();
