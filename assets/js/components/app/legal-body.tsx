/**
 * Renders a legal document body safely: blank lines separate paragraphs and lines that
 * start with "## " are headings. Never injects HTML.
 */
export function LegalBody({ body }: { body: string }) {
  const blocks = body.split(/\n{2,}/).map((block) => block.trim()).filter(Boolean)

  return (
    <div className="space-y-4 leading-7">
      {blocks.map((block, index) =>
        block.startsWith("## ") ? (
          <h2 key={index} className="pt-4 text-xl font-semibold">
            {block.slice(3)}
          </h2>
        ) : (
          <p key={index} className="whitespace-pre-line text-foreground/90">
            {block}
          </p>
        ),
      )}
    </div>
  )
}
