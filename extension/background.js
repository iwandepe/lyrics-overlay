// Holds the single WebSocket to the desktop app (ws://127.0.0.1:8765) and
// forwards whatever the YouTube content scripts report. Reconnects forever.
const URL = "ws://127.0.0.1:8765";
let ws = null;
let latest = null;

function connect() {
  ws = new WebSocket(URL);
  ws.onopen = () => { if (latest) ws.send(latest); };
  ws.onclose = () => { ws = null; setTimeout(connect, 3000); };
  ws.onerror = () => { try { ws.close(); } catch (_) {} };
}
connect();

browser.runtime.onMessage.addListener((msg) => {
  latest = JSON.stringify(msg);
  if (ws && ws.readyState === WebSocket.OPEN) ws.send(latest);
});
