import { Link } from "@/components/app/link"
import { useLocation } from "@tanstack/react-router"
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
import { paths } from "@/lib/paths"

/** Superadmin area. Separate shell so nobody confuses it with the product. */
export function AdminLayout({ children }: { children: ReactNode }) {
  const { t } = useTranslation()
  const { pathname: url } = useLocation()

  const nav = [
    { href: paths.admin, label: t("admin.nav.overview"), icon: GaugeIcon, exact: true },
    { href: paths.adminUsers, label: t("admin.nav.users"), icon: UsersIcon },
    { href: paths.adminOrganizations, label: t("admin.nav.organizations"), icon: BuildingIcon },
    { href: paths.adminTranslations, label: t("admin.nav.translations"), icon: LanguagesIcon },
    { href: paths.adminLegalDocuments, label: t("admin.nav.legal"), icon: FileTextIcon },
    { href: paths.adminAuditEvents, label: t("admin.nav.audit"), icon: HistoryIcon },
  ]

  return (
    <TooltipProvider delayDuration={200}>
      <SidebarProvider>
        <Sidebar>
          <SidebarHeader className="px-4 py-3">
            <Logo href={paths.admin} />
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
                      <a href={paths.jobs}>
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
                  <Link href={paths.dashboard}>
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
