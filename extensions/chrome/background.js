// NoteNous Clipper — Background Service Worker (Chrome)

// No background processing needed for Chrome version.
// Communication flows: popup.js -> content.js (via chrome.tabs.sendMessage)
// Clip data goes directly from popup.js -> ClipServer (HTTP POST)
