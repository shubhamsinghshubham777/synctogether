/**
 * Navigate to a `synctogether://` link after the current frame has painted.
 *
 * Assigning a custom-scheme URL makes the browser raise its native "Open
 * SyncTogether?" prompt synchronously, and the frame that would show the
 * click's feedback waits behind it - which Speed Insights records as a slow
 * interaction (INP) on every page that hands off to the app. Yielding one
 * frame lets the click paint first; the prompt follows a few ms later.
 */
export function openAppLink(url: string) {
  requestAnimationFrame(() => {
    setTimeout(() => {
      window.location.href = url;
    }, 0);
  });
}
