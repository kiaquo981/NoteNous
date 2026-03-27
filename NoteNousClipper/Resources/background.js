// NoteNous Clipper — Background Service Worker (Safari)

// Relay messages between popup and native app handler
browser.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message.action === 'clip') {
    browser.runtime
      .sendNativeMessage('com.notenous.app.clipper', message.data)
      .then((response) => {
        sendResponse(response);
      })
      .catch((error) => {
        sendResponse({ success: false, error: error.message });
      });
    return true; // async response
  }
});
