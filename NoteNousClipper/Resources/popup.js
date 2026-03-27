// NoteNous Clipper — Popup Logic (Safari)

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

  // Request page info from content script
  browser.tabs
    .query({ active: true, currentWindow: true })
    .then((tabs) => {
      if (tabs.length === 0) return;
      const tab = tabs[0];

      titleInput.value = tab.title || '';
      urlDisplay.textContent = tab.url || '';

      return browser.tabs.sendMessage(tab.id, { action: 'getPageInfo' });
    })
    .then((response) => {
      if (!response) return;
      pageData = response;

      if (response.selectedText) {
        selectionGroup.style.display = 'block';
        selectionDisplay.textContent = response.selectedText;
      }
    })
    .catch((err) => {
      console.log('Could not get page info:', err);
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

    // Send to native app handler which forwards to ClipServer
    browser.runtime
      .sendNativeMessage('application.id', clipData)
      .then((response) => {
        if (response && response.success) {
          clipForm.style.display = 'none';
          clipSuccess.style.display = 'block';
          setTimeout(() => window.close(), 1500);
        } else {
          showError(response?.error || 'Failed to save clip');
        }
      })
      .catch((err) => {
        showError(err.message || 'NoteNous app is not running. Please open NoteNous first.');
      });
  });

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
