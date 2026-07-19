"use strict";

const socket = io();

const els = {
  form: document.getElementById("terraform-form"),
  backendLocal: document.getElementById("f-backend-local"),
  backendS3: document.getElementById("f-backend-s3"),
  minio: document.getElementById("f-minio"),
  minioHint: document.getElementById("minio-hint"),
  bucket: document.getElementById("f-bucket"),
  region: document.getElementById("f-region"),
  skipCredentialsValidation: document.getElementById("f-skip-credentials-validation"),
  skipMetadataApiCheck: document.getElementById("f-skip-metadata-api-check"),
  skipRequestingAccountId: document.getElementById("f-skip-requesting-account-id"),
  usePathStyle: document.getElementById("f-use-path-style"),
  s3Fields: document.getElementById("s3-fields"),
  localNote: document.getElementById("local-note"),
  backendPreview: document.getElementById("backend-preview"),
  reloadBtn: document.getElementById("reload-btn"),
  previewBtn: document.getElementById("preview-btn"),
  previewModal: document.getElementById("modal-preview"),
  previewCopy: document.getElementById("preview-copy"),
  saveState: document.getElementById("save-state"),
  driftBanner: document.getElementById("drift-banner"),
  driftMessage: document.getElementById("drift-message"),
  driftReload: document.getElementById("drift-reload"),
};

// Suppress autosave while we programmatically populate the form.
let hydrating = false;
let currentMinios = [];

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

function currentBackend() {
  return els.backendS3.checked ? "s3" : "local";
}

function applyBackendVisibility() {
  const isS3 = currentBackend() === "s3";
  els.s3Fields.style.display = isS3 ? "contents" : "none";
  els.localNote.hidden = isS3;
}

function renderMinioOptions(minios, selected) {
  currentMinios = minios || [];
  const chosen = selected ?? els.minio.value;
  els.minio.innerHTML = '<option value="">— Select a MinIO —</option>';
  currentMinios.forEach((name) => {
    const opt = document.createElement("option");
    opt.value = name;
    opt.textContent = name;
    els.minio.appendChild(opt);
  });
  // Preserve a selection even if it is no longer in the catalog, so we surface
  // the mismatch instead of silently clearing it.
  if (chosen && !currentMinios.includes(chosen)) {
    const opt = document.createElement("option");
    opt.value = chosen;
    opt.textContent = `${chosen} (not in catalog)`;
    els.minio.appendChild(opt);
  }
  els.minio.value = chosen || "";
  els.minioHint.textContent = currentMinios.length
    ? "Pick one of your MinIO instances for remote state"
    : "No MinIO instances yet — add one on the MinIO page first";
}

function renderSettings(settings) {
  if (!settings) return;
  hydrating = true;
  if (settings.backend === "local") {
    els.backendLocal.checked = true;
  } else {
    els.backendS3.checked = true;
  }
  els.minio.value = settings.minio || "";
  // Re-add a missing selection option if needed.
  if (settings.minio && !currentMinios.includes(settings.minio)) {
    renderMinioOptions(currentMinios, settings.minio);
  }
  els.bucket.value = settings.bucket || "";
  els.region.value = settings.region || "";
  els.skipCredentialsValidation.checked = Boolean(settings.skip_credentials_validation);
  els.skipMetadataApiCheck.checked = Boolean(settings.skip_metadata_api_check);
  els.skipRequestingAccountId.checked = Boolean(settings.skip_requesting_account_id);
  els.usePathStyle.checked = Boolean(settings.use_path_style);
  applyBackendVisibility();
  hydrating = false;
}

function renderStatus(status) {
  if (!status) return;
  if (status.external_change) {
    els.driftMessage.textContent =
      "state.tfvars changed on disk outside the app.";
    els.driftBanner.style.display = "flex";
  } else {
    els.driftBanner.style.display = "none";
  }
}

function renderBackend(text) {
  els.backendPreview.textContent = text || "";
}

async function refreshBackend() {
  try {
    const data = await api("/api/terraform/backend");
    renderBackend(data.backend);
  } catch (err) {
    /* non-fatal */
  }
}

function buildPayload() {
  return {
    backend: currentBackend(),
    minio: els.minio.value,
    bucket: els.bucket.value.trim(),
    region: els.region.value.trim(),
    skip_credentials_validation: els.skipCredentialsValidation.checked,
    skip_metadata_api_check: els.skipMetadataApiCheck.checked,
    skip_requesting_account_id: els.skipRequestingAccountId.checked,
    use_path_style: els.usePathStyle.checked,
  };
}

async function autosave() {
  if (hydrating) return;
  try {
    setSaveState("saving");
    const updated = await api("/api/terraform/settings", {
      method: "PUT",
      body: JSON.stringify(buildPayload()),
    });
    renderSettings(updated);
    setSaveState("saved");
    refreshBackend();
  } catch (err) {
    setSaveState("error", err.message);
  }
}

const autosaveDebounced = debounce(autosave, 450);

[els.bucket, els.region].forEach((el) =>
  el.addEventListener("input", () => {
    if (!hydrating) autosaveDebounced();
  })
);
[
  els.backendLocal,
  els.backendS3,
  els.minio,
  els.skipCredentialsValidation,
  els.skipMetadataApiCheck,
  els.skipRequestingAccountId,
  els.usePathStyle,
].forEach((el) =>
  el.addEventListener("change", () => {
    if (hydrating) return;
    applyBackendVisibility();
    autosave();
  })
);

// Never let an accidental Enter submit/reload the page; edits auto-save.
els.form.addEventListener("submit", (event) => {
  event.preventDefault();
  autosave();
});

async function doReload() {
  try {
    const data = await api("/api/terraform/reload", { method: "POST" });
    renderMinioOptions(data.minios, data.settings ? data.settings.minio : "");
    renderSettings(data.settings);
    renderStatus(data.status);
    refreshBackend();
    toast("Reloaded from disk", "success");
  } catch (err) {
    toast(err.message, "error");
  }
}

els.reloadBtn.addEventListener("click", doReload);
els.driftReload.addEventListener("click", doReload);

els.previewBtn.addEventListener("click", async () => {
  await refreshBackend();
  els.previewModal.style.display = "flex";
});
els.previewCopy.addEventListener("click", async () => {
  try {
    await navigator.clipboard.writeText(els.backendPreview.textContent || "");
    toast("Copied minio.backend.hcl to clipboard", "success");
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

socket.on("terraform:settings", (payload) => {
  if (!payload) return;
  renderMinioOptions(payload.minios, payload.settings ? payload.settings.minio : "");
  renderSettings(payload.settings);
  refreshBackend();
});
socket.on("terraform:status", renderStatus);

// Keep the MinIO dropdown current when the catalog changes elsewhere.
socket.on("minio:instances", (instances) => {
  const names = (instances || []).map((inst) => inst.name);
  renderMinioOptions(names, els.minio.value);
  refreshBackend();
});

async function init() {
  setSaveState("idle");
  try {
    const data = await api("/api/terraform/settings");
    renderMinioOptions(data.minios, data.settings ? data.settings.minio : "");
    renderSettings(data.settings);
    renderStatus(data.status);
    refreshBackend();
  } catch (err) {
    toast(err.message, "error");
  }
}

init();
