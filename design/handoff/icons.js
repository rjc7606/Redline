// Redline icon map — Tabler Icons (outline), loaded from the Tabler webfont CDN as class "ti ti-<name>". MIT licensed.
// Tools that carry live style (shape fills, text-box border) plus line/double arrow/polyline keep the inline SVG in the app.
window.REDLINE_ICONS = {
  // draw
  eraser: { fi: 'eraser' },
  arrow: { fi: 'arrow-up-right' }, check: { fi: 'check' }, xmark: { fi: 'x' },
  distance: { fi: 'ruler-measure' }, perimeter: { fi: 'vector' }, area: { fi: 'dimensions' }, calibrate: { fi: 'ruler-3' },
  // annotate
  select: { fi: 'pointer' }, lasso: { fi: 'lasso' }, highlighter: { fi: 'highlight' }, underline: { fi: 'underline' }, strike: { fi: 'strikethrough' }, squiggly: { fi: 'scribble' },
  note: { fi: 'note' }, callout: { fi: 'message' }, stamps: { fi: 'rubber-stamp' }, signature: { fi: 'signature' }, datestamp: { fi: 'calendar-check' }, initials: { fi: 'letter-case' },
  // edit
  edittext: { fi: 'text-recognition' }, image: { fi: 'photo-plus' }, link: { fi: 'link' }, rotatepg: { fi: 'rotate-clockwise' }, insertpg: { fi: 'file-plus' }, duplicatepg: { fi: 'copy' },
  deletepg: { fi: 'trash' }, extract: { fi: 'file-export' }, append: { fi: 'paperclip' }, reorder: { fi: 'list' }, crop: { fi: 'crop' }, redact: { fi: 'eye-off' },
  // forms
  ftext: { fi: 'forms' }, fcheck: { fi: 'square-check' }, fdrop: { fi: 'select' }, fdate: { fi: 'calendar' }, fsig: { fi: 'signature' }, ftoggle: { fi: 'toggle-right' },
  // chrome
  ruler: { fi: 'ruler-2' }, undo: { fi: 'arrow-back-up' }, redo: { fi: 'arrow-forward-up' }, zoomin: { fi: 'zoom-in' }, zoomout: { fi: 'zoom-out' }, share: { fi: 'share-2' }, search: { fi: 'search' }
};
// custom outline glyphs (drawn on Tabler's grid): the four pens are upright, tip-up close-ups so the nib shape reads at 20px; shapes, line/arrows, and three where Tabler has no true match — bucket fill, text area, radio button
window.REDLINE_ICON_KEEP_SVG = ['rect', 'ellipse', 'polygon', 'cloud', 'textbox', 'line', 'dblarrow', 'polyline', 'fill', 'farea', 'fradio', 'pen', 'fineliner', 'felt', 'marker'];
