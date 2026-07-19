"use strict";

const socket = io();

const els = {
  form: document.getElementById("proxmox-form"),
  endpoint: document.getElementById("f-endpoint"),
  username: document.getElementById("f-username"),
  password: document.getElementById("f-password"),
  insecure: document.getElementById("f-insecure"),
  randomVmIds: document.getElementById("f-random-vm-ids"),
  sshAgent: document.getElementById("f-ssh-agent"),
  togglePassword: document.getElementById("toggle-password"),
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
  els.endpoint.value = creds.endpoint || "";
  els.username.value = creds.username || "";
  els.password.value = creds.password || "";
  els.insecure.checked = Boolean(creds.insecure);
  els.randomVmIds.checked = Boolean(creds.random_vm_ids);
  els.sshAgent.checked = Boolean(creds.ssh_agent);
  hydrating = false;
}

function renderStatus(status) {
  if (!status) return;
  if (status.external_change) {
    els.driftMessage.textContent =
      "proxmox.tfvars changed on disk outside the app.";
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
    const data = await api("/api/proxmox/tfvars");
    renderTfvars(data.tfvars);
  } catch (err) {
    /* non-fatal */
  }
}

function buildPayload() {
  return {
    endpoint: els.endpoint.value.trim(),
    username: els.username.value.trim(),
    password: els.password.value,
    insecure: els.insecure.checked,
    random_vm_ids: els.randomVmIds.checked,
    ssh_agent: els.sshAgent.checked,
  };
}

async function autosave() {
  if (hydrating) return;
  try {
    setSaveState("saving");
    const updated = await api("/api/proxmox/credentials", {
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

[els.endpoint, els.username, els.password].forEach((el) =>
  el.addEventListener("input", () => {
    if (!hydrating) autosaveDebounced();
  })
);
[els.insecure, els.randomVmIds, els.sshAgent].forEach((el) =>
  el.addEventListener("change", () => {
    if (!hydrating) autosave();
  })
);

// Never let an accidental Enter submit/reload the page; edits auto-save.
els.form.addEventListener("submit", (event) => {
  event.preventDefault();
  autosave();
});

els.togglePassword.addEventListener("click", () => {
  const shown = els.password.type === "text";
  els.password.type = shown ? "password" : "text";
  els.togglePassword.innerHTML = shown
    ? '<i class="fa-solid fa-eye"></i>'
    : '<i class="fa-solid fa-eye-slash"></i>';
});

async function doReload() {
  try {
    const data = await api("/api/proxmox/reload", { method: "POST" });
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
    toast("Copied proxmox.tfvars to clipboard", "success");
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

socket.on("proxmox:credentials", (creds) => {
  renderCredentials(creds);
  refreshTfvars();
});
socket.on("proxmox:status", renderStatus);

async function init() {
  setSaveState("idle");
  try {
    const data = await api("/api/proxmox/credentials");
    renderCredentials(data.credentials);
    renderStatus(data.status);
    refreshTfvars();
  } catch (err) {
    toast(err.message, "error");
  }
}

init();
