// Construction du DOM SANS jamais écrire de HTML : tout texte passe par des nœuds texte, donc un nom de
// client comme « <img src=x onerror=...> » s'affiche tel quel et ne s'exécute jamais.

/**
 * h('button', { class: 'primary', onclick: fn, disabled: true }, 'Texte', autreElement)
 * - les props commençant par « on » sont des écouteurs ;
 * - `value`, `checked`, `disabled`, `selected`, `required` sont des propriétés ;
 * - false/null/undefined sont ignorés (attributs et enfants).
 */
export function h(tag, props = {}, ...children) {
  const el = document.createElement(tag);
  for (const [key, value] of Object.entries(props ?? {})) {
    if (value === false || value === null || value === undefined) continue;
    if (key.startsWith('on') && typeof value === 'function') {
      el.addEventListener(key.slice(2).toLowerCase(), value);
    } else if (['value', 'checked', 'disabled', 'selected', 'required', 'hidden'].includes(key)) {
      el[key] = value;
    } else if (key === 'class') {
      el.className = value;
    } else {
      el.setAttribute(key, value === true ? '' : String(value));
    }
  }
  append(el, children);
  return el;
}

export function append(parent, children) {
  for (const child of children.flat(Infinity)) {
    if (child === null || child === undefined || child === false) continue;
    parent.append(child instanceof Node ? child : document.createTextNode(String(child)));
  }
  return parent;
}

/** Remplace tout le contenu de [parent] par [children]. */
export function mount(parent, ...children) {
  parent.replaceChildren();
  return append(parent, children);
}
