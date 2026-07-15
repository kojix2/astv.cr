const tree = document.getElementById('tree');
const textView = document.getElementById('textView');
const jsonView = document.getElementById('jsonView');
const tokenView = document.getElementById('tokenView');
const rubyInput = document.getElementById('rubyInput');
const parseBtn = document.getElementById('parseBtn');
const copyUrlBtn = document.getElementById('copyUrlBtn');
const rubyActionStatus = document.getElementById('rubyActionStatus');
const copyTextBtn = document.getElementById('copyTextBtn');
const copyJsonBtn = document.getElementById('copyJsonBtn');
const copyTokenBtn = document.getElementById('copyTokenBtn');
const rubyHighlight = document.getElementById('rubyHighlight');
const rubyLocLayer = document.getElementById('rubyLocLayer');
const tabButtons = Array.from(document.querySelectorAll('.tab-btn'));
const tabPanels = Array.from(document.querySelectorAll('.tab-panel'));
const expandAllBtn = document.getElementById('expandAllBtn');
const collapseAllBtn = document.getElementById('collapseAllBtn');
const rubyStatus = document.getElementById('rubyStatus');

let currentLoc = null;
let lastTokenText = '';

function typeOf(value) {
  if (value === null) return 'null';
  if (Array.isArray(value)) return 'array';
  return typeof value;
}

function isNodeObject(value) {
  return !!value && typeof value === 'object' && !Array.isArray(value) && Object.prototype.hasOwnProperty.call(value, 'type');
}

function isArrayOfNodeObjects(value) {
  if (!Array.isArray(value)) return false;
  if (value.length === 0) return false;
  return value.every(item => isNodeObject(item));
}

function extractLocation(obj) {
  if (!obj || typeof obj !== 'object') return null;
  const loc = obj.location;
  if (!loc || typeof loc !== 'object') return null;
  const required = ['start_line', 'start_column', 'end_line', 'end_column'];
  for (const key of required) {
    if (!Object.prototype.hasOwnProperty.call(loc, key)) return null;
  }
  return {
    startLine: Number(loc.start_line),
    startColumn: Number(loc.start_column) + 1,
    endLine: Number(loc.end_line),
    endColumn: Number(loc.end_column) + 1
  };
}

function formatTypeName(typeName) {
  if (typeof typeName !== 'string') return String(typeName);
  return typeName
    .split('_')
    .filter(Boolean)
    .map(part => part[0].toUpperCase() + part.slice(1))
    .join('');
}

function representativeValue(obj) {
  if (!obj || typeof obj !== 'object' || Array.isArray(obj)) return '';
  if (!Object.prototype.hasOwnProperty.call(obj, 'type')) return '';
  const typeValue = obj.type;
  let shownType = '';
  if (typeof typeValue === 'string') shownType = formatTypeName(typeValue);
  else if (typeValue === null) shownType = 'null';
  else shownType = String(typeValue);

  if (Object.prototype.hasOwnProperty.call(obj, 'name')) {
    shownType = `${shownType} (${obj.name})`;
  }
  else if (Object.prototype.hasOwnProperty.call(obj, 'value')) {
    shownType = `${shownType} (value: ${obj.value})`;
  }
  else if (Object.prototype.hasOwnProperty.call(obj, 'unescaped')) {
    shownType = `${shownType} (unescaped: ${formatDetailValue(obj.unescaped)})`;
  }
  else if (Array.isArray(obj.children_values) && obj.children_values.length > 0) {
    shownType = `${shownType} (${formatDetailValue(obj.children_values[0])})`;
  }

  return { key: 'type', value: shownType };
}

function formatDetailValue(value) {
  const t = typeOf(value);
  if (t === 'string') return `"${value}"`;
  if (t === 'number' || t === 'boolean') return String(value);
  if (t === 'null') return 'null';
  if (t === 'array') return JSON.stringify(value);
  if (t === 'object') {
    if (
      Object.prototype.hasOwnProperty.call(value, 'start_line') &&
      Object.prototype.hasOwnProperty.call(value, 'start_column') &&
      Object.prototype.hasOwnProperty.call(value, 'end_line') &&
      Object.prototype.hasOwnProperty.call(value, 'end_column')
    ) {
      const startCol = Number(value.start_column) + 1;
      const endCol = Number(value.end_column) + 1;
      return `${value.start_line}:${startCol}-${value.end_line}:${endCol}`;
    }
    try {
      return JSON.stringify(value);
    } catch (_) {
      return '[Object]';
    }
  }
  return String(value);
}

function hoverDetails(obj) {
  if (!obj || typeof obj !== 'object' || Array.isArray(obj)) return '';
  const keys = Object.keys(obj);
  const lines = [];
  keys.forEach(key => {
    const v = obj[key];
    const t = typeOf(v);
    if (t === 'array') {
      if (isArrayOfNodeObjects(v)) return;
      lines.push(`${key}: ${formatDetailValue(v)}`);
      return;
    }
    if (t === 'object' && isNodeObject(v)) return;
    lines.push(`${key}: ${formatDetailValue(v)}`);
  });
  return lines.join('\n');
}

function nodeKind(typeName) {
  if (typeof typeName !== 'string') return 'other';
  const t = typeName
    .replace(/([a-z0-9])([A-Z])/g, '$1_$2')
    .replace(/([A-Z]+)([A-Z][a-z])/g, '$1_$2')
    .toLowerCase();
  const literal = new Set(['number_literal', 'string_literal', 'char_literal', 'symbol_literal', 'bool_literal', 'nil_literal', 'array_literal', 'hash_literal', 'regex_literal', 'tuple_literal', 'named_tuple_literal', 'range_literal']);
  const reference = new Set(['var', 'instance_var', 'class_var', 'global', 'path', 'self']);
  const call = new Set(['call', 'macro_expression', 'yield', 'proc_literal']);
  const control = new Set(['if', 'unless', 'case', 'select', 'while', 'until', 'return', 'break', 'next', 'rescue', 'ensure', 'exception_handler', 'expressions']);
  const declaration = new Set(['def', 'macro', 'macro_def', 'class_def', 'module_def', 'lib_def', 'enum_def', 'alias', 'annotation', 'annotation_def', 'assign', 'arg', 'block']);
  const type = new Set(['type_declaration', 'generic', 'union', 'metaclass', 'virtual']);
  const conversion = new Set(['cast', 'is_a', 'responds_to', 'nilable_cast']);

  if (literal.has(t)) return 'literal';
  if (reference.has(t)) return 'reference';
  if (call.has(t)) return 'call';
  if (control.has(t)) return 'control';
  if (declaration.has(t)) return 'declaration';
  if (type.has(t)) return 'type';
  if (conversion.has(t)) return 'conversion';
  return 'other';
}

function buildTree(value, label = 'root') {
  const t = typeOf(value);
  const li = document.createElement('li');
  const header = document.createElement('span');
  header.className = 'node';
  if (t === 'object' && value && typeof value.type === 'string') {
    header.classList.add(`node-kind-${nodeKind(value.type)}`);
  }
  const rep = t === 'object' ? representativeValue(value) : '';
  const details = t === 'object' ? hoverDetails(value) : '';
  if (details) header.title = details;
  if (details) header.dataset.details = details;
  if (t === 'object' && value && Array.isArray(value.locals)) {
    header.classList.add('scope-node');
  }
  if (t === 'object') {
    const loc = extractLocation(value);
    if (loc) {
      header.dataset.loc = `${loc.startLine},${loc.startColumn},${loc.endLine},${loc.endColumn}`;
      li.dataset.loc = header.dataset.loc;
    }
  }
  if (rep && rep.value) {
    const repSpan = document.createElement('span');
    repSpan.className = 'value';
    repSpan.textContent = rep.value;
    header.appendChild(repSpan);
  }
  if (details) {
    const detailSpan = document.createElement('span');
    detailSpan.className = 'details';
    detailSpan.textContent = details;
    header.appendChild(detailSpan);
  }
  li.appendChild(header);
  const relation = document.createElement('span');
  relation.className = 'rel';
  if (t === 'array') {
    relation.textContent = `${label} (size: ${value.length})`;
  } else {
    relation.textContent = label;
  }
  li.insertBefore(relation, header);

  if (t === 'object') {
    const keys = Object.keys(value);
    if (keys.length) {
      const ul = document.createElement('ul');
      keys.forEach(key => {
        const child = value[key];
        const childType = typeOf(child);
        if (childType === 'array' && isArrayOfNodeObjects(child)) {
          ul.appendChild(buildTree(child, key));
          return;
        }
        if (childType === 'object' && isNodeObject(child)) {
          ul.appendChild(buildTree(child, key));
        }
      });
      li.appendChild(ul);
    }
  } else if (t === 'array') {
    if (value.length) {
      const ul = document.createElement('ul');
      value.forEach((item, index) => ul.appendChild(buildTree(item, `[${index}]`)));
      li.appendChild(ul);
    }
  }

  return li;
}

function renderTree(json) {
  tree.innerHTML = '';
  jsonView.textContent = JSON.stringify(json, null, 2);
  const ul = document.createElement('ul');
  ul.appendChild(buildTree(json, 'root'));
  tree.appendChild(ul);
}

function getEditorMetrics() {
  const style = window.getComputedStyle(rubyInput);
  const font = `${style.fontSize} ${style.fontFamily}`;
  const canvas = getEditorMetrics._canvas || (getEditorMetrics._canvas = document.createElement('canvas'));
  const ctx = canvas.getContext('2d');
  ctx.font = font;
  const lineHeight = parseFloat(style.lineHeight);
  const paddingLeft = parseFloat(style.paddingLeft) || 0;
  const paddingTop = parseFloat(style.paddingTop) || 0;
  const measure = (text) => ctx.measureText(text || '').width;
  return { lineHeight, paddingLeft, paddingTop, measure };
}

function renderLocationHighlight(loc) {
  if (!rubyLocLayer) return;
  rubyLocLayer.innerHTML = '';
  if (!loc) return;
  const { lineHeight, paddingLeft, paddingTop, measure } = getEditorMetrics();
  const lines = rubyInput.value.split('\n');
  const startLine = Math.max(1, loc.startLine);
  const endLine = Math.max(startLine, loc.endLine);
  for (let line = startLine; line <= endLine; line++) {
    const text = lines[line - 1] || '';
    const startCol = line === startLine ? Math.max(1, loc.startColumn) : 1;
    const endColRaw = line === endLine ? Math.max(startCol, loc.endColumn) : text.length + 1;
    const endCol = Math.max(startCol, endColRaw);
    const startIndex = Math.max(0, startCol - 1);
    const endExclusive = Math.max(startIndex, endCol);
    const left = paddingLeft + measure(text.slice(0, startIndex)) - rubyInput.scrollLeft;
    const width = Math.max(2, measure(text.slice(startIndex, endExclusive)));
    const top = paddingTop + (line - 1) * lineHeight - rubyInput.scrollTop;
    const block = document.createElement('div');
    block.className = 'loc-block';
    block.style.left = `${left}px`;
    block.style.top = `${top}px`;
    block.style.width = `${width}px`;
    block.style.height = `${lineHeight}px`;
    rubyLocLayer.appendChild(block);
  }
}

function updateRubyHighlight() {
  if (!rubyHighlight) return;
  const code = rubyInput.value || '';
  if (!window.hljs) {
    rubyHighlight.textContent = code;
    rubyInput.style.color = 'var(--ink)';
    return;
  }
  rubyHighlight.innerHTML = hljs.highlight(code, { language: 'crystal' }).value;
  rubyInput.style.color = 'transparent';
}

async function copyOutput(text) {
  try {
    await navigator.clipboard.writeText(text || '');
  } catch (_) {
    window.alert('Failed to copy to clipboard.');
  }
}

function renderErrorState(message) {
  tree.textContent = message;
  textView.textContent = message;
  jsonView.textContent = '';
  if (tokenView) tokenView.textContent = '';
  lastTokenText = '';
}

function renderTokenTable(tokens) {
  if (!tokenView) return;
  if (!Array.isArray(tokens) || tokens.length === 0) {
    tokenView.textContent = '';
    return;
  }

  const columns = [
    { key: 'line_number', label: 'Line', className: 'num' },
    { key: 'column_number', label: 'Col', className: 'num' },
    { key: 'type', label: 'Type' },
    { key: 'value', label: 'Value' },
    { key: 'raw', label: 'Raw' },
  ];

  const table = document.createElement('table');
  table.className = 'token-table';

  const thead = document.createElement('thead');
  const headRow = document.createElement('tr');
  columns.forEach(col => {
    const th = document.createElement('th');
    th.textContent = col.label;
    if (col.className) th.className = col.className;
    headRow.appendChild(th);
  });
  thead.appendChild(headRow);

  const tbody = document.createElement('tbody');
  tokens.forEach(token => {
    const row = document.createElement('tr');
    columns.forEach(col => {
      const td = document.createElement('td');
      if (col.className) td.className = col.className;
      const raw = token && Object.prototype.hasOwnProperty.call(token, col.key) ? token[col.key] : '';
      td.textContent = raw === null || raw === undefined ? '' : String(raw);
      row.appendChild(td);
    });
    tbody.appendChild(row);
  });

  table.appendChild(thead);
  table.appendChild(tbody);
  tokenView.innerHTML = '';
  tokenView.appendChild(table);
}

tabButtons.forEach(btn => {
  btn.addEventListener('click', () => {
    const target = btn.dataset.tab;
    if (!target) return;
    tabButtons.forEach(b => b.classList.toggle('active', b === btn));
    tabPanels.forEach(panel => panel.classList.toggle('active', panel.id === target));
  });
});

const params = new URLSearchParams(window.location.search);
const programParam = params.get('p');
if (programParam !== null) {
  rubyInput.value = programParam;
}

rubyInput.addEventListener('input', updateRubyHighlight);
rubyInput.addEventListener('input', () => {
  if (currentLoc) renderLocationHighlight(currentLoc);
});
rubyInput.addEventListener('scroll', () => {
  rubyHighlight.scrollTop = rubyInput.scrollTop;
  rubyHighlight.scrollLeft = rubyInput.scrollLeft;
  if (currentLoc) renderLocationHighlight(currentLoc);
});
rubyInput.addEventListener('keydown', (event) => {
  if ((event.ctrlKey || event.metaKey) && event.key === 'Enter') {
    event.preventDefault();
    parseBtn.click();
  }
});
updateRubyHighlight();

copyUrlBtn.addEventListener('click', async () => {
  const baseUrl = `${window.location.origin}${window.location.pathname}`;
  const params = new URLSearchParams();
  params.set('p', rubyInput.value || '');
  const url = `${baseUrl}?${params.toString()}`;
  try {
    await navigator.clipboard.writeText(url);
    rubyActionStatus.textContent = 'Share link copied';
    rubyActionStatus.className = 'status ok';
  } catch (_) {
    rubyActionStatus.textContent = 'Failed to copy share link';
    rubyActionStatus.className = 'status bad';
  }
});

copyTextBtn.addEventListener('click', () => {
  copyOutput(textView.textContent || '');
});

copyJsonBtn.addEventListener('click', () => {
  copyOutput(jsonView.textContent || '');
});

copyTokenBtn.addEventListener('click', () => {
  copyOutput(lastTokenText || tokenView.textContent || '');
});

expandAllBtn.addEventListener('click', () => {
  tree.querySelectorAll('.node[data-details]').forEach(node => {
    node.classList.add('expanded');
  });
});

collapseAllBtn.addEventListener('click', () => {
  tree.querySelectorAll('.node.expanded').forEach(node => {
    node.classList.remove('expanded');
  });
});

tree.addEventListener('click', (event) => {
  const target = event.target.closest('.node');
  if (!target || !tree.contains(target)) return;
  if (!target.dataset.details) return;
  const selection = window.getSelection && window.getSelection().toString();
  if (selection && selection.length > 0) return;
  target.classList.toggle('expanded');
});

tree.addEventListener('mouseover', (event) => {
  const row = event.target.closest('li');
  if (!row || !tree.contains(row)) return;
  const locText = row.dataset.loc;
  if (!locText) return;
  const parts = locText.split(',').map(n => Number(n));
  if (parts.length !== 4) return;
  currentLoc = {
    startLine: parts[0],
    startColumn: parts[1],
    endLine: parts[2],
    endColumn: parts[3]
  };
  renderLocationHighlight(currentLoc);
});

tree.addEventListener('mouseout', (event) => {
  const row = event.target.closest('li');
  if (!row || !tree.contains(row)) return;
  const related = event.relatedTarget && event.relatedTarget.closest && event.relatedTarget.closest('li');
  if (related === row) return;
  currentLoc = null;
  renderLocationHighlight(null);
});

async function postJson(url, payload) {
  if (window.astvWasmReady) {
    const wasm = await window.astvWasmReady;
    if (wasm && wasm.postJson) {
      return wasm.postJson(url, payload);
    }
  }
  throw new Error('WASM not ready');
}

async function parseAndRender() {
  const source = rubyInput.value || '';
  rubyActionStatus.textContent = 'Parsing...';
  rubyActionStatus.className = 'status';
  try {
    const parseResult = await postJson('/api/parse', { code: source });

    if (parseResult && parseResult.ast) {
      renderTree(parseResult.ast);
      textView.textContent = parseResult.text || '';
      rubyActionStatus.textContent = parseResult.errors && parseResult.errors.length > 0
        ? 'Parsed with errors'
        : 'Parsed';
      rubyActionStatus.className = parseResult.errors && parseResult.errors.length > 0
        ? 'status bad'
        : 'status ok';
    } else if (parseResult && parseResult.errors && parseResult.errors.length > 0) {
      renderErrorState(parseResult.errors[0].message || 'Parse error');
      rubyActionStatus.textContent = 'Parse error';
      rubyActionStatus.className = 'status bad';
    } else {
      renderErrorState('No AST returned.');
      rubyActionStatus.textContent = 'No AST returned';
      rubyActionStatus.className = 'status bad';
    }

    if (tokenView) {
      try {
        const lexResult = await postJson('/api/lex', { code: source });
        lastTokenText = lexResult && lexResult.text ? lexResult.text : '';
        if (lexResult && Array.isArray(lexResult.tokens)) {
          renderTokenTable(lexResult.tokens);
        } else if (lexResult && lexResult.text) {
          tokenView.textContent = lexResult.text;
        } else if (lexResult && lexResult.errors && lexResult.errors.length > 0) {
          tokenView.textContent = lexResult.errors[0].message || 'Lex error';
        } else {
          tokenView.textContent = '';
        }
      } catch (lexErr) {
        const lexMessage = lexErr && lexErr.message ? lexErr.message : String(lexErr);
        lastTokenText = '';
        if (lexMessage.includes('unreachable')) {
          tokenView.textContent = 'Tokens tab: lexer failed in WASM runtime for this input.';
        } else {
          tokenView.textContent = `Lex error: ${lexMessage}`;
        }
      }
    }
  } catch (err) {
    const message = err && err.message ? err.message : String(err);
    renderErrorState(message);
    rubyActionStatus.textContent = message;
    rubyActionStatus.className = 'status bad';
  }
}

parseBtn.addEventListener('click', parseAndRender);

if (rubyStatus && window.astvWasmReady) {
  window.astvWasmReady
    .then((wasm) => {
      const version = wasm && wasm.crystalVersion;
      rubyStatus.textContent = version
        ? `WASM ready (Crystal ${version})`
        : 'WASM ready (Crystal version unknown)';
      rubyStatus.className = 'status ok';
    })
    .catch(() => {
      rubyStatus.textContent = 'WASM failed';
      rubyStatus.className = 'status bad';
    });
} else if (rubyStatus) {
  rubyStatus.textContent = 'Server ready';
  rubyStatus.className = 'status ok';
}

if ((rubyInput.value || '').trim() !== '') {
  parseAndRender();
}
