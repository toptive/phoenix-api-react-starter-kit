import { Link } from "@/components/app/link"
import { useLocation } from "@tanstack/react-router"
import { HomeIcon, SettingsIcon, UsersIcon } from "lucide-react"
import type { ReactNode } from "react"
import { useTranslation } from "react-i18next"

import { Logo } from "@/components/app/logo"
import { OrganizationSwitcher } from "@/components/app/organization-switcher"
import { UserMenu } from "@/components/app/user-menu"
import {
  Sidebar,
  SidebarContent,
  SidebarFooter,
  SidebarGroup,
  SidebarGroupContent,
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

/**
 * The signed-in shell: sidebar (organization, navigation, user) and the page.
 * Products add their navigation items to `nav` — named by user task, not by model.
 */
export function AppLayout({ children }: { children: ReactNode }) {
  const { t } = useTranslation()
  const { pathname: url } = useLocation()

  const people = paths.members
  const nav = [
    { href: paths.dashboard, label: t("nav.home"), icon: HomeIcon, active: url.startsWith("/dashboard") },
    { href: people, label: t("nav.people"), icon: UsersIcon, active: url.startsWith(people) },
    {
      href: paths.profile,
      label: t("nav.settings"),
      icon: SettingsIcon,
      active: url.startsWith("/settings") && !url.startsWith(people),
    },
  ]

  return (
    <TooltipProvider delayDuration={200}>
      <SidebarProvider>
        <Sidebar collapsible="icon">
          <SidebarHeader>
            <OrganizationSwitcher />
          </SidebarHeader>
          <SidebarContent>
            <SidebarGroup>
              <SidebarGroupContent>
                <SidebarMenu>
                  {nav.map((item) => (
                    <SidebarMenuItem key={item.href}>
                      <SidebarMenuButton asChild isActive={item.active} tooltip={item.label}>
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
            <UserMenu />
          </SidebarFooter>
        </Sidebar>
        <SidebarInset>
          <header className="flex h-14 items-center gap-2 border-b px-4 md:hidden">
            <SidebarTrigger />
            <Logo href={paths.dashboard} />
          </header>
          <div id="main" className="mx-auto w-full max-w-5xl flex-1 px-4 py-8 sm:px-8 sm:py-10">
            {children}
          </div>
        </SidebarInset>
      </SidebarProvider>
    </TooltipProvider>
  )
}
