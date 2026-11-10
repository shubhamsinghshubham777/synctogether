import { preload } from "react-dom";
import { Ticket } from "@/components/Ticket";
import { HeroScrubEngine } from "@/components/hero/HeroScrubEngine";
import {
  FRAME_COUNT,
  START_SECONDS,
  TOTAL_SECONDS,
  formatTimecode,
  frameIndex,
  spokenTime,
} from "@/components/hero/scrub/machine";

const STRIP = "/film/drift-strip-11.avif";
const ROOT_ID = "hero-scrub";

const mono = "font-[family-name:var(--font-jetbrains-mono)]";
const display = "font-[family-name:var(--font-space-grotesk)]";

const SEATS = [
  { who: "MAYA", device: "IPAD", name: "Maya's iPad" },
  { who: "DEV", device: "WINDOWS", name: "Dev's Windows laptop" },
  { who: "KAI", device: "IPHONE", name: "Kai's iPhone" },
] as const;

const startFrame = frameIndex(START_SECONDS / TOTAL_SECONDS);
const startShift = `translate3d(${(-startFrame * 100) / FRAME_COUNT}%,0,0)`;
const startP = START_SECONDS / TOTAL_SECONDS;

/** One window onto the 11-frame strip. The engine only moves the image's transform. */
function Film({ index, priority = false }: { index: number; priority?: boolean }) {
  return (
    <div className="scrub-film" aria-hidden="true">
      {/* eslint-disable-next-line @next/next/no-img-element -- a 5280px filmstrip shifted by transform; next/image would resize it */}
      <img
        data-strip={index}
        src={STRIP}
        alt=""
        width={5280}
        height={270}
        decoding="async"
        fetchPriority={priority ? "high" : "auto"}
        style={{ transform: startShift }}
      />
    </div>
  );
}

/**
 * The hero's right side: four screens on one film. It does what the app does:
 * while you scrub only your own screen moves, and on release everyone lands on
 * your frame together (docs/hero-scrub-spec.md, canvas boards 74-81). This is
 * the whole no-JS fallback too: same frame, every seat IN SYNC, the strip line. `HeroScrubEngine` (client, renders nothing) enhances it after
 * hydration; the engine only changes attributes, transforms and text, so
 * nothing here is ever added, removed or reordered at runtime.
 */
export function HeroScrub({ className = "" }: { className?: string }) {
  preload(STRIP, { as: "image", fetchPriority: "high" });

  return (
    <section
      id={ROOT_ID}
      className={`scrub @container ${className}`}
      data-state="static"
      aria-labelledby="scrub-title"
    >
      <p id="scrub-title" className="sr-only">
        Demo room: four screens on one playhead.
      </p>
      <p className="sr-only">
        Four screens show the same frame of a film. Drag the playhead and only your screen moves;
        when you let go, the other three jump to your frame. The other three seats are a
        simulation.
      </p>

      <div className="scrub-host">
        <div className={`scrub-head ${mono}`}>
          <span className="flex items-center gap-2 min-w-0">
            <span className="scrub-dot" aria-hidden="true" />
            <span className="font-[family-name:var(--font-outfit)] font-semibold text-screen truncate">movie night</span>
            <span className="scrub-code">K7Q2ZP</span>
          </span>
          <span className="scrub-state" data-scrub-state>
            IN SYNC · 4 SEATS
          </span>
        </div>
        <Film index={0} priority />
      </div>

      <div className="scrub-rail">
        <span className={`scrub-time ${mono}`} data-time>
          {formatTimecode(START_SECONDS)}
        </span>
        <div className="scrub-zone" data-zone>
          <div className="scrub-track" />
          <div className="scrub-fill" data-fill style={{ transform: `scaleX(${startP})` }} />
          {/* Where the seats are: shown only while dragging (the committed position). */}
          <div className="scrub-tickbox" data-tick aria-hidden="true" style={{ transform: `translateX(${startP * 100}%)` }}>
            <span className={`scrub-tick ${mono}`}>
              <span>SEATS</span>
            </span>
          </div>
          <div className="scrub-carriage" data-carriage style={{ transform: `translateX(${startP * 100}%)` }}>
            <div className="scrub-nudge">
              <div
                className="scrub-handle"
                role="slider"
                tabIndex={0}
                data-handle
                aria-label="Playhead"
                aria-orientation="horizontal"
                aria-valuemin={0}
                aria-valuemax={TOTAL_SECONDS}
                aria-valuenow={START_SECONDS}
                aria-valuetext={`${spokenTime(START_SECONDS)} of 2 hours 49 minutes. Maya, Dev and Kai catch up when you let go.`}
              >
                <span className="scrub-bar" />
              </div>
              <span className={`scrub-chip ${mono}`} aria-hidden="true">
                <span className="scrub-chip-hint">
                  <svg width="5" height="8" viewBox="0 0 5 8" fill="none" aria-hidden="true">
                    <path d="M4 1 1 4l3 3" stroke="currentColor" strokeWidth="1.6" strokeLinecap="square" />
                  </svg>
                  DRAG
                  <svg width="5" height="8" viewBox="0 0 5 8" fill="none" aria-hidden="true">
                    <path d="m1 1 3 3-3 3" stroke="currentColor" strokeWidth="1.6" strokeLinecap="square" />
                  </svg>
                </span>
                <span className="scrub-chip-time" data-chip-time>
                  {formatTimecode(START_SECONDS)}
                </span>
              </span>
            </div>
          </div>
        </div>
        <span className={`scrub-total ${mono}`}>{formatTimecode(TOTAL_SECONDS)}</span>
      </div>

      <ul className="scrub-seats">
        {SEATS.map((s, i) => (
          <li
            key={s.who}
            className="scrub-tile"
            role="img"
            data-seat="sync"
            data-name={s.name}
            aria-label={`${s.name}, simulated, in sync`}
          >
            <Film index={i + 1} />
            <div className={`scrub-foot ${mono}`}>
              <span className="scrub-seat-name">
                <span className="@max-[399px]:hidden">{s.who} · </span>
                {s.device}
              </span>
              <span className="scrub-status" aria-hidden="true">
                <i data-on="sync">IN SYNC</i>
                <i data-on="wait">WAITING</i>
              </span>
            </div>
          </li>
        ))}
      </ul>

      <div className="scrub-strip" data-copy="idle">
        <Ticket
          compact
          stubClassName="w-[80px] @max-[399px]:w-[64px]"
          className="w-[236px] shrink-0 @max-[399px]:w-[204px]"
          stub={<span className={`${mono} text-[12px] font-semibold tracking-[0.04em]`}>K7Q2ZP</span>}
        >
          <p className={`${mono} text-[9px] tracking-[0.14em] whitespace-nowrap @max-[399px]:tracking-[0.04em] text-gray-600`}>ADMIT 4 · TONIGHT</p>
          <p className={`${display} mt-0.5 text-[14px] font-extrabold tracking-[-0.03em] leading-none whitespace-nowrap`}>
            Friday Horror Club
          </p>
        </Ticket>
        {/* Three messages stacked in one grid cell: each is its own block, so
            a short line sits centred against the ticket instead of hanging
            above a gap sized for the longest one. */}
        <div className="scrub-copy min-w-0">
          <div className="scrub-msg c-idle">
            <p className={`${display} scrub-line-1`}>Four couches. One playhead.</p>
            <p className={`${mono} scrub-line-2`}>DEMO ROOM · SEATS ARE SIMULATED</p>
          </div>
          <div className="scrub-msg c-drag">
            <p className={`${display} scrub-line-1`}>Only your screen moves. Let go.</p>
            <p className={`${mono} scrub-line-2`}>DEMO ROOM · SEATS ARE SIMULATED</p>
          </div>
          <div className="scrub-msg c-synced">
            <p className={`${display} scrub-line-1`}>
              Everyone landed on your frame.
              <span className="@max-[399px]:hidden"> Now try it with someone you miss.</span>
            </p>
            <p className={`${mono} scrub-line-2 scrub-line-free`}>DEMO ROOM · THE REAL ONE IS FREE</p>
          </div>
        </div>
      </div>

      <div className="sr-only" aria-live="polite" data-live />
      <HeroScrubEngine rootId={ROOT_ID} />
    </section>
  );
}
