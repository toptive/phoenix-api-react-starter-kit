import type { ReactNode } from "react"

type Layout = (page: ReactNode) => ReactNode

type PageModule = {
  default: { layout?: Layout } & ((props: never) => ReactNode)
}

const pages = import.meta.glob<PageModule>("./pages/**/*.tsx")

/**
 * ONE resolver for the browser and for SSR. The component name is the path under
 * pages/ ("settings/profile/edit"). The layout comes from the path prefix, so pages
 * never wrap themselves and layouts persist across visits. Layouts load lazily: the
 * landing page does not download the app shell.
 */
export async function resolvePage(name: string) {
  const loader = pages[`./pages/${name}.tsx`]
  if (!loader) throw new Error(`Unknown page: ${name}`)
  const [page, layout] = await Promise.all([loader(), layoutFor(name)])
  page.default.layout ??= layout
  return page
}

async function layoutFor(name: string): Promise<Layout> {
  if (name.startsWith("admin/")) {
    const { AdminLayout } = await import("@/layouts/admin-layout")
    return (page) => <AdminLayout>{page}</AdminLayout>
  }
  if (name.startsWith("settings/")) {
    const [{ AppLayout }, { SettingsLayout }] = await Promise.all([import("@/layouts/app-layout"), import("@/layouts/settings-layout")])
    return (page) => (
      <AppLayout>
        <SettingsLayout>{page}</SettingsLayout>
      </AppLayout>
    )
  }
  if (/^(dashboard|organizations|onboarding)\//.test(name)) {
    const { AppLayout } = await import("@/layouts/app-layout")
    return (page) => <AppLayout>{page}</AppLayout>
  }
  if (/^(session|registration|magic-links|invitations|email-opt-out)\//.test(name)) {
    const { AuthLayout } = await import("@/layouts/auth-layout")
    return (page) => <AuthLayout>{page}</AuthLayout>
  }
  const { PublicLayout } = await import("@/layouts/public-layout")
  return (page) => <PublicLayout>{page}</PublicLayout>
}
