// Runs on YouTube / YouTube Music. Reports title, position and play state to the
// background script. Reports on events (play, pause, seek, ...) plus a slow heartbeat;
// the desktop app keeps its own clock between reports, so background-tab timer
// throttling doesn't matter.
(() => {
  const isMusicApp = location.hostname === "music.youtube.com";
  let video = null;
  let lastKey = "";
  let tick = 0;

  const text = (sel) => (document.querySelector(sel)?.textContent || "").trim();

  function isWatchPage() {
    // Ignore homepage hover previews, Shorts, etc.
    return isMusicApp || location.pathname === "/watch";
  }

  function readMeta() {
    const ms = navigator.mediaSession && navigator.mediaSession.metadata;
    const title = (ms && ms.title)
      || text("ytd-watch-metadata h1")
      || document.title.replace(/ - (YouTube|YouTube Music)$/, "");
    const channel = text("ytd-watch-metadata ytd-channel-name a")
      || text("ytd-video-owner-renderer ytd-channel-name a")
      || (ms && ms.artist) || "";
    return {
      title,
      channel,
      artist: isMusicApp && ms && ms.artist ? ms.artist : null,
    };
  }

  function snapshot() {
    if (!video || !isWatchPage()) return null;
    const meta = readMeta();
    if (!meta.title) return null;
    const player = document.querySelector(".html5-video-player");
    return {
      videoId: new URLSearchParams(location.search).get("v"),
      ...meta,
      duration: Number.isFinite(video.duration) ? video.duration : null,
      position: video.currentTime,
      playing: !video.paused && !video.ended,
      rate: video.playbackRate,
      ad: !!(player && player.classList.contains("ad-showing")),
    };
  }

  function send() {
    const s = snapshot();
    if (!s) return;
    lastKey = `${s.videoId}|${s.title}|${s.ad}`;
    browser.runtime.sendMessage(s).catch(() => {});
  }

  function attach() {
    const v = document.querySelector("video.html5-main-video") || document.querySelector("video");
    if (v === video) return;
    video = v;
    if (!video) return;
    for (const ev of ["play", "playing", "pause", "seeked", "ratechange", "loadedmetadata", "ended"]) {
      video.addEventListener(ev, send);
    }
    send();
  }

  // 1s housekeeping: pick up a replaced <video>, detect song/ad changes after
  // SPA navigation, and send a heartbeat every ~4s while playing.
  setInterval(() => {
    attach();
    const s = snapshot();
    if (!s) return;
    const key = `${s.videoId}|${s.title}|${s.ad}`;
    tick = (tick + 1) % 4;
    if (key !== lastKey || (s.playing && tick === 0)) send();
  }, 1000);
})();
