/**
 * Ignite.js — Frontend glue for Ignite LiveView.
 *
 * Handles the statics/dynamics diffing protocol:
 * - On mount: server sends {s: [...statics], d: [...dynamics]}
 * - On update: server sends {d: [...dynamics]}
 * - JS zips statics + dynamics to reconstruct full HTML
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
  // Statics: ["<h1>Count: ", "</h1>"]
  // Dynamics: ["42"]
  // Result:  "<h1>Count: 42</h1>"
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

  // --- Receive updates from server ---
  socket.onmessage = function (event) {
    var data = JSON.parse(event.data);
    var container = document.getElementById(APP_CONTAINER_ID);
    if (!container) return;

    // First message includes statics — save them
    if (data.s) {
      statics = data.s;
    }

    // Reconstruct HTML from statics + dynamics
    if (statics && data.d) {
      container.innerHTML = buildHtml(statics, data.d);
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
    console.log("[Ignite] LiveView connected");
  };

  socket.onclose = function () {
    console.log("[Ignite] LiveView disconnected");
  };

  socket.onerror = function (err) {
    console.error("[Ignite] WebSocket error:", err);
  };
})();
