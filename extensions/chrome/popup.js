// NoteNous Clipper — Popup Logic (Chrome)

const CLIP_SERVER_URL = 'http://localhost:23847/api/clip';

document.addEventListener('DOMContentLoaded', () => {
  const titleInput = document.getElementById('clip-title');
  const urlDisplay = document.getElementById('clip-url');
  const selectionGroup = document.getElementById('selection-group');
  const selectionDisplay = document.getElementById('clip-selection');
  const contextInput = document.getElementById('clip-context');
  const tagsInput = document.getElementById('clip-tags');
  const clipBtn = document.getElementById('clip-btn');
  const clipForm = document.getElementById('clip-form');
  const clipSuccess = document.getElementById('clip-success');
  const clipError = document.getElementById('clip-error');
  const connectionStatus = document.getElementById('connection-status');
  const typeBtns = document.querySelectorAll('.type-btn');

  let selectedType = 0;
  let pageData = {};

  // Type picker
  typeBtns.forEach((btn) => {
    btn.addEventListener('click', () => {
      typeBtns.forEach((b) => b.classList.remove('active'));
      btn.classList.add('active');
      selectedType = parseInt(btn.dataset.type, 10);
    });
  });

  // Check server connectivity
  checkServer();

  // Request page info from content script
  chrome.tabs.query({ active: true, currentWindow: true }, (tabs) => {
    if (tabs.length === 0) return;
    const tab = tabs[0];

    titleInput.value = tab.title || '';
    urlDisplay.textContent = tab.url || '';

    chrome.tabs.sendMessage(tab.id, { action: 'getPageInfo' }, (response) => {
      if (chrome.runtime.lastError) {
        console.log('Could not get page info:', chrome.runtime.lastError.message);
        return;
      }
      if (!response) return;
      pageData = response;

      if (response.selectedText) {
        selectionGroup.style.display = 'block';
        selectionDisplay.textContent = response.selectedText;
      }
    });
  });

  // Clip button
  clipBtn.addEventListener('click', () => {
    clipBtn.disabled = true;
    clipBtn.textContent = 'CLIPPING...';

    const tags = tagsInput.value
      .split(',')
      .map((t) => t.trim())
      .filter((t) => t.length > 0);

    const clipData = {
      title: titleInput.value,
      url: urlDisplay.textContent,
      selectedText: pageData.selectedText || '',
      pageContent: pageData.pageContent || '',
      noteType: selectedType,
      context: contextInput.value,
      tags: tags,
    };

    // Option A: POST to local ClipServer
    sendToClipServer(clipData)
      .then((response) => {
        if (response.success) {
          clipForm.style.display = 'none';
          clipSuccess.style.display = 'block';
          setTimeout(() => window.close(), 1500);
        } else {
          showError(response.error || 'Failed to save clip');
        }
      })
      .catch(() => {
        // Option B: Fallback to clipboard
        fallbackToClipboard(clipData);
      });
  });

  async function sendToClipServer(data) {
    const response = await fetch(CLIP_SERVER_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(data),
    });

    if (!response.ok) {
      throw new Error(`Server responded with ${response.status}`);
    }

    return response.json();
  }

  function fallbackToClipboard(data) {
    const formatted = JSON.stringify(
      {
        _notenous_clip: true,
        ...data,
      },
      null,
      2
    );

    navigator.clipboard
      .writeText(formatted)
      .then(() => {
        clipForm.style.display = 'none';
        clipSuccess.style.display = 'block';
        document.querySelector('.success-text').textContent =
          'Copied to clipboard — paste in NoteNous';
        setTimeout(() => window.close(), 2500);
      })
      .catch((err) => {
        showError('Could not connect to NoteNous or copy to clipboard');
      });
  }

  function checkServer() {
    fetch(CLIP_SERVER_URL.replace('/api/clip', '/health'), {
      method: 'GET',
      signal: AbortSignal.timeout(2000),
    })
      .then((res) => {
        if (res.ok) {
          connectionStatus.textContent = 'NoteNous connected';
          connectionStatus.className = 'connection-status connected';
        } else {
          connectionStatus.textContent = 'NoteNous not running — will copy to clipboard';
          connectionStatus.className = 'connection-status disconnected';
        }
      })
      .catch(() => {
        connectionStatus.textContent = 'NoteNous not running — will copy to clipboard';
        connectionStatus.className = 'connection-status disconnected';
      });
  }

  function showError(message) {
    clipBtn.disabled = false;
    clipBtn.textContent = 'CLIP';
    clipError.style.display = 'block';
    clipError.querySelector('.error-text').textContent = message;
    setTimeout(() => {
      clipError.style.display = 'none';
    }, 3000);
  }
});
