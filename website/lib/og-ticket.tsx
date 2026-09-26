import React from "react";

/**
 * Link-preview cards in the Booth Light language: one paper ticket on the
 * booth. Satori (next/og) has no CSS masks, so the notches are booth-coloured
 * discs laid over the edge - which is exactly what a punched hole looks like
 * on a flat background.
 */
export const OG_BOOTH = "#121010";
export const OG_SCREEN = "#F4ECDF";
export const OG_INK = "#121010";
export const OG_MUTED = "#5A4F44";
export const OG_LIVE = "#A33A22";

const STUB = 250;
const NOTCH = 22;

export function OgTicket({
  eyebrow,
  title,
  detail,
  facts,
  stub,
}: {
  eyebrow: string;
  title: string;
  detail: string;
  facts?: string[];
  stub: string;
}) {
  return (
    <div
      style={{
        width: "100%",
        height: "100%",
        display: "flex",
        flexDirection: "column",
        justifyContent: "center",
        padding: "0 72px",
        background: OG_BOOTH,
      }}
    >
      <div
        style={{
          display: "flex",
          fontSize: 26,
          letterSpacing: 2,
          color: OG_SCREEN,
          marginBottom: 28,
          fontWeight: 800,
        }}
      >
        sync<span style={{ color: "#FFB23F" }}>·</span>together
      </div>
      <div
        style={{
          position: "relative",
          display: "flex",
          height: 380,
          borderRadius: 8,
          background: OG_SCREEN,
          color: OG_INK,
        }}
      >
        <div
          style={{
            display: "flex",
            flexDirection: "column",
            justifyContent: "space-between",
            flexGrow: 1,
            padding: "44px 52px",
          }}
        >
          <div style={{ display: "flex", fontSize: 22, letterSpacing: 4, color: OG_LIVE }}>
            {eyebrow.toUpperCase()}
          </div>
          <div style={{ display: "flex", flexDirection: "column" }}>
            <div style={{ display: "flex", fontSize: 64, fontWeight: 800, lineHeight: 1.02, letterSpacing: -2 }}>
              {title}
            </div>
            <div style={{ display: "flex", marginTop: 16, fontSize: 30, color: OG_MUTED }}>{detail}</div>
          </div>
          {facts && facts.length > 0 ? (
            <div style={{ display: "flex", gap: 36, fontSize: 24, color: OG_MUTED, letterSpacing: 1 }}>
              {facts.map((f) => (
                <div key={f} style={{ display: "flex" }}>
                  {f}
                </div>
              ))}
            </div>
          ) : (
            <div style={{ display: "flex" }} />
          )}
        </div>
        <div
          style={{
            display: "flex",
            width: STUB,
            alignItems: "center",
            justifyContent: "center",
            borderLeft: "3px dashed #B8AB98",
            fontSize: 34,
            fontWeight: 700,
            letterSpacing: 4,
          }}
        >
          {stub}
        </div>
        {[-NOTCH, 380 - NOTCH].map((top) => (
          <div
            key={top}
            style={{
              position: "absolute",
              top,
              right: STUB - NOTCH,
              width: NOTCH * 2,
              height: NOTCH * 2,
              borderRadius: NOTCH,
              background: OG_BOOTH,
            }}
          />
        ))}
      </div>
    </div>
  );
}
