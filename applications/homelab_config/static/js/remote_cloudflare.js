"use strict";

const socket = io();

const els = {
  zone: document.getElementById("f-zone"),
  rows: document.getElementById("record-rows"),
  empty: document.getElementById("empty-state"),
  tfvars: document.getElementById("tfvars-preview"),
  form: document.getElementById("record-form"),
  origKey: document.getElementById("f-id"),
  key: document.getElementById("f-key"),
  name: document.getElementById("f-name"),
  content: document.getElementById("f-content"),
  ttl: document.getElementById("f-ttl"),
  proxied: document.getElementById("f-proxied"),
  formTitle: document.getElementById("form-title"),
  saveBtn: document.getElementById("save-btn"),
  cancelEdit: document.getElementById("cancel-edit"),
  reloadBtn: document.getElementById("reload-btn"),
  previewBtn: document.getElementById("preview-btn"),
  previewModal: document.getElementById("modal-preview"),
  previewCopy: document.getElementById("preview-copy"),
  saveState: document.getElementById("save-state"),
  driftBanner: document.getElementById("drift-banner"),
  driftMessage: document.getElementById("drift-message"),
  driftReload: document.getElementById("drift-reload"),
};

let currentRecords = [];

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

function isEditing() {
  return Boolean(els.origKey.value);
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

function renderRecords(records) {
  currentRecords = records;
  els.rows.innerHTML = "";
  if (!records.length) {
    els.empty.hidden = false;
    return;
  }
  els.empty.hidden = true;

  records.forEach((record) => {
    const proxiedHtml = record.proxied
      ? '<span class="rounded-full bg-orange-500/15 px-2 py-0.5 text-xs font-medium text-orange-300">proxied</span>'
      : '<span class="text-xs text-slate-600">DNS only</span>';
    const row = document.createElement("tr");
    row.className = "hover:bg-slate-800/40";
    row.innerHTML = `
      <td class="px-4 py-3">
        <div class="font-medium text-slate-100">${escapeHtml(record.name)}</div>
        <div class="font-mono text-xs text-slate-500">${escapeHtml(record.key)}</div>
      </td>
      <td class="px-4 py-3 font-mono text-xs text-slate-400">${escapeHtml(
        record.content
      )}</td>
      <td class="px-4 py-3 text-xs text-slate-400">${escapeHtml(record.ttl)}</td>
      <td class="px-4 py-3">${proxiedHtml}</td>
      <td class="px-4 py-3 text-right whitespace-nowrap">
        <button data-edit="${escapeHtml(record.key)}" class="mr-1 rounded-md px-2 py-1 text-slate-400 hover:bg-slate-700 hover:text-sky-300" title="Edit">
          <i class="fa-solid fa-pen"></i>
        </button>
        <button data-delete="${escapeHtml(record.key)}" class="rounded-md px-2 py-1 text-slate-400 hover:bg-slate-700 hover:text-rose-300" title="Delete">
          <i class="fa-solid fa-trash"></i>
        </button>
      </td>`;
    els.rows.appendChild(row);
  });
}

function renderStatus(status) {
  if (!status) return;
  els.driftBanner.style.display = status.external_change ? "flex" : "none";
}

function renderConfig(config) {
  if (!config) return;
  if (document.activeElement !== els.zone) {
    els.zone.value = config.zone_id || "";
  }
  renderRecords(config.records || []);
}

function renderTfvars(text) {
  els.tfvars.textContent = text || "";
}

async function refreshTfvars() {
  try {
    const data = await api("/api/remote/cloudflare/tfvars");
    renderTfvars(data.tfvars);
  } catch (err) {
    /* non-fatal */
  }
}

function resetForm() {
  els.origKey.value = "";
  els.form.reset();
  els.ttl.value = "1";
  els.formTitle.textContent = "Add A record";
  els.saveBtn.hidden = false;
  els.saveBtn.innerHTML = '<i class="fa-solid fa-plus mr-2"></i>Add record';
  els.cancelEdit.hidden = true;
}

function startEdit(record) {
  els.origKey.value = record.key;
  els.key.value = record.key;
  els.name.value = record.name;
  els.content.value = record.content;
  els.ttl.value = record.ttl;
  els.proxied.checked = Boolean(record.proxied);
  els.formTitle.textContent = `Edit ${record.key}`;
  els.saveBtn.hidden = true;
  els.cancelEdit.hidden = false;
  els.cancelEdit.innerHTML = '<i class="fa-solid fa-check mr-2"></i>Done';
  els.key.focus();
}

function buildPayload() {
  return {
    key: els.key.value.trim(),
    name: els.name.value.trim(),
    content: els.content.value.trim(),
    ttl: parseInt(els.ttl.value, 10) || 1,
    proxied: els.proxied.checked,
  };
}

async function autosaveEdit() {
  const orig = els.origKey.value;
  if (!orig) return;
  const payload = buildPayload();
  if (!payload.key || !payload.name || !payload.content) {
    setSaveState("error", "Key, name and content are required");
    return;
  }
  try {
    setSaveState("saving");
    const updated = await api(
      `/api/remote/cloudflare/records/${encodeURIComponent(orig)}`,
      { method: "PUT", body: JSON.stringify(payload) }
    );
    els.origKey.value = updated.key;
    els.formTitle.textContent = `Edit ${updated.key}`;
    setSaveState("saved");
    refreshTfvars();
  } catch (err) {
    setSaveState("error", err.message);
  }
}

const autosaveEditDebounced = debounce(autosaveEdit, 450);

async function saveZone() {
  try {
    setSaveState("saving");
    await api("/api/remote/cloudflare/zone", {
      method: "PUT",
      body: JSON.stringify({ zone_id: els.zone.value.trim() }),
    });
    setSaveState("saved");
    refreshTfvars();
  } catch (err) {
    setSaveState("error", err.message);
  }
}

const saveZoneDebounced = debounce(saveZone, 600);

els.zone.addEventListener("input", saveZoneDebounced);
els.zone.addEventListener("blur", saveZone);

els.form.addEventListener("submit", async (event) => {
  event.preventDefault();
  if (isEditing()) {
    autosaveEdit();
    return;
  }
  const payload = buildPayload();
  try {
    await api("/api/remote/cloudflare/records", {
      method: "POST",
      body: JSON.stringify(payload),
    });
    toast(`Added ${payload.key}`, "success");
    resetForm();
    refreshTfvars();
  } catch (err) {
    toast(err.message, "error");
  }
});

els.cancelEdit.addEventListener("click", resetForm);

[els.key, els.name, els.content, els.ttl, els.proxied].forEach((el) =>
  el.addEventListener("input", () => {
    if (isEditing()) autosaveEditDebounced();
  })
);

els.rows.addEventListener("click", async (event) => {
  const editBtn = event.target.closest("[data-edit]");
  if (editBtn) {
    const record = currentRecords.find((r) => r.key === editBtn.dataset.edit);
    if (record) startEdit(record);
    return;
  }
  const delBtn = event.target.closest("[data-delete]");
  if (delBtn) {
    if (!confirm(`Delete DNS record "${delBtn.dataset.delete}"?`)) return;
    try {
      await api(
        `/api/remote/cloudflare/records/${encodeURIComponent(delBtn.dataset.delete)}`,
        { method: "DELETE" }
      );
      toast(`Deleted ${delBtn.dataset.delete}`, "success");
      refreshTfvars();
    } catch (err) {
      toast(err.message, "error");
    }
  }
});

async function doReload() {
  try {
    const data = await api("/api/remote/cloudflare/reload", { method: "POST" });
    renderConfig(data);
    renderStatus(data.status);
    resetForm();
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
    toast("Copied config.tfvars to clipboard", "success");
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

socket.on("cloudflare_dns:config", (config) => {
  renderConfig(config);
  refreshTfvars();
});
socket.on("cloudflare_dns:status", renderStatus);

async function init() {
  setSaveState("idle");
  try {
    const data = await api("/api/remote/cloudflare/config");
    renderConfig(data);
    renderStatus(data.status);
    refreshTfvars();
  } catch (err) {
    toast(err.message, "error");
  }
}

init();
