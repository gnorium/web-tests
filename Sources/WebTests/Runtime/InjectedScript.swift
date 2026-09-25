// The page-side half of locators: resolving a locator's steps to elements,
// the actionability checks an action waits on, and the reads assertions
// retry. One script for every engine, since both protocols can evaluate an
// expression; it is sent whole with each call rather than installed, so a
// navigation can never leave a stale copy behind.

enum InjectedScript {
  /// An expression that runs `operation` with `arguments` (JSON) and
  /// evaluates to its result.
  static func call(_ operation: String, _ arguments: JSONValue...) -> String {
    let list = arguments.map(\.jsonText).joined(separator: ", ")
    return "(async () => { const WT = (\(source))(); return await WT.\(operation)(\(list)); })()"
  }

  static let source = #"""
    () => {
      const norm = (s) => String(s == null ? '' : s).replace(/[\s​]+/g, ' ').trim();
      const matchText = (actual, expected, exact) => {
        const a = norm(actual);
        const e = norm(expected);
        return exact ? a === e : a.toLowerCase().includes(e.toLowerCase());
      };

      // Visible: laid out with a non-empty box, not visibility: hidden.
      const isVisible = (el) => {
        if (!el || !el.isConnected) return false;
        const style = getComputedStyle(el);
        if (style.display === 'contents') {
          for (const child of el.children) if (isVisible(child)) return true;
          return false;
        }
        if (typeof el.checkVisibility === 'function' && !el.checkVisibility()) return false;
        if (style.visibility !== 'visible') return false;
        const rect = el.getBoundingClientRect();
        return rect.width > 0 && rect.height > 0;
      };
      const hiddenReason = (el) => {
        const style = getComputedStyle(el);
        if (style.display === 'none') return 'display: none';
        for (let a = el.parentElement; a; a = a.parentElement) {
          if (getComputedStyle(a).display === 'none') return 'inside ' + describe(a) + ' which is display: none';
        }
        if (style.visibility !== 'visible') return 'visibility: ' + style.visibility;
        const rect = el.getBoundingClientRect();
        if (rect.width === 0 || rect.height === 0) return 'its box is ' + Math.round(rect.width) + '×' + Math.round(rect.height);
        return 'not rendered';
      };
      // Hidden from assistive technology: what getByRole leaves out.
      const isAriaHidden = (el) => {
        for (let a = el; a; a = a.parentElement) {
          if (a.getAttribute('aria-hidden') === 'true') return true;
        }
        if (typeof el.checkVisibility === 'function') return !el.checkVisibility({ visibilityProperty: true });
        return getComputedStyle(el).visibility !== 'visible';
      };

      const describe = (el) => {
        if (!el || el.nodeType !== 1) return String(el);
        let s = '<' + el.localName;
        if (el.id) s += ' id="' + el.id + '"';
        const cls = el.getAttribute('class');
        if (cls) s += ' class="' + (cls.length > 60 ? cls.slice(0, 60) + '…' : cls) + '"';
        for (const name of ['role', 'name', 'type', 'href', 'aria-label']) {
          const v = el.getAttribute(name);
          if (v) s += ' ' + name + '="' + (v.length > 40 ? v.slice(0, 40) + '…' : v) + '"';
        }
        s += '>';
        const text = norm(el.textContent);
        if (text) s += text.length > 40 ? text.slice(0, 40) + '…' : text;
        return s;
      };

      // MARK: Roles and names

      const hasName = (el) => el.hasAttribute('aria-label') || el.hasAttribute('aria-labelledby') || el.hasAttribute('title');
      const roleOf = (el) => {
        const explicit = (el.getAttribute('role') || '').trim().split(/\s+/)[0];
        if (explicit) return explicit;
        const tag = el.localName;
        switch (tag) {
          case 'a': case 'area': return el.hasAttribute('href') ? 'link' : null;
          case 'button': return 'button';
          case 'summary': return 'button';
          case 'input': {
            const type = (el.getAttribute('type') || 'text').toLowerCase();
            if (['button', 'submit', 'reset', 'image'].includes(type)) return 'button';
            if (type === 'checkbox') return 'checkbox';
            if (type === 'radio') return 'radio';
            if (type === 'range') return 'slider';
            if (type === 'number') return 'spinbutton';
            if (type === 'hidden') return null;
            if (type === 'search') return el.hasAttribute('list') ? 'combobox' : 'searchbox';
            return el.hasAttribute('list') ? 'combobox' : 'textbox';
          }
          case 'textarea': return 'textbox';
          case 'select': return el.multiple || el.size > 1 ? 'listbox' : 'combobox';
          case 'option': return 'option';
          case 'h1': case 'h2': case 'h3': case 'h4': case 'h5': case 'h6': return 'heading';
          case 'img': return el.getAttribute('alt') === '' ? 'presentation' : 'img';
          case 'nav': return 'navigation';
          case 'main': return 'main';
          case 'aside': return 'complementary';
          case 'header': return el.closest('article, aside, main, nav, section') ? null : 'banner';
          case 'footer': return el.closest('article, aside, main, nav, section') ? null : 'contentinfo';
          case 'section': return hasName(el) ? 'region' : null;
          case 'form': return hasName(el) ? 'form' : null;
          case 'ul': case 'ol': case 'menu': return 'list';
          case 'li': return 'listitem';
          case 'table': return 'table';
          case 'tr': return 'row';
          case 'td': return 'cell';
          case 'th': return el.getAttribute('scope') === 'row' ? 'rowheader' : 'columnheader';
          case 'dialog': return 'dialog';
          case 'hr': return 'separator';
          case 'article': return 'article';
          case 'fieldset': case 'details': return 'group';
          case 'progress': return 'progressbar';
          case 'output': return 'status';
        }
        return null;
      };
      const nameFromContent = new Set(['button', 'link', 'heading', 'cell', 'columnheader', 'rowheader', 'option', 'tab',
        'menuitem', 'menuitemcheckbox', 'menuitemradio', 'treeitem', 'checkbox', 'radio', 'switch', 'tooltip', 'row', 'gridcell']);
      const textOf = (el, includeHidden, skip) => {
        let out = '';
        for (const node of el.childNodes) {
          if (node.nodeType === 3) { out += node.textContent; continue; }
          if (node.nodeType !== 1 || node === skip) continue;
          const tag = node.localName;
          if (['script', 'style', 'template', 'noscript'].includes(tag)) continue;
          if (!includeHidden && isAriaHidden(node)) continue;
          if (node.hasAttribute('aria-label')) { out += ' ' + node.getAttribute('aria-label') + ' '; continue; }
          if (tag === 'img') { out += ' ' + (node.getAttribute('alt') || '') + ' '; continue; }
          const inline = getComputedStyle(node).display.startsWith('inline');
          const inner = textOf(node, includeHidden, skip);
          out += inline ? inner : ' ' + inner + ' ';
        }
        return out;
      };
      const labelledBy = (el) => {
        const ids = el.getAttribute('aria-labelledby');
        if (!ids) return '';
        return norm(ids.split(/\s+/).map((id) => document.getElementById(id)).filter(Boolean).map((e) => textOf(e, true)).join(' '));
      };
      const nameOf = (el) => {
        const byIds = labelledBy(el);
        if (byIds) return byIds;
        const aria = norm(el.getAttribute('aria-label'));
        if (aria) return aria;
        const tag = el.localName;
        if (tag === 'input' || tag === 'textarea' || tag === 'select') {
          const type = (el.getAttribute('type') || '').toLowerCase();
          if (['button', 'submit', 'reset'].includes(type)) return norm(el.value || (type === 'submit' ? 'Submit' : type === 'reset' ? 'Reset' : ''));
          if (type === 'image') return norm(el.getAttribute('alt') || el.value || 'Submit');
          if (el.labels && el.labels.length) return norm([...el.labels].map((l) => textOf(l, true, el)).join(' '));
          return norm(el.getAttribute('title') || el.getAttribute('placeholder') || '');
        }
        if (tag === 'img') return norm(el.getAttribute('alt') || el.getAttribute('title') || '');
        if (nameFromContent.has(roleOf(el))) {
          const text = norm(textOf(el, false));
          if (text) return text;
        }
        return norm(el.getAttribute('title') || '');
      };
      const labelOf = (el) => {
        const byIds = labelledBy(el);
        if (byIds) return byIds;
        const aria = norm(el.getAttribute('aria-label'));
        if (aria) return aria;
        if (el.labels && el.labels.length) return norm([...el.labels].map((l) => textOf(l, true, el)).join(' '));
        return '';
      };

      // MARK: Resolving

      const skipTags = new Set(['script', 'style', 'template', 'head', 'noscript', 'title']);
      const byText = (root, text, exact) => {
        const out = [];
        const walk = (el) => {
          let found = false;
          for (const child of el.children) {
            if (skipTags.has(child.localName)) continue;
            if (walk(child)) found = true;
          }
          if (!found && el !== root && el.nodeType === 1 && matchText(el.textContent, text, exact)) {
            out.push(el);
            return true;
          }
          return found;
        };
        walk(root === document ? document.documentElement : root);
        return out;
      };
      const all = (root) => root.querySelectorAll('*');
      const inOrder = (elements) => {
        const unique = [...new Set(elements)];
        return unique.sort((a, b) => a === b ? 0 : (a.compareDocumentPosition(b) & Node.DOCUMENT_POSITION_FOLLOWING ? -1 : 1));
      };
      const resolve = (steps) => {
        let current = [document];
        for (const step of steps) {
          let next = [];
          switch (step.kind) {
            case 'css':
              for (const root of current) next.push(...root.querySelectorAll(step.selector));
              break;
            case 'role':
              for (const root of current) {
                for (const el of all(root)) {
                  if (roleOf(el) !== step.role || isAriaHidden(el)) continue;
                  if (step.name != null && !matchText(nameOf(el), step.name, step.exact)) continue;
                  next.push(el);
                }
              }
              break;
            case 'text':
              for (const root of current) next.push(...byText(root, step.text, step.exact));
              break;
            case 'label':
              for (const root of current) {
                for (const el of all(root)) {
                  const label = labelOf(el);
                  if (label && matchText(label, step.text, step.exact)) next.push(el);
                }
              }
              break;
            case 'hasText':
              next = current.filter((el) => el !== document && matchText(el.textContent, step.text, step.exact));
              break;
            case 'visible':
              next = current.filter((el) => el !== document && isVisible(el) === step.visible);
              break;
            case 'nth': {
              const elements = current.filter((el) => el !== document);
              const index = step.index < 0 ? elements.length + step.index : step.index;
              next = index >= 0 && index < elements.length ? [elements[index]] : [];
              break;
            }
          }
          current = current.length > 1 ? inOrder(next) : [...new Set(next)];
        }
        return current.filter((el) => el !== document);
      };

      // MARK: Actionability

      const frame = () => new Promise((resolve) => {
        let done = false;
        requestAnimationFrame(() => { done = true; resolve(); });
        // A page with no frames coming (hidden, throttled) still settles.
        setTimeout(() => { if (!done) resolve(); }, 100);
      });
      const box = (el) => {
        const rects = el.getClientRects();
        const r = rects.length > 1 ? rects[0] : el.getBoundingClientRect();
        return { x: r.left, y: r.top, width: r.width, height: r.height };
      };
      const sameBox = (a, b) => a.x === b.x && a.y === b.y && a.width === b.width && a.height === b.height;
      const isDisabled = (el) => {
        if (['button', 'input', 'select', 'textarea', 'option', 'optgroup', 'fieldset'].includes(el.localName) && el.disabled) return true;
        for (let a = el; a; a = a.parentElement) {
          if (a.getAttribute('aria-disabled') === 'true') return true;
        }
        return false;
      };
      const isEditable = (el) => {
        if (isDisabled(el)) return false;
        if (['input', 'textarea'].includes(el.localName)) return !el.readOnly;
        if (el.localName === 'select') return true;
        return el.isContentEditable;
      };
      const deepHit = (x, y) => {
        let hit = document.elementFromPoint(x, y);
        while (hit && hit.shadowRoot) {
          const inner = hit.shadowRoot.elementFromPoint(x, y);
          if (!inner || inner === hit) break;
          hit = inner;
        }
        return hit;
      };
      const single = (steps) => {
        const elements = resolve(steps);
        if (elements.length === 0) return { error: { status: 'notAttached', detail: 'no element matches' } };
        if (elements.length > 1) {
          return { error: { status: 'notUnique', detail: 'it matches ' + elements.length + ' elements: ' +
            elements.slice(0, 5).map(describe).join(', ') + (elements.length > 5 ? ', …' : '') } };
        }
        return { element: elements[0] };
      };

      const actionPoint = async (steps, options) => {
        const { element: el, error } = single(steps);
        if (error) return error;
        if (!isVisible(el)) return { status: 'notVisible', detail: describe(el) + ' is not visible (' + hiddenReason(el) + ')' };
        let first = box(el);
        if (first.y < 0 || first.x < 0 || first.y + first.height > innerHeight || first.x + first.width > innerWidth) {
          el.scrollIntoView({ block: 'center', inline: 'center', behavior: 'instant' });
          first = box(el);
        }
        await frame();
        const second = box(el);
        await frame();
        const third = box(el);
        if (!sameBox(second, third) || !sameBox(first, second)) {
          return { status: 'notStable', detail: describe(el) + ' is still moving (from ' + JSON.stringify(first) + ' to ' + JSON.stringify(third) + ')' };
        }
        if (options.enabled && isDisabled(el)) return { status: 'notEnabled', detail: describe(el) + ' is disabled' };
        if (options.editable && !isEditable(el)) return { status: 'notEditable', detail: describe(el) + ' is not editable (disabled or read-only)' };
        const x = third.x + third.width / 2;
        const y = third.y + third.height / 2;
        if (x < 0 || y < 0 || x >= innerWidth || y >= innerHeight) {
          return { status: 'outsideViewport', detail: describe(el) + ' is outside the viewport at (' + Math.round(x) + ', ' + Math.round(y) + ')' };
        }
        if (options.hitTest) {
          const hit = deepHit(x, y);
          const receives = hit && (hit === el || el.contains(hit) || (el.labels && [...el.labels].some((l) => l === hit || l.contains(hit))));
          if (!receives) {
            return { status: 'obscured', detail: (hit ? describe(hit) : 'nothing') + ' would receive the pointer event at (' +
              Math.round(x) + ', ' + Math.round(y) + ') instead of ' + describe(el) };
          }
        }
        return { status: 'ok', x, y };
      };

      const focus = async (steps) => {
        const { element: el, error } = single(steps);
        if (error) return error;
        el.focus();
        return { status: 'ok' };
      };

      // Focus the field and select what it holds, so typed text replaces it.
      const selectContents = async (steps) => {
        const { element: el, error } = single(steps);
        if (error) return error;
        if (el.localName === 'input' && ['checkbox', 'radio', 'file', 'submit', 'button', 'reset', 'image', 'range', 'color'].includes(el.type)) {
          return { status: 'notFillable', detail: describe(el) + ' is an input of type ' + el.type + ', which cannot be filled' };
        }
        el.focus();
        if (typeof el.select === 'function') {
          try { el.select(); } catch (e) {}
        } else if (el.isContentEditable) {
          const range = document.createRange();
          range.selectNodeContents(el);
          const selection = getSelection();
          selection.removeAllRanges();
          selection.addRange(range);
        }
        const value = el.value != null ? el.value : el.textContent;
        return { status: 'ok', empty: value === '' };
      };

      // MARK: Reading

      const inspect = async (steps, options) => {
        const elements = resolve(steps);
        const result = { count: elements.length };
        if (options.all) {
          result.texts = elements.map((el) => norm(options.innerText ? el.innerText : el.textContent));
        }
        if (elements.length !== 1) {
          result.visibleCount = elements.filter(isVisible).length;
          if (elements.length > 1) result.detail = elements.slice(0, 5).map(describe).join(', ');
          return result;
        }
        const el = elements[0];
        result.description = describe(el);
        result.visible = isVisible(el);
        if (!result.visible) result.hiddenReason = hiddenReason(el);
        result.text = norm(el.textContent);
        result.innerText = norm(el.innerText);
        result.enabled = !isDisabled(el);
        result.editable = isEditable(el);
        result.checked = el.checked === true || el.getAttribute('aria-checked') === 'true';
        result.focused = document.activeElement === el;
        if ('value' in el) result.value = String(el.value);
        if (options.attribute) result.attribute = el.getAttribute(options.attribute);
        if (options.css) result.css = getComputedStyle(el).getPropertyValue(options.css);
        if (options.name) result.name = nameOf(el);
        if (options.role) result.role = roleOf(el);
        const r = el.getBoundingClientRect();
        result.box = { x: r.left, y: r.top, width: r.width, height: r.height };
        return result;
      };

      // Whether the page is wider than `width`, and the deepest elements
      // that stick out past it.
      const overflow = async (width) => {
        const limit = width || innerWidth;
        const scrollWidth = document.documentElement.scrollWidth;
        if (scrollWidth <= limit) return null;
        const sticking = [...document.body.querySelectorAll('*')].filter((el) => {
          const r = el.getBoundingClientRect();
          return r.width > 0 && r.right + scrollX > limit + 1;
        });
        const deepest = sticking.filter((el) => !sticking.some((other) => other !== el && el.contains(other)));
        return {
          scrollWidth, width: limit,
          offenders: deepest.slice(0, 8).map((el) => describe(el) + ' reaches x=' + Math.round(el.getBoundingClientRect().right + scrollX)),
        };
      };

      return { resolve, actionPoint, focus, selectContents, inspect, overflow, describe };
    }
    """#
}
