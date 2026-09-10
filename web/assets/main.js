const video = document.querySelector(".demo-video");
const motionPreference = window.matchMedia("(prefers-reduced-motion: reduce)");
if (video && !motionPreference.matches) {
  video.play().catch(() => {});
}
motionPreference.addEventListener("change", (event) => {
  if (event.matches) video?.pause();
});
