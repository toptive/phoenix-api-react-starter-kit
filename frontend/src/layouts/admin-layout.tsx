import { useAppConfig } from "@/api/hooks/bootstrap"
import { useJobsAccess } from "@/api/hooks/admin"
import { FormError } from "@/components/app/form-error"
import { Link } from "@/components/app/link"
import { useLocation } from "@tanstack/react-router"
import {
  ArrowLeftIcon,
  BuildingIcon,
  FileTextIcon,
  GaugeIcon,
  HistoryIcon,
  ListTodoIcon,
  LanguagesIcon,
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
  const { app } = useAppConfig()
  const jobs = useJobsAccess()
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
                </SidebarMenu>
              </SidebarGroupContent>
            </SidebarGroup>
          </SidebarContent>
          <SidebarFooter>
            {app.jobsDashboard && (
              <SidebarMenu>
                <SidebarMenuItem>
                  <SidebarMenuButton
                    className="min-h-11"
                    disabled={jobs.isPending}
                    onClick={async () => {
                      try {
                        const { url } = await jobs.mutateAsync()
                        window.open(url, "_blank", "noopener")
                      } catch {
                        /* The mutation error is displayed below. */
                      }
                    }}
                  >
                    <ListTodoIcon aria-hidden="true" />
                    <span>{t("admin.nav.jobs")}</span>
                  </SidebarMenuButton>
                  <FormError error={jobs.error} />
                </SidebarMenuItem>
              </SidebarMenu>
            )}
            <SidebarMenu>
              <SidebarMenuItem>
                <SidebarMenuButton asChild className="min-h-11">
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
            <SidebarTrigger className="size-11" />
          </header>
          <div id="main" className="mx-auto w-full max-w-6xl flex-1 px-4 py-8 sm:px-8">
            {children}
          </div>
        </SidebarInset>
      </SidebarProvider>
    </TooltipProvider>
  )
}
