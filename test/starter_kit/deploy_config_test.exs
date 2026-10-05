defmodule StarterKit.DeployConfigTest do
  # Release scripts, Kamal files and env-driven config (docs/DEPLOY.md, docs/GATES.md).
  # Not async: some tests change OS env vars.
  use ExUnit.Case, async: false

  test "server and RPC use the same loopback long name despite a dotted Kamal hostname" do
    for command <- ~w(start rpc remote eval) do
      assert System.cmd(
               "sh",
               [
                 "-c",
                 "unset RELEASE_NODE; . rel/env.sh.eex; printf '%s %s' \"$RELEASE_DISTRIBUTION\" \"$RELEASE_NODE\""
               ],
               env: [{"HOSTNAME", "209.97.156.205-container"}, {"RELEASE_COMMAND", command}]
             ) == {"name starter_kit@127.0.0.1", 0}
    end
  end

  @tag :tmp_dir
  test "bin/launch starts the server only after migrations succeed", %{tmp_dir: dir} do
    File.cp!("rel/overlays/bin/launch", Path.join(dir, "launch"))
    write_script(dir, "server", "echo server")

    for {migration_status, expected} <- [{0, "migrate\nserver\n"}, {17, "migrate\n"}] do
      write_script(dir, "migrate", "echo migrate\nexit #{migration_status}")
      assert System.cmd("sh", [Path.join(dir, "launch")]) == {expected, migration_status}
    end
  end

  @tag :tmp_dir
  test "pre-build skips the gates only when the gate stamp equals HEAD", %{tmp_dir: dir} do
    File.mkdir_p!(Path.join(dir, ".kamal/hooks"))
    File.mkdir_p!(Path.join(dir, "bin"))
    File.cp!(".kamal/hooks/pre-build", Path.join(dir, ".kamal/hooks/pre-build"))
    File.write!(Path.join(dir, ".kamal/secrets"), "SECRET_KEY_BASE=x\n")
    # A fake bin/check proves which secrets reach the gates.
    write_script(dir, "bin/check", "echo \"gates ran, secret=${SECRET_KEY_BASE:-unset}\"")

    git = fn args -> {_, 0} = System.cmd("git", args, cd: dir, stderr_to_stdout: true) end
    git.(["init", "-q"])
    git.(["add", "."])
    git.(["-c", "user.email=t@t", "-c", "user.name=t", "commit", "-qm", "init"])
    {head, 0} = System.cmd("git", ["rev-parse", "HEAD"], cd: dir)

    run = fn ->
      System.cmd("bash", [".kamal/hooks/pre-build"],
        cd: dir,
        env: [{"SECRET_KEY_BASE", "prod-secret"}, {"SKIP_GATES", nil}],
        stderr_to_stdout: true
      )
    end

    assert {out, 0} = run.()
    assert out =~ "gates ran, secret=unset"

    File.write!(Path.join(dir, ".git/mix-check-passed"), "0000000\n")
    assert {out, 0} = run.()
    assert out =~ "gates ran"

    File.write!(Path.join(dir, ".git/mix-check-passed"), head)
    assert {out, 0} = run.()
    assert out =~ "gate stamp"
    refute out =~ "gates ran"
  end

  test "a blank SENTRY_DSN is removed from the OS env, a real one stays" do
    with_env(%{"SENTRY_DSN" => "  "}, fn ->
      Config.Reader.read!("config/runtime.exs", env: :test)
      assert System.get_env("SENTRY_DSN") == nil
    end)

    with_env(%{"SENTRY_DSN" => "https://key@sentry.example.com/1"}, fn ->
      Config.Reader.read!("config/runtime.exs", env: :test)
      assert System.get_env("SENTRY_DSN") == "https://key@sentry.example.com/1"
    end)
  end

  test "SIGNUP_MODE is read at boot; a typo stops the boot" do
    with_env(%{"SIGNUP_MODE" => "invite"}, fn ->
      config = Config.Reader.read!("config/runtime.exs", env: :test)
      assert config[:starter_kit][:signup_mode] == :invite
    end)

    with_env(%{"SIGNUP_MODE" => "invited"}, fn ->
      assert_raise RuntimeError, ~r/SIGNUP_MODE/, fn ->
        Config.Reader.read!("config/runtime.exs", env: :test)
      end
    end)

    assert File.read!("config/deploy.yml") =~ ~r/^    SIGNUP_MODE: invite$/m
  end

  defp write_script(dir, name, body) do
    path = Path.join(dir, name)
    File.write!(path, "#!/bin/sh\n#{body}\n")
    File.chmod!(path, 0o755)
  end

  defp with_env(vars, fun) do
    previous = Map.new(vars, fn {name, _} -> {name, System.get_env(name)} end)
    Enum.each(vars, fn {name, value} -> put_env(name, value) end)

    try do
      fun.()
    after
      Enum.each(previous, fn {name, value} -> put_env(name, value) end)
    end
  end

  defp put_env(name, nil), do: System.delete_env(name)
  defp put_env(name, value), do: System.put_env(name, value)
end
