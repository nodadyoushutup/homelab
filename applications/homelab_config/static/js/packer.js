"use strict";

const socket = io();
const API = "/api/packer";

const TEXT_FIELDS = [
  "distro",
  "image_version",
  "gui",
  "ubuntu_release",
  "centos_stream",
  "arch_snapshot",
  "kali_release",
  "target",
  "build_arch",
  "amd64_accelerator",
  "arm64_accelerator",
];
const BOOL_FIELDS = ["install_node_exporter", "publish"];

let settings = {};

function $(id) {
  return document.getElementById(id);
}

let saveStateTimer;
function setSaveState(kind, message) {
  const el = $("save-state");
  clearTimeout(saveStateTimer);
  if (kind === "saving") {
    el.innerHTML = '<i class="fa-solid fa-circle-notch fa-spin"></i>';
    el.className = "text-sm text-sky-300";
  } else if (kind === "saved") {
    el.innerHTML = '<i class="fa-solid fa-cloud-arrow-up"></i>';
    el.className = "text-sm text-emerald-300";
    saveStateTimer = setTimeout(() => setSaveState("idle"), 1000);
  } else if (kind === "error") {
    el.innerHTML = `<i class="fa-solid fa-triangle-exclamation mr-1 text-rose-400"></i>${escapeHtml(message || "Save failed")}`;
    el.className = "text-xs font-medium text-rose-300";
  } else {
    el.innerHTML = '<i class="fa-solid fa-cloud"></i>';
    el.className = "text-sm text-slate-500";
  }
}

function escapeHtml(value) {
  return String(value ?? "").replace(/[&<>"']/g, (ch) =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[ch])
  );
}

function debounce(fn, ms) {
  let t;
  return (...a) => {
    clearTimeout(t);
    t = setTimeout(() => fn(...a), ms);
  };
}

async function api(path, options = {}) {
  const response = await fetch(path, {
    headers: { "Content-Type": "application/json" },
    ...options,
  });
  const data = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(data.error || `Request failed (${response.status})`);
  return data;
}

function toast(message, kind = "info") {
  const palette = {
    info: "bg-slate-800 text-slate-100 border-slate-700",
    success: "bg-emerald-500/15 text-emerald-200 border-emerald-500/40",
    error: "bg-rose-500/15 text-rose-200 border-rose-500/40",
  };
  const el = document.createElement("div");
  el.className = `pointer-events-auto rounded-lg border px-4 py-2 text-sm shadow-lg ${palette[kind] || palette.info}`;
  el.textContent = message;
  document.getElementById("toast-root").appendChild(el);
  setTimeout(() => {
    el.style.transition = "opacity 300ms";
    el.style.opacity = "0";
    setTimeout(() => el.remove(), 300);
  }, 2600);
}

function isEditing() {
  const el = document.activeElement;
  return el && (el.matches("input") || el.matches("textarea") || el.matches("select"));
}

function render() {
  if (isEditing()) return;
  TEXT_FIELDS.forEach((f) => {
    if ($(f)) $(f).value = settings[f] ?? "";
  });
  BOOL_FIELDS.forEach((f) => {
    if ($(f)) $(f).checked = Boolean(settings[f]);
  });
}

function renderStatus(status) {
  if (!status) return;
  $("drift-banner").style.display = status.external_change ? "flex" : "none";
}

async function refreshTfvars() {
  try {
    const data = await api(`${API}/tfvars`);
    $("tfvars-preview").textContent = data.tfvars || "";
  } catch (err) {
    /* non-fatal */
  }
}

function collect() {
  const out = {};
  TEXT_FIELDS.forEach((f) => {
    out[f] = $(f) ? $(f).value.trim() : "";
  });
  BOOL_FIELDS.forEach((f) => {
    out[f] = $(f) ? $(f).checked : false;
  });
  return out;
}

async function save() {
  try {
    setSaveState("saving");
    const saved = await api(`${API}/config`, {
      method: "PUT",
      body: JSON.stringify(collect()),
    });
    settings = saved;
    setSaveState("saved");
    refreshTfvars();
  } catch (err) {
    setSaveState("error", err.message);
  }
}
const saveDebounced = debounce(save, 600);

TEXT_FIELDS.forEach((f) => {
  const el = $(f);
  if (!el) return;
  el.addEventListener(el.tagName === "SELECT" ? "change" : "input", saveDebounced);
});
BOOL_FIELDS.forEach((f) => {
  const el = $(f);
  if (el) el.addEventListener("change", save);
});

async function doReload() {
  try {
    const data = await api(`${API}/reload`, { method: "POST" });
    settings = data.config;
    render();
    renderStatus(data.status);
    refreshTfvars();
    toast("Reloaded from disk", "success");
  } catch (err) {
    toast(err.message, "error");
  }
}
$("reload-btn").addEventListener("click", doReload);
$("drift-reload").addEventListener("click", doReload);

$("preview-btn").addEventListener("click", async () => {
  await refreshTfvars();
  $("modal-preview").style.display = "flex";
});
$("preview-copy").addEventListener("click", async () => {
  try {
    await navigator.clipboard.writeText($("tfvars-preview").textContent || "");
    toast("Copied build.pkrvars.hcl to clipboard", "success");
  } catch (err) {
    toast("Could not copy to clipboard", "error");
  }
});
document.querySelectorAll("[data-close]").forEach((btn) =>
  btn.addEventListener("click", () => {
    const modal = btn.closest(".fixed");
    if (modal) modal.style.display = "none";
  })
);
document.querySelectorAll(".fixed").forEach((modal) =>
  modal.addEventListener("click", (event) => {
    if (event.target === modal) modal.style.display = "none";
  })
);
document.addEventListener("keydown", (event) => {
  if (event.key === "Escape") document.querySelectorAll(".fixed").forEach((m) => (m.style.display = "none"));
});

socket.on("packer:config", (payload) => {
  settings = payload || settings;
  render();
  refreshTfvars();
});
socket.on("packer:status", renderStatus);

async function init() {
  setSaveState("idle");
  try {
    const data = await api(`${API}/config`);
    settings = data.config;
    render();
    renderStatus(data.status);
    refreshTfvars();
  } catch (err) {
    toast(err.message, "error");
  }
}

init();
