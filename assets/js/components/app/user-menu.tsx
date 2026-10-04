import { Link, router } from "@inertiajs/react"
import { ChevronsUpDownIcon, LogOutIcon, SettingsIcon, ShieldIcon } from "lucide-react"
import { useTranslation } from "react-i18next"

import { Avatar, AvatarFallback } from "@/components/ui/avatar"
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu"
import { SidebarMenu, SidebarMenuButton, SidebarMenuItem } from "@/components/ui/sidebar"
import { useSharedProps } from "@/hooks/use-shared-props"
import { routes } from "@/generated/routes"
import { initials } from "@/lib/format"

/** Who is signed in, their settings, the admin area (superadmins) and sign out. */
export function UserMenu() {
  const { t } = useTranslation()
  const { auth } = useSharedProps()
  if (!auth) return null
  const { user } = auth

  return (
    <SidebarMenu>
      <SidebarMenuItem>
        <DropdownMenu>
          <DropdownMenuTrigger asChild>
            <SidebarMenuButton size="lg" className="data-[state=open]:bg-sidebar-accent">
              <Avatar className="size-8 rounded-lg">
                <AvatarFallback className="rounded-lg bg-secondary">{initials(user.name || user.email)}</AvatarFallback>
              </Avatar>
              <span className="grid flex-1 text-left leading-tight">
                <span className="truncate font-medium">{user.name || user.email}</span>
                <span className="truncate text-xs text-muted-foreground">{user.email}</span>
              </span>
              <ChevronsUpDownIcon className="ml-auto" aria-hidden="true" />
            </SidebarMenuButton>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end" side="top" className="w-60">
            <DropdownMenuLabel className="truncate">{user.email}</DropdownMenuLabel>
            <DropdownMenuSeparator />
            <DropdownMenuItem asChild>
              <Link href={routes.settingsProfile.edit().url}>
                <SettingsIcon aria-hidden="true" /> {t("nav.settings")}
              </Link>
            </DropdownMenuItem>
            {auth.superadmin && (
              <DropdownMenuItem asChild>
                <Link href={routes.adminDashboard.show().url}>
                  <ShieldIcon aria-hidden="true" /> {t("nav.admin")}
                </Link>
              </DropdownMenuItem>
            )}
            <DropdownMenuSeparator />
            <DropdownMenuItem onSelect={() => router.delete(routes.session.delete().url)}>
              <LogOutIcon aria-hidden="true" /> {t("nav.sign_out")}
            </DropdownMenuItem>
          </DropdownMenuContent>
        </DropdownMenu>
      </SidebarMenuItem>
    </SidebarMenu>
  )
}
