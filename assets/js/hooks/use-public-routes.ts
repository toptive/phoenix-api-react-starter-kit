import { routes } from "@/generated/routes"
import { useSharedProps } from "@/hooks/use-shared-props"

/**
 * URLs of the public (SEO) pages in the current language: the default locale has no
 * prefix ("/legal/terms"), the others live under "/:locale" ("/es/legal/terms"), whose
 * locale param comes from the typelizer URL defaults set in app.tsx / ssr.tsx.
 */
export function usePublicRoutes() {
  const { locale, locales } = useSharedProps()
  const isDefault = locale === locales[0]

  return {
    home: () => (isDefault ? routes.home.show() : routes.localizedHome.show()).url,
    legal: (slug: string) => (isDefault ? routes.legalPage.show(slug) : routes.localizedLegalPage.show(slug)).url,
  }
}
