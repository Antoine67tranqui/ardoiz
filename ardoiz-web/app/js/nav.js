/** Navigation par ancre (#/chemin). Séparé de main.js pour éviter les imports circulaires. */
export function navigate(path, { replace = false } = {}) {
  const target = `#${path}`;
  if (location.hash === target || replace) {
    if (location.hash !== target) history.replaceState(null, '', target);
    window.dispatchEvent(new HashChangeEvent('hashchange'));
    return;
  }
  location.hash = target;
}
