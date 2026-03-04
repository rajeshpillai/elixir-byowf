defmodule MyApp.WelcomeController do
  @moduledoc """
  Handles requests to the welcome/home pages.
  """

  import Ignite.Controller

  def index(conn) do
    text(conn, "Welcome to Ignite!")
  end

  def hello(conn) do
    text(conn, "Hello from the Controller!")
  end

  def crash(_conn) do
    raise "This is a test crash!"
  end

  def counter(conn) do
    page = """
    <!DOCTYPE html>
    <html>
    <head>
      <title>Live Counter — Ignite</title>
      <style>
        body { font-family: system-ui, sans-serif; text-align: center; margin-top: 50px; }
        button { cursor: pointer; margin: 5px; }
      </style>
    </head>
    <body>
      <div id="ignite-app">Connecting...</div>
      <script>
        const socket = new WebSocket("ws://" + window.location.host + "/live");

        socket.onmessage = function(event) {
          var data = JSON.parse(event.data);
          document.getElementById("ignite-app").innerHTML = data.html;
        };

        document.addEventListener("click", function(e) {
          var eventName = e.target.getAttribute("ignite-click");
          if (eventName) {
            socket.send(JSON.stringify({event: eventName, params: {}}));
          }
        });

        socket.onopen = function() { console.log("Ignite LiveView connected"); };
        socket.onclose = function() { console.log("Ignite LiveView disconnected"); };
      </script>
    </body>
    </html>
    """

    html(conn, page)
  end
end
