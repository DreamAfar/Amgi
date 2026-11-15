//
//  RichFieldPage.swift
//  BrowseFeature
//

import Foundation

/// The page a note field is edited in: one `contenteditable` element whose
/// HTML *is* the field's HTML, so whatever the field holds — formatting,
/// images, tables from another client — round-trips untouched.
///
/// App → page: `amgi.set(html)`, `amgi.exec(command, value)`,
/// `amgi.wrap(prefix, suffix)`, `amgi.insertImage(filename)`,
/// `amgi.setColors(text, accent)`, `amgi.blur()`.
///
/// Page → app, through the `amgi` message handler, as `{name, …}`:
/// `ready`, `change {html}` (only for edits made in the page — `set` never
/// echoes, so a field nobody touched is never rewritten), `height
/// {height}`, `state {bold, italic, …}`, `focus`, `blur`, and `image
/// {index, src, width, x, y, w, h}` when an image is tapped (answered with
/// `amgi.imageAction(index, action, value)` or `amgi.clearImage()`).
enum RichFieldPage {
    static let messageHandler = "amgi"

    static func html(textColor: String, caretColor: String) -> String {
        template
            .replacingOccurrences(of: "__COLOR__", with: textColor)
            .replacingOccurrences(of: "__ACCENT__", with: caretColor)
    }

    private static let template = #"""
<!doctype html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
<style>
:root { color-scheme: light dark; }
html, body { margin: 0; padding: 0; background: transparent; -webkit-text-size-adjust: none; }
body { font: -apple-system-body; color: __COLOR__; overflow-wrap: anywhere; }
#f { outline: none; min-height: 1.3em; padding: 4px 0; caret-color: __ACCENT__; -webkit-user-select: text; -webkit-tap-highlight-color: transparent; }
#f img { max-width: 100%; max-height: 220px; height: auto; vertical-align: bottom; border-radius: 6px; }
#f ul, #f ol { margin: 0.2em 0; padding-left: 1.5em; }
#f blockquote { margin: 0 0 0 1.5em; }
#sel { position: absolute; display: none; pointer-events: none; box-sizing: border-box; border: 2px solid __ACCENT__; border-radius: 6px; }
</style>
</head>
<body>
<div id="f" contenteditable="true" spellcheck="true"></div>
<div id="sel"></div>
<script>
(function () {
  var f = document.getElementById('f');
  // Outline of the tapped image. Kept outside the field so it never ends
  // up in the stored HTML.
  var sel = document.getElementById('sel');
  var last = '';
  var lastHeight = -1;
  var saved = null;
  var pending = 0;

  function send(name, body) {
    var message = body || {};
    message.name = name;
    try { window.webkit.messageHandlers.amgi.postMessage(message); } catch (e) {}
  }

  // An emptied field is left holding a lone <br>; store that as empty.
  function html() {
    var h = f.innerHTML;
    return (h === '<br>' || h === '<div><br></div>') ? '' : h;
  }

  function reportHeight() {
    var h = Math.ceil(f.getBoundingClientRect().height);
    if (h !== lastHeight) { lastHeight = h; send('height', { height: h }); }
  }

  function changed() {
    var h = html();
    if (h !== last) { last = h; send('change', { html: h }); }
    reportHeight();
  }

  function selectionInField() {
    var s = window.getSelection();
    return s.rangeCount > 0 && f.contains(s.anchorNode);
  }

  function inside(tag) {
    var s = window.getSelection();
    var n = s.rangeCount ? s.anchorNode : null;
    while (n && n !== f) {
      if (n.nodeName === tag) { return true; }
      n = n.parentNode;
    }
    return false;
  }

  function query(command) {
    try { return document.queryCommandState(command); } catch (e) { return false; }
  }

  function reportState() {
    pending = 0;
    if (!selectionInField()) { return; }
    saved = window.getSelection().getRangeAt(0).cloneRange();
    send('state', {
      bold: query('bold'),
      italic: query('italic'),
      underline: query('underline'),
      strike: query('strikeThrough'),
      sub: query('subscript'),
      sup: query('superscript'),
      ul: query('insertUnorderedList'),
      ol: query('insertOrderedList'),
      align: query('justifyCenter') ? 'center' : (query('justifyRight') ? 'right' : 'left')
    });
  }

  function scheduleState() {
    if (!pending) { pending = window.requestAnimationFrame(reportState); }
  }

  // Puts the caret back where it was when the field last had it, for
  // commands that arrive after focus went elsewhere (the image sheet).
  function restore() {
    if (selectionInField()) { return; }
    f.focus({ preventScroll: true });
    var s = window.getSelection();
    s.removeAllRanges();
    if (saved) {
      s.addRange(saved);
    } else {
      var r = document.createRange();
      r.selectNodeContents(f);
      r.collapse(false);
      s.addRange(r);
    }
  }

  function escapeHTML(text) {
    return text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  }

  window.amgi = {
    // Replaces the content from the app side. Never echoes a change back.
    set: function (value) {
      if (value === last) { return; }
      f.innerHTML = value;
      last = value;
      saved = null;
      reportHeight();
    },

    exec: function (command, value) {
      restore();
      var s = window.getSelection();
      if (command === 'removeFormat' && s.isCollapsed) {
        // No selection: clear the whole field's formatting, then put the
        // caret at the end.
        var all = document.createRange();
        all.selectNodeContents(f);
        s.removeAllRanges();
        s.addRange(all);
        document.execCommand('removeFormat', false, null);
        s.collapseToEnd();
      } else {
        // Highlight needs CSS output; everything else uses plain tags
        // (<b>, <i>, <font color>), which is what Anki's editor writes.
        document.execCommand('styleWithCSS', false, command === 'hiliteColor');
        document.execCommand(command, false, value === undefined ? null : value);
        document.execCommand('styleWithCSS', false, false);
      }
      changed();
      reportState();
    },

    // Wraps the selection, or inserts the pair and leaves the caret
    // between them — used for MathJax delimiters.
    wrap: function (prefix, suffix) {
      restore();
      var s = window.getSelection();
      var text = s.toString();
      document.execCommand('insertText', false, prefix + text + suffix);
      if (!text) {
        for (var i = 0; i < suffix.length; i++) { s.modify('move', 'backward', 'character'); }
      }
      changed();
      reportState();
    },

    insertImage: function (filename) {
      restore();
      document.execCommand('insertHTML', false, '<img src="' + escapeHTML(filename) + '">');
      changed();
      reportState();
    },

    setColors: function (text, accent) {
      document.body.style.color = text;
      f.style.caretColor = accent;
      sel.style.borderColor = accent;
    },

    clearImage: function () { sel.style.display = 'none'; },

    // Acts on the field's index-th image: 'remove', 'width' (a value, or
    // empty for the original size) or 'src' (a new filename).
    imageAction: function (index, action, value) {
      var img = f.querySelectorAll('img')[index];
      window.amgi.clearImage();
      if (!img) { return; }
      if (action === 'remove') {
        // Delete through the editing command so Undo brings it back.
        f.focus({ preventScroll: true });
        var r = document.createRange();
        r.selectNode(img);
        var s = window.getSelection();
        s.removeAllRanges();
        s.addRange(r);
        document.execCommand('delete', false, null);
      } else if (action === 'width') {
        img.removeAttribute('height');
        if (value) { img.setAttribute('width', value); } else { img.removeAttribute('width'); }
      } else if (action === 'src') {
        img.setAttribute('src', value);
      }
      changed();
    },

    blur: function () { f.blur(); }
  };

  f.addEventListener('input', changed);

  // Tapping an image outlines it and asks the app for the image menu,
  // instead of dropping the caret beside it.
  f.addEventListener('click', function (event) {
    var img = event.target;
    if (!img || img.nodeName !== 'IMG') { return; }
    event.preventDefault();
    var r = img.getBoundingClientRect();
    sel.style.left = (r.left + window.scrollX) + 'px';
    sel.style.top = (r.top + window.scrollY) + 'px';
    sel.style.width = r.width + 'px';
    sel.style.height = r.height + 'px';
    sel.style.display = 'block';
    send('image', {
      index: Array.prototype.indexOf.call(f.querySelectorAll('img'), img),
      src: img.getAttribute('src') || '',
      width: img.getAttribute('width') || '',
      x: r.left, y: r.top, w: r.width, h: r.height
    });
  }, true);

  // Return adds a line break, as Anki's editor does, rather than a new
  // <div> block — except in a list, where it starts the next item.
  f.addEventListener('beforeinput', function (event) {
    if (event.inputType === 'insertParagraph' && !inside('LI')) {
      event.preventDefault();
      document.execCommand('insertLineBreak', false, null);
    }
  });

  // Paste as plain text: clipboard HTML carries the source page's fonts,
  // sizes and colors, which don't belong in a note field.
  f.addEventListener('paste', function (event) {
    var data = event.clipboardData;
    if (!data) { return; }
    var text = data.getData('text/plain');
    if (!text) { return; }
    event.preventDefault();
    var markup = escapeHTML(text).replace(/\r\n|\r|\n/g, '<br>');
    document.execCommand('insertHTML', false, markup);
  });

  f.addEventListener('focus', function () { send('focus'); scheduleState(); });
  f.addEventListener('blur', function () { send('blur'); });
  f.addEventListener('load', reportHeight, true);
  document.addEventListener('selectionchange', scheduleState);
  if (window.ResizeObserver) { new ResizeObserver(reportHeight).observe(f); }

  send('ready');
})();
</script>
</body>
</html>
"""#
}
