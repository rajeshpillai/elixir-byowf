/**
 * Ignite.js — Frontend glue for Ignite LiveView.
 *
 * Uses morphdom for efficient DOM patching:
 * - Instead of replacing innerHTML (which destroys focus, animations, etc.),
 *   morphdom compares the old and new HTML and only updates what changed.
 *
 * Protocol:
 * - On mount: server sends {s: [...statics], d: [...dynamics]}
 * - On update (full): server sends {d: [...dynamics]}
 * - On update (sparse): server sends {d: {"0": "new_val", "3": "changed"}}
 * - On redirect: server sends {redirect: {live_path: "/live/x", url: "/x"}}
 * - Streams: server sends {streams: {name: {inserts: [...], deletes: [...], reset: bool}}}
 * - JS zips statics + dynamics, then morphdom patches the DOM
 *
 * Supported attributes:
 * - ignite-click="event"    — sends event on click
 * - ignite-change="event"   — sends event on input change (with field name + value)
 * - ignite-submit="event"   — sends event on form submit (with all form fields)
 * - ignite-value="val"      — optional static value sent with click events
 * - ignite-navigate="/path" — client-side LiveView navigation (no full page reload)
 * - ignite-hook="HookName"  — attach a JS Hook for client-side interop
 */

(function () {
  "use strict";

  // --- Configuration ---
  var APP_CONTAINER_ID = "ignite-app";

  // Statics are saved from the first message and reused for every update
  var statics = null;

  // Dynamics are saved so sparse updates can patch individual indices
  var dynamics = null;

  // Current WebSocket connection
  var socket = null;

  // Route mapping: HTTP path → WebSocket live_path (injected by server)
  var liveRoutes = {};

  // --- JS Hooks Registry ---
  // Users register hooks via: window.IgniteHooks = { HookName: { mounted(){}, ... } }
  // Each hook instance gets: this.el, this.pushEvent(event, params)
  var mountedHooks = {}; // elementId → { name, instance }

  function getHookDefinitions() {
    return window.IgniteHooks || {};
  }

  // Create a hook instance with the right context
  function createHookInstance(hookDef, el) {
    var instance = Object.create(hookDef);
    instance.el = el;
    instance.pushEvent = function (event, params) {
      sendEvent(event, params || {});
    };
    return instance;
  }

  // Scan the DOM for [ignite-hook] elements and call mounted() on new ones
  function mountHooks(container) {
    var hookDefs = getHookDefinitions();
    var elements = container.querySelectorAll("[ignite-hook]");

    for (var i = 0; i < elements.length; i++) {
      var el = elements[i];
      var hookName = el.getAttribute("ignite-hook");
      var elId = el.id;

      if (!elId || !hookName) continue;
      if (mountedHooks[elId]) continue; // already mounted

      var def = hookDefs[hookName];
      if (!def) {
        console.warn("[Ignite] Hook '" + hookName + "' not found in IgniteHooks");
        continue;
      }

      var instance = createHookInstance(def, el);
      mountedHooks[elId] = { name: hookName, instance: instance };

      if (typeof instance.mounted === "function") {
        instance.mounted();
      }
    }
  }

  // Call updated() on hooks whose elements were re-rendered
  function updateHooks(container) {
    var elements = container.querySelectorAll("[ignite-hook]");

    for (var i = 0; i < elements.length; i++) {
      var el = elements[i];
      var elId = el.id;
      if (!elId) continue;

      var entry = mountedHooks[elId];
      if (entry) {
        // Update the element reference (morphdom may have replaced it)
        entry.instance.el = el;
        if (typeof entry.instance.updated === "function") {
          entry.instance.updated();
        }
      }
    }
  }

  // Call destroyed() on hooks whose elements were removed
  function cleanupHooks(container) {
    var currentIds = {};
    var elements = container.querySelectorAll("[ignite-hook]");
    for (var i = 0; i < elements.length; i++) {
      if (elements[i].id) currentIds[elements[i].id] = true;
    }

    var toRemove = [];
    for (var id in mountedHooks) {
      if (!currentIds[id]) {
        toRemove.push(id);
      }
    }

    for (var j = 0; j < toRemove.length; j++) {
      var entry = mountedHooks[toRemove[j]];
      if (entry && typeof entry.instance.destroyed === "function") {
        entry.instance.destroyed();
      }
      delete mountedHooks[toRemove[j]];
    }
  }

  // Destroy all hooks (e.g. on navigation)
  function destroyAllHooks() {
    for (var id in mountedHooks) {
      var entry = mountedHooks[id];
      if (entry && typeof entry.instance.destroyed === "function") {
        entry.instance.destroyed();
      }
    }
    mountedHooks = {};
  }

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

    // Hook lifecycle: clean up removed hooks, mount new ones, update existing
    cleanupHooks(container);
    mountHooks(container);
    updateHooks(container);
  }

  // --- Apply stream operations (insert/delete/reset) ---
  // Streams bypass the statics/dynamics diffing — they operate directly on
  // DOM containers marked with [ignite-stream="name"].
  function applyStreamOps(data) {
    if (!data.streams) return;

    for (var streamName in data.streams) {
      var ops = data.streams[streamName];
      var container = document.querySelector(
        '[ignite-stream="' + streamName + '"]'
      );

      if (!container) {
        console.warn("[Ignite] Stream container not found: " + streamName);
        continue;
      }

      // Reset: remove all children
      if (ops.reset) {
        while (container.firstChild) {
          container.removeChild(container.firstChild);
        }
      }

      // Deletes: remove elements by DOM ID
      if (ops.deletes) {
        for (var i = 0; i < ops.deletes.length; i++) {
          var el = document.getElementById(ops.deletes[i]);
          if (el) {
            el.parentNode.removeChild(el);
          }
        }
      }

      // Inserts: add new elements
      if (ops.inserts) {
        for (var j = 0; j < ops.inserts.length; j++) {
          var entry = ops.inserts[j];

          // Parse the HTML string into a DOM element
          var temp = document.createElement("div");
          temp.innerHTML = entry.html.trim();
          var newEl = temp.firstChild;

          // Ensure the element has the correct ID
          if (newEl && !newEl.id) {
            newEl.id = entry.id;
          }

          // If element with this ID already exists, update it (morphdom or replace)
          var existing = document.getElementById(entry.id);
          if (existing) {
            if (typeof morphdom === "function") {
              morphdom(existing, newEl);
            } else {
              existing.parentNode.replaceChild(newEl, existing);
            }
          } else if (entry.at === 0) {
            // Prepend
            container.insertBefore(newEl, container.firstChild);
          } else {
            // Append (default)
            container.appendChild(newEl);
          }
        }
      }
    }
  }

  // --- WebSocket connection management ---
  function connect(livePath) {
    // Close existing connection
    if (socket) {
      socket.onclose = null; // prevent disconnect log
      socket.close();
    }

    // Destroy all hooks from previous view
    destroyAllHooks();

    // Reset statics and dynamics for new view
    statics = null;
    dynamics = null;

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

      // Apply dynamics update (supports both full array and sparse object)
      if (statics && data.d) {
        if (Array.isArray(data.d)) {
          // Full dynamics array — replace entirely
          dynamics = data.d;
        } else if (dynamics) {
          // Sparse object — patch only changed indices
          for (var key in data.d) {
            dynamics[parseInt(key, 10)] = data.d[key];
          }
        } else {
          // First update is sparse but no previous dynamics (shouldn't happen)
          dynamics = [];
          for (var k in data.d) {
            dynamics[parseInt(k, 10)] = data.d[k];
          }
        }

        // Reconstruct HTML and patch the DOM
        var newHtml = buildHtml(statics, dynamics);
        applyUpdate(el, newHtml);
      }

      // Apply stream operations (after DOM is updated so containers exist)
      applyStreamOps(data);
    };

    socket.onopen = function () {
      console.log(
        "[Ignite] LiveView connected to " +
          livePath +
          " (morphdom: " +
          (typeof morphdom === "function") +
          ", hooks: " +
          Object.keys(getHookDefinitions()).length +
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

  // --- Component event namespacing ---
  // If an element is inside [ignite-component="id"], prefix its event with "id:"
  function resolveEvent(eventName, target) {
    var el = target;
    while (el && el !== document) {
      var componentId = el.getAttribute("ignite-component");
      if (componentId) {
        return componentId + ":" + eventName;
      }
      el = el.parentElement;
    }
    return eventName;
  }

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

        // Namespace the event if inside a component
        sendEvent(resolveEvent(eventName, target), params);
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
        // Namespace the event if inside a component
        sendEvent(resolveEvent(eventName, target), params);
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

      // Namespace the event if inside a component
      sendEvent(resolveEvent(eventName, form), params);
    }
  });

  // --- Initial connection ---
  connect(initialLivePath);
})();
