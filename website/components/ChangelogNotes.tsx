import ReactMarkdown from "react-markdown";
import remarkGfm from "remark-gfm";

/**
 * Release bodies are written for GitHub: a "What's Changed" heading, emoji
 * sub-headings and a Downloads list of bare filenames. The changelog shows
 * only the bullets, so those headings go (their items stay) and the Downloads
 * section is dropped entirely - the newest release gets real buttons instead.
 */
export function cleanReleaseBody(body: string): string {
  if (!body) return "";
  const out: string[] = [];
  let skipping = false;
  for (const line of body.split(/\r?\n/)) {
    const h = line.match(/^#{1,6}\s+(.*)$/);
    if (h) {
      const text = h[1].trim();
      if (/^downloads?\b/i.test(text)) { skipping = true; continue; }
      skipping = false;
      if (/^what'?s changed\b/i.test(text)) continue;
      // Emoji-led sub-headings ("🛠️ Improvements & Fixes", "✨ What's New").
      if (/^\p{Extended_Pictographic}/u.test(text)) continue;
      out.push(line);
      continue;
    }
    if (!skipping) out.push(line);
  }
  return (
    out
      .join("\n")
      .replace(/\n{3,}/g, "\n\n")
      // Release notes are free text from GitHub; the site sets no em or en
      // dashes, so a spaced one becomes a comma and a range becomes "to".
      .replace(/\s+[—–]\s+/g, ", ")
      .replace(/(\d)[–—](\d)/g, "$1 to $2")
      .replace(/[—–]/g, ", ")
      .trim()
  );
}

export function ChangelogNotes({ content, muted = false }: { content: string; muted?: boolean }) {
  if (!content) return null;
  const text = muted ? "text-gray-400" : "text-gray-300";
  return (
    <div className="space-y-3">
      <ReactMarkdown
        remarkPlugins={[remarkGfm]}
        components={{
          h1: ({ children }) => <h3 className="text-base font-bold text-white mt-5 first:mt-0">{children}</h3>,
          h2: ({ children }) => <h3 className="text-base font-bold text-white mt-5 first:mt-0">{children}</h3>,
          h3: ({ children }) => <h3 className="text-sm font-bold text-white mt-4 first:mt-0">{children}</h3>,
          h4: ({ children }) => <h4 className="text-sm font-semibold text-gray-200 mt-3 first:mt-0">{children}</h4>,
          p: ({ children }) => <p className={`${text} text-[15px] leading-relaxed`}>{children}</p>,
          ul: ({ children }) => (
            <ul className={`space-y-3 pl-5 list-disc ${muted ? "marker:text-gray-600" : "marker:text-beam-500"}`}>{children}</ul>
          ),
          ol: ({ children }) => <ol className="space-y-3 pl-5 list-decimal marker:text-gray-500">{children}</ol>,
          li: ({ children }) => <li className={`${text} text-[15px] leading-relaxed pl-1`}>{children}</li>,
          strong: ({ children }) => <strong className="text-white font-semibold">{children}</strong>,
          a: ({ href, children }) => (
            <a href={href} target="_blank" rel="noopener noreferrer" className="text-white underline underline-offset-4 decoration-rail hover:decoration-beam-500">
              {children}
            </a>
          ),
          code: ({ children }) => <code className="font-[family-name:var(--font-jetbrains-mono)] text-[0.85em] text-gray-200">{children}</code>,
        }}
      >
        {content}
      </ReactMarkdown>
    </div>
  );
}
