import { Link, usePage } from "@inertiajs/react"
import {
  ArrowLeftIcon,
  BuildingIcon,
  FileTextIcon,
  GaugeIcon,
  HistoryIcon,
  LanguagesIcon,
  ListChecksIcon,
  UsersIcon,
} from "lucide-react"
import type { ReactNode } from "react"
import { useTranslation } from "react-i18next"

import { Logo } from "@/components/app/logo"
import {
  Sidebar,
  SidebarContent,
  SidebarFooter,
  SidebarGroup,
  SidebarGroupContent,
  SidebarGroupLabel,
  SidebarHeader,
  SidebarInset,
  SidebarMenu,
  SidebarMenuButton,
  SidebarMenuItem,
  SidebarProvider,
  SidebarTrigger,
} from "@/components/ui/sidebar"
import { TooltipProvider } from "@/components/ui/tooltip"
import { routes } from "@/generated/routes"

/** Superadmin area. Separate shell so nobody confuses it with the product. */
export function AdminLayout({ children }: { children: ReactNode }) {
  const { t } = useTranslation()
  const { url } = usePage()

  const nav = [
    { href: routes.adminDashboard.show().url, label: t("admin.nav.overview"), icon: GaugeIcon, exact: true },
    { href: routes.adminUser.index().url, label: t("admin.nav.users"), icon: UsersIcon },
    { href: routes.adminOrganization.index().url, label: t("admin.nav.organizations"), icon: BuildingIcon },
    { href: routes.adminTranslation.index().url, label: t("admin.nav.translations"), icon: LanguagesIcon },
    { href: routes.adminLegalDocument.index().url, label: t("admin.nav.legal"), icon: FileTextIcon },
    { href: routes.adminAuditEvent.index().url, label: t("admin.nav.audit"), icon: HistoryIcon },
  ]

  return (
    <TooltipProvider delayDuration={200}>
      <SidebarProvider>
        <Sidebar>
          <SidebarHeader className="px-4 py-3">
            <Logo href={routes.adminDashboard.show().url} />
          </SidebarHeader>
          <SidebarContent>
            <SidebarGroup>
              <SidebarGroupLabel>{t("admin.title")}</SidebarGroupLabel>
              <SidebarGroupContent>
                <SidebarMenu>
                  {nav.map((item) => (
                    <SidebarMenuItem key={item.href}>
                      <SidebarMenuButton asChild isActive={item.exact ? url === item.href : url.startsWith(item.href)}>
                        <Link href={item.href}>
                          <item.icon aria-hidden="true" />
                          <span>{item.label}</span>
                        </Link>
                      </SidebarMenuButton>
                    </SidebarMenuItem>
                  ))}
                  <SidebarMenuItem>
                    <SidebarMenuButton asChild>
                      <a href={routes.webDashboard.home().url}>
                        <ListChecksIcon aria-hidden="true" />
                        <span>{t("admin.nav.jobs")}</span>
                      </a>
                    </SidebarMenuButton>
                  </SidebarMenuItem>
                </SidebarMenu>
              </SidebarGroupContent>
            </SidebarGroup>
          </SidebarContent>
          <SidebarFooter>
            <SidebarMenu>
              <SidebarMenuItem>
                <SidebarMenuButton asChild>
                  <Link href={routes.dashboard.show().url}>
                    <ArrowLeftIcon aria-hidden="true" />
                    <span>{t("admin.nav.back")}</span>
                  </Link>
                </SidebarMenuButton>
              </SidebarMenuItem>
            </SidebarMenu>
          </SidebarFooter>
        </Sidebar>
        <SidebarInset>
          <header className="flex h-14 items-center gap-2 border-b px-4 md:hidden">
            <SidebarTrigger />
          </header>
          <div id="main" className="mx-auto w-full max-w-6xl flex-1 px-4 py-8 sm:px-8">
            {children}
          </div>
        </SidebarInset>
      </SidebarProvider>
    </TooltipProvider>
  )
}
