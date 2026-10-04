import { act, fireEvent, screen, waitFor } from "@testing-library/react"
import { beforeEach, describe, expect, it, vi } from "vitest"

import { Turnstile } from "@/components/app/turnstile"
import { loadWidget, type TurnstileApi } from "@/lib/turnstile-client"
import { renderWithI18n } from "@/test/render"

const shared = vi.hoisted(() => ({ turnstile: { required: true, siteKey: "public-key" as string | null } }))
vi.mock("@/api/hooks/bootstrap", () => ({ useAppConfig: () => shared }))
vi.mock("@/hooks/use-appearance", () => ({ useAppearance: () => ({ appearance: "dark" }) }))
vi.mock("@/lib/turnstile-client", () => ({ loadWidget: vi.fn() }))

describe("Turnstile", () => {
  beforeEach(() => {
    vi.resetAllMocks()
    shared.turnstile = { required: true, siteKey: "public-key" }
  })

  it("clears an expired token and replaces the widget on the next attempt", async () => {
    let options: Parameters<TurnstileApi["render"]>[1] | undefined
    const api: TurnstileApi = {
      render: vi.fn((_container, value) => { options = value; return "widget" }),
      remove: vi.fn(),
    }
    vi.mocked(loadWidget).mockResolvedValue(api)
    const onToken = vi.fn()
    const view = renderWithI18n(<Turnstile action="registration" attempt={0} onToken={onToken} />)

    await waitFor(() => expect(api.render).toHaveBeenCalledOnce())
    expect(options).toMatchObject({ action: "registration", theme: "dark", sitekey: "public-key" })
    act(() => options?.callback("token"))
    expect(onToken).toHaveBeenLastCalledWith("token")
    act(() => options?.["expired-callback"]())
    expect(onToken).toHaveBeenLastCalledWith("")

    view.rerender(<Turnstile action="registration" attempt={1} onToken={onToken} />)
    await waitFor(() => expect(api.render).toHaveBeenCalledTimes(2))
    expect(api.remove).toHaveBeenCalledWith("widget")
    view.unmount()
    expect(api.remove).toHaveBeenCalledTimes(2)
  })

  it("offers a retry after a network failure and keeps no old token", async () => {
    const api: TurnstileApi = { render: vi.fn(() => "retry-widget"), remove: vi.fn() }
    vi.mocked(loadWidget).mockRejectedValueOnce(new Error("offline")).mockResolvedValueOnce(api)
    const onToken = vi.fn()
    renderWithI18n(<Turnstile action="magic_link" attempt={0} onToken={onToken} />)

    await screen.findByText("We couldn't load the security check. Check your connection and try again.")
    expect(onToken).toHaveBeenLastCalledWith("")
    fireEvent.click(screen.getByRole("button", { name: "Try again" }))
    await waitFor(() => expect(api.render).toHaveBeenCalledOnce())
    expect(screen.queryByRole("status")).toBeNull()
  })

  it("loads no external script while protection is off or the site key is missing", () => {
    shared.turnstile = { required: false, siteKey: null }
    const onToken = vi.fn()
    const view = renderWithI18n(<Turnstile action="registration" attempt={0} onToken={onToken} />)
    expect(view.container.innerHTML).toBe("")

    shared.turnstile = { required: true, siteKey: null }
    view.rerender(<Turnstile action="registration" attempt={0} onToken={onToken} />)
    expect(screen.getByRole("status")).toBeTruthy()
    expect(loadWidget).not.toHaveBeenCalled()
  })

  it("shows the server's error", () => {
    vi.mocked(loadWidget).mockReturnValue(new Promise(() => {}))
    renderWithI18n(<Turnstile action="registration" attempt={0} error="Not verified" onToken={vi.fn()} />)
    expect(screen.getByRole("alert").textContent).toBe("Not verified")
  })
})
