// NoteNous Clipper — Content Script (Safari)

browser.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message.action === 'getPageInfo') {
    const selectedText = window.getSelection().toString().trim();
    const pageContent = document.body ? document.body.innerText.substring(0, 5000) : '';

    sendResponse({
      title: document.title,
      url: window.location.href,
      selectedText: selectedText,
      pageContent: pageContent,
    });
  }
});
