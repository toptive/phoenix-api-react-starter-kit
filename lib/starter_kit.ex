defmodule StarterKit do
  @moduledoc """
  The domain. Each context (`StarterKit.Accounts`, `StarterKit.Organizations`, …) is its
  own boundary; see docs/ARCHITECTURE.md.
  """

  use Boundary, deps: [], exports: []
end
