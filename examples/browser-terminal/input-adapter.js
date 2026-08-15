const root = document.querySelector("#terminal-session");
const viewport = document.querySelector("#terminal-output");
let sequence = 0;
let ordered = Promise.resolve();

function send(facts) {
  const command = {...facts, sequence: ++sequence};
  ordered = ordered.then(() => fetch("/commands", {
    method: "POST",
    headers: {"content-type": "application/json"},
    body: JSON.stringify(command),
  }).then((response) => {
    if (!response.ok) throw new Error(`terminal command failed: ${response.status}`);
  }));
}

function modifiers(event) {
  return {
    shift: event.shiftKey,
    ctrl: event.ctrlKey,
    alt: event.altKey,
    meta: event.metaKey,
    capsLock: event.getModifierState?.("CapsLock") ?? false,
    numLock: event.getModifierState?.("NumLock") ?? false,
  };
}

function position(event) {
  const bounds = viewport.getBoundingClientRect();
  return {x: event.clientX - bounds.left, y: event.clientY - bounds.top};
}

root.addEventListener("keydown", (event) => {
  send({type: "key", action: event.repeat ? "repeat" : "press", code: event.code,
        text: event.key, composing: event.isComposing, ...modifiers(event)});
  event.preventDefault();
});
root.addEventListener("keyup", (event) => {
  send({type: "key", action: "release", code: event.code, text: event.key,
        composing: event.isComposing, ...modifiers(event)});
  event.preventDefault();
});
root.addEventListener("paste", (event) => {
  send({type: "paste", text: event.clipboardData.getData("text")});
  event.preventDefault();
});
for (const name of ["pointerdown", "pointerup", "pointermove"]) {
  viewport.addEventListener(name, (event) => {
    const action = name === "pointerdown" ? "press" : name === "pointerup" ? "release" : "motion";
    send({type: "pointer", action, button: event.button < 0 ? null : event.button,
          ...position(event), ...modifiers(event)});
    event.preventDefault();
  });
}
viewport.addEventListener("wheel", (event) => {
  send({type: "wheel", deltaX: event.deltaX, deltaY: event.deltaY,
        deltaMode: event.deltaMode, ...position(event), ...modifiers(event)});
  event.preventDefault();
}, {passive: false});

function sendResize() {
  const bounds = viewport.getBoundingClientRect();
  const cell = viewport.querySelector(".terminal-cell")?.getBoundingClientRect();
  if (!cell || cell.width === 0 || cell.height === 0) return;
  const style = getComputedStyle(viewport);
  send({type: "resize", columns: Math.floor(bounds.width / cell.width),
        rows: Math.floor(bounds.height / cell.height), screenWidth: bounds.width,
        screenHeight: bounds.height, cellWidth: cell.width, cellHeight: cell.height,
        paddingTop: parseFloat(style.paddingTop), paddingBottom: parseFloat(style.paddingBottom),
        paddingRight: parseFloat(style.paddingRight), paddingLeft: parseFloat(style.paddingLeft)});
}
new ResizeObserver(sendResize).observe(viewport);
root.tabIndex = 0;
root.focus();
