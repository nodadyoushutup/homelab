"use strict";

const socket = io();

const els = {
  rows: document.getElementById("share-rows"),
  empty: document.getElementById("empty-state"),
  tfvars: document.getElementById("tfvars-preview"),
  form: document.getElementById("share-form"),
  origName: document.getElementById("f-id"),
  name: document.getElementById("f-name"),
  server: document.getElementById("f-server"),
  export: document.getElementById("f-export"),
  mountPoint: document.getElementById("f-mount-point"),
  options: document.getElementById("f-options"),
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

let currentShares = [];

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
  return Boolean(els.origName.value);
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

function renderShares(shares) {
  currentShares = shares;
  els.rows.innerHTML = "";
  if (!shares.length) {
    els.empty.hidden = false;
    return;
  }
  els.empty.hidden = true;

  shares.forEach((share) => {
    const optionsHtml = share.options
      ? `<span class="font-mono text-xs text-slate-400">${escapeHtml(share.options)}</span>`
      : `<span class="text-xs text-slate-600">&mdash;</span>`;
    const row = document.createElement("tr");
    row.className = "hover:bg-slate-800/40";
    row.innerHTML = `
      <td class="px-4 py-3">
        <div class="font-medium text-slate-100">${escapeHtml(share.name)}</div>
        <div class="font-mono text-xs text-slate-500">${escapeHtml(share.export)}</div>
      </td>
      <td class="px-4 py-3 font-mono text-xs text-slate-400">${escapeHtml(
        share.server
      )}</td>
      <td class="px-4 py-3 font-mono text-xs text-slate-400">${escapeHtml(
        share.mount_point
      )}</td>
      <td class="px-4 py-3 max-w-md truncate" title="${escapeHtml(share.options)}">${optionsHtml}</td>
      <td class="px-4 py-3 text-right whitespace-nowrap">
        <button data-edit="${escapeHtml(share.name)}" class="mr-1 rounded-md px-2 py-1 text-slate-400 hover:bg-slate-700 hover:text-sky-300" title="Edit">
          <i class="fa-solid fa-pen"></i>
        </button>
        <button data-delete="${escapeHtml(share.name)}" class="rounded-md px-2 py-1 text-slate-400 hover:bg-slate-700 hover:text-rose-300" title="Delete">
          <i class="fa-solid fa-trash"></i>
        </button>
      </td>`;
    els.rows.appendChild(row);
  });
}

function renderStatus(status) {
  if (!status) return;
  if (status.external_change) {
    els.driftMessage.textContent =
      "nfs.tfvars changed on disk outside the app.";
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
    const data = await api("/api/nfs/tfvars");
    renderTfvars(data.tfvars);
  } catch (err) {
    /* non-fatal */
  }
}

function resetForm() {
  els.origName.value = "";
  els.form.reset();
  els.formTitle.textContent = "Add NFS share";
  els.saveBtn.hidden = false;
  els.saveBtn.innerHTML = '<i class="fa-solid fa-plus mr-2"></i>Add share';
  els.cancelEdit.hidden = true;
}

function startEdit(share) {
  els.origName.value = share.name;
  els.name.value = share.name;
  els.server.value = share.server;
  els.export.value = share.export;
  els.mountPoint.value = share.mount_point;
  els.options.value = share.options;
  els.formTitle.textContent = `Edit ${share.name}`;
  // No submit button while editing — changes auto-save as you type.
  els.saveBtn.hidden = true;
  els.cancelEdit.hidden = false;
  els.cancelEdit.innerHTML = '<i class="fa-solid fa-check mr-2"></i>Done';
  els.name.focus();
}

function buildPayload() {
  return {
    name: els.name.value.trim(),
    server: els.server.value.trim(),
    export: els.export.value.trim(),
    mount_point: els.mountPoint.value.trim(),
    options: els.options.value.trim(),
  };
}

// Auto-save the share currently being edited. Skips while the form is not a
// valid share so partial keystrokes don't blow away the on-disk value.
async function autosaveEdit() {
  const orig = els.origName.value;
  if (!orig) return;
  const payload = buildPayload();
  if (!payload.name || !payload.server || !payload.export) {
    setSaveState("error", "Name, server and export are required");
    return;
  }
  try {
    setSaveState("saving");
    const updated = await api(`/api/nfs/shares/${encodeURIComponent(orig)}`, {
      method: "PUT",
      body: JSON.stringify(payload),
    });
    els.origName.value = updated.name;
    els.formTitle.textContent = `Edit ${updated.name}`;
    setSaveState("saved");
    refreshTfvars();
  } catch (err) {
    setSaveState("error", err.message);
  }
}

const autosaveEditDebounced = debounce(autosaveEdit, 450);

els.form.addEventListener("submit", async (event) => {
  event.preventDefault();
  if (isEditing()) {
    autosaveEdit();
    return;
  }
  const payload = buildPayload();
  try {
    await api("/api/nfs/shares", {
      method: "POST",
      body: JSON.stringify(payload),
    });
    toast(`Added ${payload.name}`, "success");
    resetForm();
    refreshTfvars();
  } catch (err) {
    toast(err.message, "error");
  }
});

els.cancelEdit.addEventListener("click", resetForm);

const textFields = [
  els.name,
  els.server,
  els.export,
  els.mountPoint,
  els.options,
];
textFields.forEach((el) =>
  el.addEventListener("input", () => {
    if (isEditing()) autosaveEditDebounced();
  })
);

els.rows.addEventListener("click", async (event) => {
  const editBtn = event.target.closest("[data-edit]");
  if (editBtn) {
    const share = currentShares.find((s) => s.name === editBtn.dataset.edit);
    if (share) startEdit(share);
    return;
  }
  const delBtn = event.target.closest("[data-delete]");
  if (delBtn) {
    if (!confirm(`Delete NFS share "${delBtn.dataset.delete}"?`)) return;
    try {
      await api(`/api/nfs/shares/${encodeURIComponent(delBtn.dataset.delete)}`, {
        method: "DELETE",
      });
      toast(`Deleted ${delBtn.dataset.delete}`, "success");
      refreshTfvars();
    } catch (err) {
      toast(err.message, "error");
    }
  }
});

async function doReload() {
  try {
    const data = await api("/api/nfs/reload", { method: "POST" });
    renderShares(data.shares);
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
    toast("Copied nfs.tfvars to clipboard", "success");
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

socket.on("nfs:shares", (shares) => {
  renderShares(shares);
  refreshTfvars();
});
socket.on("nfs:status", renderStatus);

async function init() {
  setSaveState("idle");
  try {
    const data = await api("/api/nfs/shares");
    renderShares(data.shares);
    renderStatus(data.status);
    refreshTfvars();
  } catch (err) {
    toast(err.message, "error");
  }
}

init();
