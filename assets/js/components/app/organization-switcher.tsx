import { Link, router } from "@inertiajs/react"
import { Building2Icon, CheckIcon, ChevronsUpDownIcon, PlusIcon } from "lucide-react"
import { useTranslation } from "react-i18next"

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

/** Shows the current organization; lets people who belong to several switch. */
export function OrganizationSwitcher() {
  const { t } = useTranslation()
  const { auth, app } = useSharedProps()
  if (!auth) return null

  const current = auth.organization
  const single = app.tenancy === "single"

  return (
    <SidebarMenu>
      <SidebarMenuItem>
        <DropdownMenu>
          <DropdownMenuTrigger asChild disabled={single}>
            <SidebarMenuButton size="lg" className="data-[state=open]:bg-sidebar-accent">
              <span className="flex size-8 items-center justify-center rounded-lg bg-primary text-primary-foreground">
                <Building2Icon className="size-4" aria-hidden="true" />
              </span>
              <span className="grid flex-1 text-left leading-tight">
                <span className="truncate font-semibold">{current.name}</span>
                <span className="truncate text-xs text-muted-foreground">{t(`level.${auth.membership.role}_${auth.membership.access}`)}</span>
              </span>
              {!single && <ChevronsUpDownIcon className="ml-auto" aria-hidden="true" />}
            </SidebarMenuButton>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="start" className="w-64">
            <DropdownMenuLabel>{t("organizations.switch")}</DropdownMenuLabel>
            {auth.organizations.map((organization) => (
              <DropdownMenuItem
                key={organization.id}
                onSelect={() => router.patch(routes.currentOrganization.update().url, { organizationId: organization.id })}
              >
                <span className="flex-1 truncate">{organization.name}</span>
                {organization.id === current.id && <CheckIcon aria-hidden="true" />}
              </DropdownMenuItem>
            ))}
            <DropdownMenuSeparator />
            <DropdownMenuItem asChild>
              <Link href={routes.organization.new().url}>
                <PlusIcon aria-hidden="true" /> {t("organizations.create")}
              </Link>
            </DropdownMenuItem>
          </DropdownMenuContent>
        </DropdownMenu>
      </SidebarMenuItem>
    </SidebarMenu>
  )
}
