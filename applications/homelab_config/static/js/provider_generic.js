"use strict";

const socket = io();

const meta = JSON.parse(document.getElementById("provider-meta").textContent);
const API_BASE = `/api/${meta.key}`;

const els = {
  form: document.getElementById("provider-form"),
  tfvars: document.getElementById("tfvars-preview"),
  reloadBtn: document.getElementById("reload-btn"),
  previewBtn: document.getElementById("preview-btn"),
  previewModal: document.getElementById("modal-preview"),
  previewCopy: document.getElementById("preview-copy"),
  saveState: document.getElementById("save-state"),
  driftBanner: document.getElementById("drift-banner"),
  driftMessage: document.getElementById("drift-message"),
  driftReload: document.getElementById("drift-reload"),
};

// name -> { input, type } for every editable field on the form.
const fields = {};
document.querySelectorAll("[data-field]").forEach((input) => {
  fields[input.dataset.field] = { input, type: input.dataset.type };
});

// Suppress autosave while we programmatically populate the form (initial load,
// socket updates, reload) so hydration doesn't echo a write back to disk.
let hydrating = false;

function debounce(fn, ms) {
  let timer;
  return (...args) => {
    clearTimeout(timer);
    timer = setTimeout(() => fn(...args), ms);
  };
}

let saveStateTimer;
function setSaveState(kind, message) {
  clearTimeout(saveStateTimer);
  if (kind === "saving") {
    els.saveState.innerHTML = '<i class="fa-solid fa-circle-notch fa-spin"></i>';
    els.saveState.className = "text-sm text-sky-300";
    els.saveState.title = "Saving…";
  } else if (kind === "saved") {
    els.saveState.innerHTML = '<i class="fa-solid fa-cloud-arrow-up"></i>';
    els.saveState.className = "text-sm text-emerald-300";
    els.saveState.title = "Saved";
    saveStateTimer = setTimeout(() => setSaveState("idle"), 1000);
  } else if (kind === "error") {
    els.saveState.innerHTML = `<i class="fa-solid fa-triangle-exclamation mr-1 text-rose-400"></i>${escapeHtml(
      message || "Save failed"
    )}`;
    els.saveState.className = "text-xs font-medium text-rose-300";
    els.saveState.title = message || "Save failed";
  } else {
    els.saveState.innerHTML = '<i class="fa-solid fa-cloud"></i>';
    els.saveState.className = "text-sm text-slate-500";
    els.saveState.title = "Auto-save on";
  }
}

function escapeHtml(value) {
  return String(value ?? "").replace(
    /[&<>"']/g,
    (ch) =>
      ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[ch])
  );
}

async function api(path, options = {}) {
  const response = await fetch(path, {
    headers: { "Content-Type": "application/json" },
    ...options,
  });
  const data = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(data.error || `Request failed (${response.status})`);
  }
  return data;
}

function toast(message, kind = "info") {
  const palette = {
    info: "bg-slate-800 text-slate-100 border-slate-700",
    success: "bg-emerald-500/15 text-emerald-200 border-emerald-500/40",
    error: "bg-rose-500/15 text-rose-200 border-rose-500/40",
  };
  const el = document.createElement("div");
  el.className = `pointer-events-auto rounded-lg border px-4 py-2 text-sm shadow-lg ${
    palette[kind] || palette.info
  }`;
  el.textContent = message;
  document.getElementById("toast-root").appendChild(el);
  setTimeout(() => {
    el.style.transition = "opacity 300ms";
    el.style.opacity = "0";
    setTimeout(() => el.remove(), 300);
  }, 2600);
}

function renderCredentials(creds) {
  if (!creds) return;
  hydrating = true;
  Object.entries(fields).forEach(([name, { input, type }]) => {
    const value = creds[name];
    if (type === "bool") {
      input.checked = Boolean(value);
    } else {
      input.value = value === undefined || value === null ? "" : String(value);
    }
  });
  hydrating = false;
}

function renderStatus(status) {
  if (!status) return;
  if (status.external_change) {
    els.driftMessage.textContent = `${meta.tfvars_filename} changed on disk outside the app.`;
    els.driftBanner.style.display = "flex";
  } else {
    els.driftBanner.style.display = "none";
  }
}

function renderTfvars(text) {
  els.tfvars.textContent = text || "";
}

async function refreshTfvars() {
  try {
    const data = await api(`${API_BASE}/tfvars`);
    renderTfvars(data.tfvars);
  } catch (err) {
    /* non-fatal */
  }
}

function buildPayload() {
  const payload = {};
  Object.entries(fields).forEach(([name, { input, type }]) => {
    if (type === "bool") {
      payload[name] = input.checked;
    } else {
      payload[name] = input.value.trim();
    }
  });
  return payload;
}

async function autosave() {
  if (hydrating) return;
  try {
    setSaveState("saving");
    const updated = await api(`${API_BASE}/credentials`, {
      method: "PUT",
      body: JSON.stringify(buildPayload()),
    });
    renderCredentials(updated);
    setSaveState("saved");
    refreshTfvars();
  } catch (err) {
    setSaveState("error", err.message);
  }
}

const autosaveDebounced = debounce(autosave, 450);

Object.values(fields).forEach(({ input, type }) => {
  if (type === "bool") {
    input.addEventListener("change", () => {
      if (!hydrating) autosave();
    });
  } else {
    input.addEventListener("input", () => {
      if (!hydrating) autosaveDebounced();
    });
  }
});

// Never let an accidental Enter submit/reload the page; edits auto-save.
els.form.addEventListener("submit", (event) => {
  event.preventDefault();
  autosave();
});

document.querySelectorAll("[data-toggle]").forEach((btn) => {
  btn.addEventListener("click", () => {
    const field = fields[btn.dataset.toggle];
    if (!field) return;
    const shown = field.input.type === "text";
    field.input.type = shown ? "password" : "text";
    btn.innerHTML = shown
      ? '<i class="fa-solid fa-eye"></i>'
      : '<i class="fa-solid fa-eye-slash"></i>';
  });
});

async function doReload() {
  try {
    const data = await api(`${API_BASE}/reload`, { method: "POST" });
    renderCredentials(data.credentials);
    renderStatus(data.status);
    refreshTfvars();
    toast("Reloaded from disk", "success");
  } catch (err) {
    toast(err.message, "error");
  }
}

els.reloadBtn.addEventListener("click", doReload);
els.driftReload.addEventListener("click", doReload);

els.previewBtn.addEventListener("click", async () => {
  await refreshTfvars();
  els.previewModal.style.display = "flex";
});
els.previewCopy.addEventListener("click", async () => {
  try {
    await navigator.clipboard.writeText(els.tfvars.textContent || "");
    toast(`Copied ${meta.tfvars_filename} to clipboard`, "success");
  } catch (err) {
    toast("Could not copy to clipboard", "error");
  }
});
els.previewModal.addEventListener("click", (event) => {
  if (event.target === els.previewModal || event.target.closest("[data-close]")) {
    els.previewModal.style.display = "none";
  }
});
document.addEventListener("keydown", (event) => {
  if (event.key === "Escape") els.previewModal.style.display = "none";
});

socket.on(meta.credentials_event, (creds) => {
  renderCredentials(creds);
  refreshTfvars();
});
socket.on(meta.status_event, renderStatus);

async function init() {
  setSaveState("idle");
  try {
    const data = await api(`${API_BASE}/credentials`);
    renderCredentials(data.credentials);
    renderStatus(data.status);
    refreshTfvars();
  } catch (err) {
    toast(err.message, "error");
  }
}

init();
