import { initSoundRibbon } from "./sound-ribbon.js";

const $ = (selector, parent = document) => parent.querySelector(selector);
const $$ = (selector, parent = document) => [
  ...parent.querySelectorAll(selector),
];

const tourDialog = $("#tour-dialog");
const tourVideo = $("#tour-video");
const downloadDialog = $("#download-dialog");

function openTour(time = 0) {
  tourDialog.showModal();
  const seekAndPlay = () => {
    if (!tourDialog.open) return;
    tourVideo.currentTime = time;
    tourVideo.play().catch(() => {
      // Native controls remain available when autoplay is blocked.
    });
  };
  if (tourVideo.readyState >= 1) seekAndPlay();
  else {
    tourVideo.addEventListener("loadedmetadata", seekAndPlay, { once: true });
  }
  if (tourVideo.readyState === 0) tourVideo.load();
}

$$("[data-open-tour]").forEach((button) => {
  button.addEventListener("click", () => {
    openTour(Number(button.dataset.tourTime || 0));
  });
});

$$("[data-open-download]").forEach((button) => {
  button.addEventListener("click", (event) => {
    event.preventDefault();
    downloadDialog.showModal();
  });
});

$$("[data-close-dialog]").forEach((button) => {
  button.addEventListener("click", () => button.closest("dialog").close());
});

$$("dialog").forEach((dialog) => {
  dialog.addEventListener("click", (event) => {
    const bounds = dialog.getBoundingClientRect();
    const outside =
      event.clientX < bounds.left ||
      event.clientX > bounds.right ||
      event.clientY < bounds.top ||
      event.clientY > bounds.bottom;
    if (event.target === dialog && outside) dialog.close();
  });
});

tourDialog.addEventListener("close", () => tourVideo.pause());

$$("[data-seek]").forEach((button) => {
  button.addEventListener("click", () => {
    tourVideo.currentTime = Number(button.dataset.seek);
    tourVideo.play().catch(() => {});
  });
});

tourVideo.addEventListener("timeupdate", () => {
  const chapters = $$("[data-seek]");
  const current = chapters.findLast(
    (button) => Number(button.dataset.seek) <= tourVideo.currentTime,
  );
  chapters.forEach((button) => {
    button.setAttribute("aria-current", String(button === current));
  });
});

function selectTab(tabs, active) {
  tabs.forEach((tab) => {
    const selected = tab === active;
    tab.setAttribute("aria-selected", String(selected));
    tab.tabIndex = selected ? 0 : -1;
  });
}

function supportTabKeys(tabs, activate) {
  tabs.forEach((tab, index) => {
    tab.addEventListener("keydown", (event) => {
      let target;
      if (event.key === "ArrowLeft") {
        target = tabs[(index + tabs.length - 1) % tabs.length];
      }
      if (event.key === "ArrowRight") {
        target = tabs[(index + 1) % tabs.length];
      }
      if (event.key === "Home") target = tabs[0];
      if (event.key === "End") target = tabs.at(-1);
      if (!target) return;
      event.preventDefault();
      activate(target);
      target.focus();
    });
  });
}

const insightTabs = $$("[data-insight]");

function showInsight(name) {
  const active = insightTabs.find((tab) => tab.dataset.insight === name);
  if (!active) return;
  selectTab(insightTabs, active);
  $("#insight-panel").setAttribute("aria-labelledby", active.id);
  $$("[data-insight-view]").forEach((view) => {
    view.hidden = view.dataset.insightView !== name;
  });
}

insightTabs.forEach((tab) => {
  tab.addEventListener("click", () => showInsight(tab.dataset.insight));
});

supportTabKeys(insightTabs, (tab) => showInsight(tab.dataset.insight));

const mobileMenu = $(".mobile-menu");
$$("a", mobileMenu).forEach((link) => {
  link.addEventListener("click", () => {
    mobileMenu.open = false;
  });
});
document.addEventListener("keydown", (event) => {
  if (event.key === "Escape" && mobileMenu.open) {
    mobileMenu.open = false;
    $("summary", mobileMenu).focus();
  }
});
document.addEventListener("click", (event) => {
  if (!mobileMenu.contains(event.target)) mobileMenu.open = false;
});

const phoneLayout = matchMedia("(max-width: 780px)");
function updateInstallDetails() {
  $$("[data-responsive-details]").forEach((details) => {
    details.open = !phoneLayout.matches;
  });
}
updateInstallDetails();
phoneLayout.addEventListener("change", updateInstallDetails);

$$(".faq-list details").forEach((detail) => {
  detail.addEventListener("toggle", () => {
    if (!detail.open) return;
    $$(".faq-list details").forEach((other) => {
      if (other !== detail) other.open = false;
    });
  });
});
initSoundRibbon();
