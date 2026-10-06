// Progressive enhancements. The page and its code stay readable without JS.
const announcement = document.querySelector("#site-announcement");
document.querySelectorAll("[data-copy]").forEach((button) => {
  button.hidden = false;
  const original = button.innerHTML;
  let resetTimer;
  button.addEventListener("click", async () => {
    const code = document.getElementById(button.dataset.copy);
    try {
      await navigator.clipboard.writeText(code.textContent);
      button.textContent = "Copied ✓";
      announcement.textContent = "Code copied to clipboard.";
    } catch {
      const range = document.createRange();
      range.selectNodeContents(code);
      const selection = window.getSelection();
      selection.removeAllRanges();
      selection.addRange(range);
      button.textContent = "Selected";
      announcement.textContent =
        "Copy is unavailable. The code is selected; use your keyboard to copy it.";
    }
    clearTimeout(resetTimer);
    resetTimer = setTimeout(() => {
      button.innerHTML = original;
    }, 2200);
  });
});

const tabs = [...document.querySelectorAll("[data-panel]")];
const panels = [...document.querySelectorAll(".tour-panel")];
document.querySelector(".tour-tabs").setAttribute("role", "tablist");
tabs.forEach((tab, index) => {
  tab.id = `tour-tab-${index}`;
  tab.setAttribute("role", "tab");
  tab.setAttribute("aria-controls", tab.dataset.panel);
  const panel = document.getElementById(tab.dataset.panel);
  panel.setAttribute("role", "tabpanel");
  panel.setAttribute("aria-labelledby", tab.id);
  tab.addEventListener("click", (event) => {
    event.preventDefault();
    selectTab(index);
  });
  tab.addEventListener("keydown", (event) => {
    let next;
    if (event.key === "ArrowRight") next = (index + 1) % tabs.length;
    if (event.key === "ArrowLeft")
      next = (index - 1 + tabs.length) % tabs.length;
    if (event.key === "Home") next = 0;
    if (event.key === "End") next = tabs.length - 1;
    if (next !== undefined) {
      event.preventDefault();
      selectTab(next);
      tabs[next].focus();
    }
  });
});
function selectTab(index) {
  tabs.forEach((tab, i) => {
    tab.setAttribute("aria-selected", String(index === i));
    tab.tabIndex = index === i ? 0 : -1;
  });
  panels.forEach((panel, i) => {
    panel.hidden = i !== index;
  });
}
const linkedTab = tabs.findIndex(
  (tab) => `#${tab.dataset.panel}` === location.hash,
);
selectTab(linkedTab >= 0 ? linkedTab : 0);
window.addEventListener("hashchange", () => {
  const index = tabs.findIndex(
    (tab) => `#${tab.dataset.panel}` === location.hash,
  );
  if (index >= 0) selectTab(index);
});
