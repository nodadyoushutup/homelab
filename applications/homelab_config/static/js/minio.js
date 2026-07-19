"use strict";

const socket = io();

const els = {
  rows: document.getElementById("instance-rows"),
  empty: document.getElementById("empty-state"),
  tfvars: document.getElementById("tfvars-preview"),
  form: document.getElementById("instance-form"),
  origName: document.getElementById("f-id"),
  name: document.getElementById("f-name"),
  endpoint: document.getElementById("f-endpoint"),
  region: document.getElementById("f-region"),
  accessKey: document.getElementById("f-access-key"),
  secretKey: document.getElementById("f-secret-key"),
  toggleSecret: document.getElementById("toggle-secret"),
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

let currentInstances = [];

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

function renderInstances(instances) {
  currentInstances = instances;
  els.rows.innerHTML = "";
  if (!instances.length) {
    els.empty.hidden = false;
    return;
  }
  els.empty.hidden = true;

  instances.forEach((inst) => {
    const accessHtml = inst.access_key
      ? `<span class="font-mono text-xs text-slate-400">${escapeHtml(inst.access_key)}</span>`
      : `<span class="text-xs text-slate-600">&mdash;</span>`;
    const row = document.createElement("tr");
    row.className = "hover:bg-slate-800/40";
    row.innerHTML = `
      <td class="px-4 py-3">
        <div class="font-medium text-slate-100">${escapeHtml(inst.name)}</div>
      </td>
      <td class="px-4 py-3 font-mono text-xs text-slate-400">${escapeHtml(
        inst.endpoint
      )}</td>
      <td class="px-4 py-3 font-mono text-xs text-slate-400">${escapeHtml(
        inst.region
      )}</td>
      <td class="px-4 py-3">${accessHtml}</td>
      <td class="px-4 py-3 text-right whitespace-nowrap">
        <button data-edit="${escapeHtml(inst.name)}" class="mr-1 rounded-md px-2 py-1 text-slate-400 hover:bg-slate-700 hover:text-sky-300" title="Edit">
          <i class="fa-solid fa-pen"></i>
        </button>
        <button data-delete="${escapeHtml(inst.name)}" class="rounded-md px-2 py-1 text-slate-400 hover:bg-slate-700 hover:text-rose-300" title="Delete">
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
      "minio.tfvars changed on disk outside the app.";
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
    const data = await api("/api/minio/tfvars");
    renderTfvars(data.tfvars);
  } catch (err) {
    /* non-fatal */
  }
}

function resetForm() {
  els.origName.value = "";
  els.form.reset();
  els.formTitle.textContent = "Add MinIO instance";
  els.saveBtn.hidden = false;
  els.saveBtn.innerHTML = '<i class="fa-solid fa-plus mr-2"></i>Add instance';
  els.cancelEdit.hidden = true;
}

function startEdit(inst) {
  els.origName.value = inst.name;
  els.name.value = inst.name;
  els.endpoint.value = inst.endpoint;
  els.region.value = inst.region;
  els.accessKey.value = inst.access_key;
  els.secretKey.value = inst.secret_key;
  els.formTitle.textContent = `Edit ${inst.name}`;
  // No submit button while editing — changes auto-save as you type.
  els.saveBtn.hidden = true;
  els.cancelEdit.hidden = false;
  els.cancelEdit.innerHTML = '<i class="fa-solid fa-check mr-2"></i>Done';
  els.name.focus();
}

function buildPayload() {
  return {
    name: els.name.value.trim(),
    endpoint: els.endpoint.value.trim(),
    region: els.region.value.trim(),
    access_key: els.accessKey.value.trim(),
    secret_key: els.secretKey.value.trim(),
  };
}

// Auto-save the instance currently being edited. Skips while the form is not a
// valid instance so partial keystrokes don't blow away the on-disk value.
async function autosaveEdit() {
  const orig = els.origName.value;
  if (!orig) return;
  const payload = buildPayload();
  if (!payload.name || !payload.endpoint) {
    setSaveState("error", "Name and endpoint are required");
    return;
  }
  try {
    setSaveState("saving");
    const updated = await api(`/api/minio/instances/${encodeURIComponent(orig)}`, {
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
    await api("/api/minio/instances", {
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
  els.endpoint,
  els.region,
  els.accessKey,
  els.secretKey,
];
textFields.forEach((el) =>
  el.addEventListener("input", () => {
    if (isEditing()) autosaveEditDebounced();
  })
);

els.toggleSecret.addEventListener("click", () => {
  const shown = els.secretKey.type === "text";
  els.secretKey.type = shown ? "password" : "text";
  els.toggleSecret.innerHTML = shown
    ? '<i class="fa-solid fa-eye"></i>'
    : '<i class="fa-solid fa-eye-slash"></i>';
});

els.rows.addEventListener("click", async (event) => {
  const editBtn = event.target.closest("[data-edit]");
  if (editBtn) {
    const inst = currentInstances.find((s) => s.name === editBtn.dataset.edit);
    if (inst) startEdit(inst);
    return;
  }
  const delBtn = event.target.closest("[data-delete]");
  if (delBtn) {
    if (!confirm(`Delete MinIO instance "${delBtn.dataset.delete}"?`)) return;
    try {
      await api(`/api/minio/instances/${encodeURIComponent(delBtn.dataset.delete)}`, {
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
    const data = await api("/api/minio/reload", { method: "POST" });
    renderInstances(data.instances);
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
    toast("Copied minio.tfvars to clipboard", "success");
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

socket.on("minio:instances", (instances) => {
  renderInstances(instances);
  refreshTfvars();
});
socket.on("minio:status", renderStatus);

async function init() {
  setSaveState("idle");
  try {
    const data = await api("/api/minio/instances");
    renderInstances(data.instances);
    renderStatus(data.status);
    refreshTfvars();
  } catch (err) {
    toast(err.message, "error");
  }
}

init();
