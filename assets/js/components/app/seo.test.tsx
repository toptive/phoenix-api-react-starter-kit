import { describe, expect, it } from "vitest"

import { jsonLdText } from "@/components/app/seo"

describe("jsonLdText", () => {
  it("cannot close the script tag, and parses back to the same data", () => {
    const block = { "@type": "Organization", name: "</script><script>alert(1)</script>" }
    const text = jsonLdText(block)

    expect(text).not.toContain("<")
    expect(JSON.parse(text)).toEqual(block)
  })
})
