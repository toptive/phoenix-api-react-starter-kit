import { Link } from "@/components/app/link"
import { useNavigate } from "@tanstack/react-router"
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
import { useAppConfig } from "@/api/hooks/bootstrap"
import { useSwitchOrganization } from "@/api/hooks/auth"
import { FormError } from "./form-error"
import { paths } from "@/lib/paths"

/** Shows the current organization; lets people who belong to several switch. */
export function OrganizationSwitcher() {
  const { t } = useTranslation()
  const navigate = useNavigate()
  const switchOrg = useSwitchOrganization()
  const { auth, app } = useAppConfig()
  if (!auth) return null

  const current = auth.organization
  const single = app.tenancy === "single"

  return (
    <SidebarMenu>
      <SidebarMenuItem>
        <DropdownMenu>
          <DropdownMenuTrigger asChild disabled={single}>
            <SidebarMenuButton size="lg" disabled={switchOrg.isPending} className="data-[state=open]:bg-sidebar-accent">
              <span className="flex size-8 items-center justify-center rounded-lg bg-primary text-primary-foreground">
                <Building2Icon className="size-4" aria-hidden="true" />
              </span>
              <span className="grid flex-1 text-left leading-tight">
                <span className="truncate font-semibold">{current.name}</span>
                <span className="truncate text-xs text-muted-foreground">
                  {t(`level.${auth.membership.role}_${auth.membership.access}`)}
                </span>
              </span>
              {!single && <ChevronsUpDownIcon className="ml-auto" aria-hidden="true" />}
            </SidebarMenuButton>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="start" className="w-64">
            <DropdownMenuLabel>{t("organizations.switch")}</DropdownMenuLabel>
            {auth.organizations.map((organization) => (
              <DropdownMenuItem
                key={organization.id}
                disabled={switchOrg.isPending || organization.id === current.id}
                className="min-h-11"
                onSelect={() =>
                  switchOrg.mutate(organization.id, {
                    onSuccess: () => {
                      void navigate({ to: paths.dashboard })
                    },
                  })
                }
              >
                <span className="flex-1 truncate">{organization.name}</span>
                {organization.id === current.id && <CheckIcon aria-hidden="true" />}
              </DropdownMenuItem>
            ))}
            <DropdownMenuSeparator />
            <DropdownMenuItem asChild className="min-h-11">
              <Link href={paths.newOrganization}>
                <PlusIcon aria-hidden="true" /> {t("organizations.create")}
              </Link>
            </DropdownMenuItem>
          </DropdownMenuContent>
        </DropdownMenu>
        <FormError error={switchOrg.error} />
      </SidebarMenuItem>
    </SidebarMenu>
  )
}
