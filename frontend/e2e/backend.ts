/** Per-kit fixture seam. Rails/Rust implement these exports against their isolated test backend. */
import { execFileSync } from "node:child_process"

function database() {
  const name = process.env.E2E_PGDATABASE ?? "starter_kit_e2e"
  if (!/(?:e2e|test)/.test(name)) throw new Error("Fixtures require an isolated e2e/test database")
  return name
}
function run(code: string) {
  const result = execFileSync(
    "mix",
    [
      "run",
      "--no-start",
      "--no-compile",
      "-e",
      `
    Logger.configure(level: :error)
    Application.ensure_all_started(:ecto_sql)
    Application.ensure_all_started(:postgrex)
    Application.ensure_all_started(:oban)
    Application.ensure_all_started(:plug_crypto)
    repo = Application.get_env(:starter_kit, StarterKit.Repo)
    Application.put_env(:starter_kit, StarterKit.Repo,
      Keyword.put(repo, :port, String.to_integer(System.get_env("PGPORT", "5432"))))
    {:ok, _} = StarterKit.Repo.start_link()
    {:ok, _} = Oban.start_link(repo: StarterKit.Repo, queues: false, plugins: false)
    ${code}
  `,
    ],
    {
      cwd: process.env.E2E_API_DIR ?? new URL("../../../../phoenix-api-react-starter-kit", import.meta.url).pathname,
      env: {
        ...process.env,
        MIX_ENV: "dev",
        PGDATABASE: database(),
        ERL_FLAGS: "+S 2:2",
        SPA_ORIGIN: process.env.E2E_BASE_URL ?? "http://localhost:5173",
      },
      encoding: "utf8",
      timeout: 30_000,
    },
  )
  return result.trim().split("\n").at(-1)!
}
function uuid(value: string) {
  if (!/^[0-9a-f-]{36}$/.test(value)) throw new Error("Invalid fixture UUID")
  return value
}
/** Seed a confirmed account and fresh bearer; bootstrap the first superadmin using the kit's public hook. */
export function seedUser(email: string, admin = false): { token: string; expiresAt: string; sudoUntil: string | null } {
  if (!/^[a-z0-9@.-]+$/.test(email)) throw new Error("Invalid fixture email")
  return JSON.parse(
    run(`
    alias StarterKit.{Accounts, Repo}
    alias StarterKit.Accounts.User
    user = Accounts.get_user_by_email("${email}") || (
      if ${admin} do
        {:ok, user} = Accounts.bootstrap_superadmin("${email}")
        user
      else
        %User{} |> User.registration_changeset(%{name: "Browser Tester", email: "${email}", locale: "en", terms_accepted: true})
        |> Ecto.Changeset.put_change(:confirmed_at, DateTime.utc_now(:second)) |> Repo.insert!()
      end
    )
    session = Accounts.generate_api_token(user)
    IO.puts(Jason.encode!(%{token: session.token, expiresAt: session.expires_at, sudoUntil: session.sudo_until}))
  `),
  )
}
/** Expire just this session's sudo clock to exercise real reauthentication. */
export function expireSudo(sessionId: string) {
  execFileSync(
    "psql",
    [
      "-X",
      "-v",
      "ON_ERROR_STOP=1",
      "-c",
      `UPDATE sessions SET sudo_until = NOW() - INTERVAL '1 minute' WHERE id = '${uuid(sessionId)}'`,
    ],
    {
      env: {
        ...process.env,
        PGDATABASE: database(),
        PGUSER: process.env.PGUSER ?? "postgres",
        PGPASSWORD: process.env.PGPASSWORD ?? "postgres",
      },
      stdio: "pipe",
    },
  )
}
/** Queue real optional mail; the running API delivers it into its dev mailbox. */
export function sendOptionalEmail(userId: string) {
  run(`
    user = StarterKit.Accounts.get_user!("${uuid(userId)}")
    {:ok, _} = StarterKit.Notifications.notify(user, :product_update, %{title: "Browser news", summary: "Test newsletter", url: "http://localhost:5173/"})
  `)
}
