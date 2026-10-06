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
const insightOrder = ["listen", "repeat", "compare"];
const insightTabsRoot = $(".insight-tabs");
const motionQuery = matchMedia("(prefers-reduced-motion: reduce)");
let activeInsight = "listen";

function prefersReducedMotion() {
  return motionQuery.matches;
}

let viewChange = null;

function runViewTransition(update, type) {
  if (
    viewChange ||
    prefersReducedMotion() ||
    typeof document.startViewTransition !== "function"
  ) {
    update();
    return Promise.resolve();
  }
  let transition;
  try {
    transition = document.startViewTransition({ update, types: [type] });
  } catch {
    try {
      transition = document.startViewTransition(update);
    } catch {
      update();
      return Promise.resolve();
    }
  }
  viewChange = transition.finished.catch(() => {}).finally(() => {
    viewChange = null;
  });
  return viewChange;
}

function showInsight(name) {
  if (name === activeInsight) return;
  const direction = insightOrder.indexOf(name) > insightOrder.indexOf(activeInsight)
    ? "practice-forward"
    : "practice-back";
  runViewTransition(() => {
    const active = insightTabs.find((tab) => tab.dataset.insight === name);
    if (!active) return;
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
  }, direction);
}

insightTabs.forEach((tab) => {
  tab.addEventListener("click", () => showInsight(tab.dataset.insight));
});

supportTabKeys(insightTabs, (tab) => showInsight(tab.dataset.insight));

const screenshotDialog = $("#screenshot-dialog");
const expandedScreenshot = $("#expanded-screenshot");
let screenshotSource = null;
let screenshotRequest = 0;

function closeDialog(dialog) {
  if (dialog === screenshotDialog && screenshotDialog.open) {
    closeScreenshot();
    return;
  }
  dialog?.close();
}

function openScreenshot(link) {
  const request = ++screenshotRequest;
  const source = $("img", link);
  expandedScreenshot.alt = source.alt;
  $("#screenshot-caption").textContent = link.dataset.caption ||
    "Real app capture. Transcripts and Words replies can contain errors.";
  let revealed = false;
  const reveal = () => {
    if (revealed || request !== screenshotRequest) return;
    revealed = true;
    screenshotSource = source;
    const animate = !prefersReducedMotion() &&
      typeof document.startViewTransition === "function";
    if (!animate) {
      screenshotDialog.showModal();
      return;
    }
    source.style.viewTransitionName = "expanded-shot";
    runViewTransition(() => {
      screenshotDialog.showModal();
      source.style.viewTransitionName = "";
      source.style.visibility = "hidden";
      expandedScreenshot.style.viewTransitionName = "expanded-shot";
    }, "screenshot").finally(() => {
      source.style.visibility = "";
      source.style.viewTransitionName = "";
      expandedScreenshot.style.viewTransitionName = "";
    });
  };
  if (expandedScreenshot.src !== link.href) {
    expandedScreenshot.addEventListener("load", reveal, { once: true });
    expandedScreenshot.src = link.href;
    if (expandedScreenshot.complete && expandedScreenshot.naturalWidth) reveal();
    return;
  }
  reveal();
}

function closeScreenshot() {
  const source = screenshotSource;
  const animate = source && !prefersReducedMotion() &&
    typeof document.startViewTransition === "function";
  if (!animate) {
    screenshotDialog.close();
    screenshotSource = null;
    return;
  }
  expandedScreenshot.style.viewTransitionName = "expanded-shot";
  runViewTransition(() => {
    screenshotDialog.close();
    expandedScreenshot.style.viewTransitionName = "";
    source.style.viewTransitionName = "expanded-shot";
  }, "screenshot").finally(() => {
    source.style.viewTransitionName = "";
    expandedScreenshot.style.viewTransitionName = "";
    screenshotSource = null;
  });
}

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
