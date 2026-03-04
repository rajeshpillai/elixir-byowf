defmodule Mix.Tasks.Ignite.Gen.Cert do
  @moduledoc """
  Generates self-signed SSL certificates for local development.

      $ mix ignite.gen.cert

  Creates `priv/ssl/cert.pem` and `priv/ssl/key.pem` using `openssl`.
  These are **not** suitable for production — use Let's Encrypt or your
  CA for real certificates.

  ## Options

  - `--hostname` — the hostname for the certificate (default: `localhost`)
  """

  use Mix.Task

  @shortdoc "Generate self-signed SSL certificates for development"

  @output_dir "priv/ssl"
  @certfile "cert.pem"
  @keyfile "key.pem"

  @impl true
  def run(args) do
    hostname = parse_hostname(args)

    File.mkdir_p!(@output_dir)

    certpath = Path.join(@output_dir, @certfile)
    keypath = Path.join(@output_dir, @keyfile)

    if File.exists?(certpath) do
      Mix.shell().info("""
      Certificate already exists at #{certpath}.
      Delete it first if you want to regenerate:

          rm -rf #{@output_dir}
          mix ignite.gen.cert
      """)
    else
      generate_cert(hostname, certpath, keypath)
    end
  end

  defp generate_cert(hostname, certpath, keypath) do
    Mix.shell().info("Generating self-signed certificate for #{hostname}...")

    # Use openssl to generate a self-signed cert valid for 365 days
    {output, exit_code} =
      System.cmd("openssl", [
        "req",
        "-x509",
        "-newkey", "rsa:2048",
        "-nodes",
        "-keyout", keypath,
        "-out", certpath,
        "-days", "365",
        "-subj", "/CN=#{hostname}/O=Ignite Dev"
      ], stderr_to_stdout: true)

    if exit_code == 0 do
      Mix.shell().info("""

      Self-signed certificate generated successfully!

        Certificate: #{certpath}
        Private key: #{keypath}
        Valid for:   365 days
        Hostname:    #{hostname}

      Add this to your config/prod.exs:

          config :ignite,
            port: 4443,
            ssl: [
              certfile: "#{certpath}",
              keyfile: "#{keypath}"
            ]

      Then start with: MIX_ENV=prod iex -S mix

      Note: Browsers will show a warning for self-signed certs.
      Use `curl -k` to skip verification when testing.
      """)
    else
      Mix.shell().error("Failed to generate certificate:\n#{output}")
      Mix.shell().error("Make sure `openssl` is installed and in your PATH.")
    end
  end

  defp parse_hostname(args) do
    case OptionParser.parse(args, strict: [hostname: :string]) do
      {opts, _, _} -> Keyword.get(opts, :hostname, "localhost")
      _ -> "localhost"
    end
  end
end
