const $ = (selector, parent = document) => parent.querySelector(selector);
const $$ = (selector, parent = document) => [
  ...parent.querySelectorAll(selector),
];

// Native dialogs provide keyboard focus trapping and return focus to their opener.
const tourDialog = $("#tour-dialog");
const tourVideo = $("#tour-video");

function openTour(time = 0) {
  tourDialog.showModal();
  const seekAndPlay = () => {
    if (!tourDialog.open) return;
    tourVideo.currentTime = time;
    tourVideo.play().catch(() => {
      /* Native controls remain available. */
    });
  };
  if (tourVideo.readyState >= 1) seekAndPlay();
  else
    tourVideo.addEventListener("loadedmetadata", seekAndPlay, { once: true });
  if (tourVideo.readyState === 0) tourVideo.load();
}

$$("[data-open-tour]").forEach((button) =>
  button.addEventListener("click", () =>
    openTour(Number(button.dataset.tourTime || 0)),
  ),
);
$$("[data-open-download]").forEach((button) =>
  button.addEventListener("click", (event) => {
    event.preventDefault();
    $("#download-dialog").showModal();
  }),
);
$$("[data-open-privacy]").forEach((button) =>
  button.addEventListener("click", () => $("#privacy-dialog").showModal()),
);
$$("[data-close-dialog]").forEach((button) =>
  button.addEventListener("click", () => button.closest("dialog").close()),
);
$$("dialog").forEach((dialog) => {
  dialog.addEventListener("click", (event) => {
    const bounds = dialog.getBoundingClientRect();
    if (
      event.target === dialog &&
      (event.clientX < bounds.left ||
        event.clientX > bounds.right ||
        event.clientY < bounds.top ||
        event.clientY > bounds.bottom)
    )
      dialog.close();
  });
});
tourDialog.addEventListener("close", () => tourVideo.pause());
$$("[data-seek]").forEach((button) =>
  button.addEventListener("click", () => {
    tourVideo.currentTime = Number(button.dataset.seek);
    tourVideo.play().catch(() => {});
  }),
);
tourVideo.addEventListener("timeupdate", () => {
  const chapters = $$("[data-seek]");
  const current = chapters.findLast(
    (button) => Number(button.dataset.seek) <= tourVideo.currentTime,
  );
  chapters.forEach((button) =>
    button.setAttribute("aria-current", String(button === current)),
  );
});

function selectTab(tabs, active) {
  tabs.forEach((tab) => {
    const selected = tab === active;
    tab.setAttribute("aria-selected", String(selected));
    tab.tabIndex = selected ? 0 : -1;
  });
}

function supportTabKeys(tabs, activate) {
  tabs.forEach((tab, index) =>
    tab.addEventListener("keydown", (event) => {
      const vertical =
        tab.closest('[role="tablist"]').getAttribute("aria-orientation") ===
        "vertical";
      const previous = vertical ? "ArrowUp" : "ArrowLeft";
      const next = vertical ? "ArrowDown" : "ArrowRight";
      let target;
      if (event.key === previous)
        target = tabs[(index + tabs.length - 1) % tabs.length];
      if (event.key === next) target = tabs[(index + 1) % tabs.length];
      if (event.key === "Home") target = tabs[0];
      if (event.key === "End") target = tabs.at(-1);
      if (!target) return;
      event.preventDefault();
      activate(target);
      target.focus();
    }),
  );
}

const stepTabs = $$("[data-step]");
function showStep(step) {
  const active = stepTabs.find((tab) => tab.dataset.step === step);
  if (!active) return;
  selectTab(stepTabs, active);
  $("#practice-panel").setAttribute("aria-labelledby", active.id);
  $$("[data-view]").forEach((panel) => {
    panel.hidden = panel.dataset.view !== step;
  });
  if (step === "record") drawWaveform();
}
stepTabs.forEach((tab) =>
  tab.addEventListener("click", () => showStep(tab.dataset.step)),
);
supportTabKeys(stepTabs, (tab) => showStep(tab.dataset.step));
$$("[data-next-step]").forEach((button) =>
  button.addEventListener("click", () => {
    showStep(button.dataset.nextStep);
    $("#practice-panel").focus({ preventScroll: true });
  }),
);

// An explicitly illustrative waveform; no microphone or recording API is used.
function drawWaveform() {
  const canvas = $(".waveform");
  const context = canvas.getContext("2d");
  const width = canvas.clientWidth;
  if (!context || !width) return;
  const height = canvas.clientHeight;
  const ratio = Math.min(window.devicePixelRatio || 1, 2);
  canvas.width = width * ratio;
  canvas.height = height * ratio;
  context.scale(ratio, ratio);
  context.clearRect(0, 0, width, height);
  const count = Math.floor(width / 5);
  for (let i = 0; i < count; i++) {
    const x = i / count;
    const gap = (x > 0.22 && x < 0.31) || (x > 0.61 && x < 0.68) || x > 0.92;
    const envelope = Math.pow(Math.sin(x * Math.PI * 4.1), 2);
    const amplitude = gap
      ? 2
      : 5 +
        (Math.abs(Math.sin(i * 5.71)) * 0.65 + 0.35) * envelope * (height - 12);
    context.fillStyle = gap ? "#b7beb2" : "#2449e9";
    context.fillRect(i * 5, (height - amplitude) / 2, 2, amplitude);
  }
}
new ResizeObserver(drawWaveform).observe($(".waveform"));
drawWaveform();

const appViews = {
  compare: {
    image: "assets/mimic-compare.jpg",
    alt: "Real Voice Coach Mimic screen comparing the reference and your delivery",
    label: "SIDE BY SIDE",
  },
  analysis: {
    image: "assets/take-analysis.jpg",
    alt: "Real Voice Coach take analysis with transcript and acoustic timeline",
    label: "A CLOSER LISTEN",
  },
  library: {
    image: "assets/library.jpg",
    alt: "Real Voice Coach library of local recordings and takes",
    label: "ALL YOUR TAKES",
  },
};
$$("[data-app-view]").forEach((button) =>
  button.addEventListener("click", () => {
    const view = appViews[button.dataset.appView];
    $("#mimic-image").src = view.image;
    $("#mimic-image").alt = view.alt;
    $(".compare-label").textContent = view.label;
    $$(".mimic-switcher button").forEach((item) =>
      item.setAttribute("aria-pressed", String(item === button)),
    );
  }),
);

const moments = {
  talk: {
    eyebrow: "BEFORE YOU TAKE THE ROOM",
    quote: "“I want the opening<br>to feel like <em>me.</em>”",
    description:
      "Run through the first minute. Hear where you rush, leave a gap, or lose the shape of a sentence. Then give it another go.",
  },
  pitch: {
    eyebrow: "BEFORE YOU SHARE THE BIG IDEA",
    quote: "“The idea is there.<br>Let’s make it <em>land.</em>”",
    description:
      "Say the short version out loud. Listen for the pauses and the words you want to emphasize. Try a different rhythm on the next take.",
  },
  interview: {
    eyebrow: "BEFORE THE FIRST QUESTION",
    quote: "“So, tell me a little<br>about <em>yourself.</em>”",
    description:
      "Give your answer some room before the real conversation. Record, listen back, and practice saying it in a way that feels like you.",
  },
};
const momentTabs = $$("[data-moment]");
function showMoment(key) {
  const moment = moments[key];
  const tab = momentTabs.find((item) => item.dataset.moment === key);
  if (!moment || !tab) return;
  selectTab(momentTabs, tab);
  $("#occasion-panel").setAttribute("aria-labelledby", tab.id);
  $("#occasion-eyebrow").textContent = moment.eyebrow;
  $("#occasion-quote").innerHTML = moment.quote;
  $("#occasion-description").textContent = moment.description;
}
momentTabs.forEach((tab) =>
  tab.addEventListener("click", () => showMoment(tab.dataset.moment)),
);
supportTabKeys(momentTabs, (tab) => showMoment(tab.dataset.moment));
$$("[data-occasion]").forEach((link) =>
  link.addEventListener("click", () => showMoment(link.dataset.occasion)),
);

// Keep the FAQ compact while retaining native details/summary keyboard behavior.
$$(".faq-list details").forEach((detail) =>
  detail.addEventListener("toggle", () => {
    if (detail.open)
      $$(".faq-list details").forEach((other) => {
        if (other !== detail) other.open = false;
      });
  }),
);
