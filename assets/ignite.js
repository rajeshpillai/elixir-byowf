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
 */

(function () {
  "use strict";

  // --- Configuration ---
  var LIVE_PATH = "/live";
  var APP_CONTAINER_ID = "ignite-app";

  // Statics are saved from the first message and reused for every update
  var statics = null;

  // --- WebSocket Connection ---
  var protocol = window.location.protocol === "https:" ? "wss:" : "ws:";
  var socket = new WebSocket(protocol + "//" + window.location.host + LIVE_PATH);

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
      wrapper.innerHTML = newHtml;

      morphdom(container, wrapper, {
        // Preserve focused input elements
        onBeforeElUpdated: function (fromEl, toEl) {
          // Don't update the element if the user is actively typing in it
          if (fromEl === document.activeElement && fromEl.tagName === "INPUT") {
            toEl.value = fromEl.value;
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

  // --- Send events to server ---
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

        socket.send(
          JSON.stringify({
            event: eventName,
            params: params,
          })
        );
        return;
      }
      target = target.parentElement;
    }
  });

  // --- Connection lifecycle ---
  socket.onopen = function () {
    console.log("[Ignite] LiveView connected (morphdom: " + (typeof morphdom === "function") + ")");
  };

  socket.onclose = function () {
    console.log("[Ignite] LiveView disconnected");
  };

  socket.onerror = function (err) {
    console.error("[Ignite] WebSocket error:", err);
  };
})();
