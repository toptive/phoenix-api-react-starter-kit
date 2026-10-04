# `mix check` runs every gate (docs/GATES.md). The git hooks and the /deploy skill call it.
# A gate that fails is fixed in the code, never by weakening the gate.
[
  parallel: true,
  skipped: false,
  tools: [
    # compiler also runs `boundary` (the compiler fails on a forbidden reference)
    {:compiler, "mix compile --warnings-as-errors --force"},
    {:formatter, "mix format --check-formatted"},
    {:credo, "mix credo --strict"},
    {:dialyzer, "mix dialyzer --format short"},
    {:sobelow, "mix sobelow --config"},
    {:mix_audit, "mix deps.audit"},
    {:hex_audit, "mix hex.audit"},
    {:unused_deps, "mix deps.unlock --check-unused"},
    {:doctor, false},
    {:gettext, false},
    {:npm_test, false},
    {:ex_doc, false},
    {:ex_unit, "mix test --warnings-as-errors", env: %{"MIX_ENV" => "test"}},
    # Type contract drift: generated TypeScript must match the serializers, routes and
    # page declarations (needs the dev database for column nullability).
    {:typelizer, "mix typelizer.check", env: %{"MIX_ENV" => "dev"}},
    {:ts_typecheck, "pnpm typecheck"},
    {:eslint, "pnpm lint"},
    {:vitest, "pnpm test"},
    {:pnpm_audit, "pnpm audit --audit-level=high"}
  ]
]
