/**
 * Ignite.js — Frontend glue for Ignite LiveView.
 *
 * This script:
 * 1. Opens a WebSocket connection to the server
 * 2. Listens for clicks on elements with `ignite-click` attributes
 * 3. Sends events to the server as JSON
 * 4. Updates the DOM with HTML received from the server
 */

(function () {
  "use strict";

  // --- Configuration ---
  var LIVE_PATH = "/live";
  var APP_CONTAINER_ID = "ignite-app";

  // --- WebSocket Connection ---
  var protocol = window.location.protocol === "https:" ? "wss:" : "ws:";
  var socket = new WebSocket(protocol + "//" + window.location.host + LIVE_PATH);

  // --- Receive updates from server ---
  socket.onmessage = function (event) {
    var data = JSON.parse(event.data);
    var container = document.getElementById(APP_CONTAINER_ID);

    if (container && data.html) {
      container.innerHTML = data.html;
    }
  };

  // --- Send events to server ---
  // Uses event delegation — one listener on the document catches all clicks.
  document.addEventListener("click", function (e) {
    var target = e.target;

    // Walk up the DOM tree to find the element with ignite-click
    while (target && target !== document) {
      var eventName = target.getAttribute("ignite-click");
      if (eventName) {
        e.preventDefault();

        // Collect data attributes as params
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
