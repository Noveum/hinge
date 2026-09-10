const preview = document.querySelector(".preview");
const control = document.querySelector(".motion-control");
control?.addEventListener("click", () => {
  const paused = preview.classList.toggle("paused");
  control.setAttribute("aria-pressed", String(paused));
  control.textContent = paused ? "Play preview" : "Pause preview";
});
