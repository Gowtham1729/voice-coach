import { initSoundRibbon } from "./sound-ribbon.js";

const $ = (selector, parent = document) => parent.querySelector(selector);
const $$ = (selector, parent = document) => [
  ...parent.querySelectorAll(selector),
];

const tourDialog = $("#tour-dialog");
const tourVideo = $("#tour-video");
const downloadDialog = $("#download-dialog");
let tourStartTime = 0;

tourVideo.addEventListener("loadedmetadata", () => {
  tourVideo.currentTime = tourStartTime;
});
tourVideo.addEventListener("error", () => {
  $("#film-load-error").hidden = false;
});

function openTour(time = 0) {
  tourStartTime = time;
  tourDialog.showModal();
  if (tourVideo.readyState >= 1) tourVideo.currentTime = time;
  // Request playback during the click so browsers retain the user gesture.
  tourVideo.play().catch(() => {
    // Native controls remain available when autoplay is blocked.
  });
}

$$("[data-open-tour]").forEach((button) => {
  button.addEventListener("click", (event) => {
    event.preventDefault();
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
  button.addEventListener("click", () => closeDialog(button.closest("dialog")));
});

$$("dialog").forEach((dialog) => {
  dialog.addEventListener("click", (event) => {
    const bounds = dialog.getBoundingClientRect();
    const outside =
      event.clientX < bounds.left ||
      event.clientX > bounds.right ||
      event.clientY < bounds.top ||
      event.clientY > bounds.bottom;
    if (event.target === dialog && outside) closeDialog(dialog);
  });
});

tourDialog.addEventListener("close", () => tourVideo.pause());

$$("[data-seek]").forEach((button) => {
  button.addEventListener("click", () => {
    tourStartTime = Number(button.dataset.seek);
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
const insightOrder = ["listen", "understand", "repeat", "compare"];
const insightTabsRoot = $(".insight-tabs");
let activeInsight = "listen";
let insightRequest = 0;

// Hidden steps still download and decode before their first selection.
const insightImages = new Map(
  $$("[data-insight-view]").map((view) => [
    view.dataset.insightView,
    $("img", view).decode().catch(() => {}),
  ]),
);

async function showInsight(name) {
  const request = ++insightRequest;
  if (name === activeInsight) return;
  const active = insightTabs.find((tab) => tab.dataset.insight === name);
  if (!active) return;
  await insightImages.get(name);
  if (request !== insightRequest) return;
  selectTab(insightTabs, active);
  $("#insight-panel").setAttribute("aria-labelledby", active.id);
  $$("[data-insight-view]").forEach((view) => {
    view.hidden = view.dataset.insightView !== name;
  });
  insightTabsRoot?.style.setProperty(
    "--insight-index",
    String(Math.max(0, insightOrder.indexOf(name))),
  );
  activeInsight = name;
}

insightTabs.forEach((tab) => {
  tab.addEventListener("click", () => showInsight(tab.dataset.insight));
});

supportTabKeys(insightTabs, (tab) => showInsight(tab.dataset.insight));

const screenshotDialog = $("#screenshot-dialog");
const expandedScreenshot = $("#expanded-screenshot");
let screenshotSource = null;
let screenshotOpener = null;
let screenshotRequest = 0;

function closeDialog(dialog) {
  if (dialog === screenshotDialog && screenshotDialog.open) {
    closeScreenshot();
    return;
  }
  dialog?.close();
}

async function openScreenshot(link) {
  if (screenshotDialog.open) return;
  const request = ++screenshotRequest;
  const source = $("img", link);
  expandedScreenshot.src = link.href;
  expandedScreenshot.alt = source.alt;
  $("#screenshot-caption").textContent = link.dataset.caption ||
    "Real app capture. Transcripts and Words replies can contain errors.";
  await expandedScreenshot.decode().catch(() => {});
  if (request !== screenshotRequest || !expandedScreenshot.naturalWidth) return;
  expandedScreenshot.width = expandedScreenshot.naturalWidth;
  expandedScreenshot.height = expandedScreenshot.naturalHeight;
  screenshotSource = link.closest(".screen-frame") || link;
  screenshotOpener = link;
  screenshotSource.classList.add("screenshot-source-hidden");
  screenshotDialog.showModal();
}

async function closeScreenshot() {
  if (!screenshotDialog.open || screenshotDialog.classList.contains("screenshot-closing")) return;
  ++screenshotRequest;
  screenshotDialog.classList.add("screenshot-closing");
  await Promise.allSettled(
    screenshotDialog.getAnimations().map((animation) => animation.finished),
  );
  screenshotDialog.close();
}

screenshotDialog.addEventListener("close", () => {
  const opener = screenshotOpener;
  screenshotDialog.classList.remove("screenshot-closing");
  screenshotSource?.classList.remove("screenshot-source-hidden");
  screenshotSource = null;
  screenshotOpener = null;
  opener?.focus({ preventScroll: true });
});

screenshotDialog.addEventListener("cancel", (event) => {
  event.preventDefault();
  closeScreenshot();
});

$$("[data-screenshot]").forEach((link) => {
  link.addEventListener("click", (event) => {
    event.preventDefault();
    openScreenshot(link);
  });
});

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

$$(".faq-list details").forEach((detail) => {
  detail.addEventListener("toggle", () => {
    if (!detail.open) return;
    $$(".faq-list details").forEach((other) => {
      if (other !== detail) other.open = false;
    });
  });
});
initSoundRibbon();
