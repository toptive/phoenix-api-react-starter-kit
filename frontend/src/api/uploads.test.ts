import { afterEach, describe, expect, it, vi } from "vitest"

import { UploadError, uploadFile } from "@/api/uploads"

afterEach(() => vi.unstubAllGlobals())

describe("uploadFile", () => {
  it("signs, PUTs to storage and returns the key", async () => {
    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce(
        new Response(
          JSON.stringify({
            data: {
              url: "https://s3/put",
              key: "uploads/k.png",
              method: "PUT",
              headers: { "content-type": "image/png" },
            },
          }),
          { status: 201 },
        ),
      )
      .mockResolvedValueOnce(new Response(null, { status: 200 }))
    vi.stubGlobal("fetch", fetchMock)

    const key = await uploadFile(new File(["x"], "k.png", { type: "image/png" }), "image")
    expect(key).toBe("uploads/k.png")
    expect(fetchMock.mock.calls[0]?.[0]).toBe("/api/v1/direct-uploads")
    expect(fetchMock.mock.calls[1]?.[0]).toBe("https://s3/put")
  })

  it("surfaces the server error envelope", async () => {
    vi.stubGlobal(
      "fetch",
      vi
        .fn()
        .mockResolvedValue(
          new Response(JSON.stringify({ error: { code: "too_large", message: "The file is too large." } }), {
            status: 422,
          }),
        ),
    )
    await expect(uploadFile(new File(["x"], "a.png", { type: "image/png" }), "image")).rejects.toBeInstanceOf(
      UploadError,
    )
  })
})
