"use strict";

const socket = io();

const els = {
  form: document.getElementById("cir-form"),
  dockerMachine: document.getElementById("f-docker-machine"),
  dockerMachines: document.getElementById("docker-machines"),
  dnsNameservers: document.getElementById("f-dns-nameservers"),
  nfsShare: document.getElementById("f-nfs-share"),
  nfsShares: document.getElementById("nfs-shares"),
  nfsSubpath: document.getElementById("f-nfs-subpath"),
  constraints: document.getElementById("f-constraints"),
  platformRows: document.getElementById("platform-rows"),
  platformEmpty: document.getElementById("platform-empty"),
  addPlatform: document.getElementById("add-platform"),
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

// Suppress autosave while we programmatically populate the form.
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

function linesToList(text) {
  return String(text || "")
    .split("\n")
    .map((line) => line.trim())
    .filter(Boolean);
}

function fillDatalist(datalist, values) {
  datalist.innerHTML = "";
  values.forEach((value) => {
    const option = document.createElement("option");
    option.value = value;
    datalist.appendChild(option);
  });
}

// -- platform rows -----------------------------------------------------------

function updatePlatformEmpty() {
  const hasRows = els.platformRows.querySelector("tr") !== null;
  els.platformEmpty.style.display = hasRows ? "none" : "block";
}

function addPlatformRow(platform = { os: "", architecture: "" }) {
  const row = document.createElement("tr");
  row.className = "align-top";
  row.innerHTML = `
    <td class="py-2 pr-3">
      <input
        class="plat-os w-full rounded-lg border border-slate-700 bg-slate-950 px-3 py-2 font-mono text-xs text-slate-100 focus:border-sky-500 focus:outline-none"
        placeholder="linux"
        value="${escapeHtml(platform.os || "")}"
      />
    </td>
    <td class="py-2 pr-3">
      <input
        class="plat-arch w-full rounded-lg border border-slate-700 bg-slate-950 px-3 py-2 font-mono text-xs text-slate-100 focus:border-sky-500 focus:outline-none"
        placeholder="amd64"
        value="${escapeHtml(platform.architecture || "")}"
      />
    </td>
    <td class="py-2 text-right">
      <button
        type="button"
        class="plat-remove rounded-md px-2 py-1 text-slate-400 hover:bg-slate-800 hover:text-rose-300"
        title="Remove platform"
      >
        <i class="fa-solid fa-trash"></i>
      </button>
    </td>`;
  els.platformRows.appendChild(row);

  row.querySelectorAll(".plat-os, .plat-arch").forEach((el) =>
    el.addEventListener("input", () => {
      if (!hydrating) autosaveDebounced();
    })
  );
  row.querySelector(".plat-remove").addEventListener("click", () => {
    row.remove();
    updatePlatformEmpty();
    if (!hydrating) autosaveDebounced();
  });
  updatePlatformEmpty();
}

function renderPlatforms(platforms) {
  els.platformRows.innerHTML = "";
  (platforms || []).forEach((platform) => addPlatformRow(platform));
  updatePlatformEmpty();
}

function collectPlatforms() {
  const rows = els.platformRows.querySelectorAll("tr");
  return Array.from(rows)
    .map((row) => ({
      os: row.querySelector(".plat-os").value.trim(),
      architecture: row.querySelector(".plat-arch").value.trim(),
    }))
    .filter((p) => p.os || p.architecture);
}

// -- config <-> form ---------------------------------------------------------

function renderConfig(config) {
  if (!config) return;
  hydrating = true;
  els.dockerMachine.value = config.docker_machine || "";
  els.dnsNameservers.value = (config.dns_nameservers || []).join("\n");
  els.nfsShare.value = config.nfs_share || "";
  els.nfsSubpath.value = config.nfs_subpath || "";
  const placement = config.placement || {};
  els.constraints.value = (placement.constraints || []).join("\n");
  renderPlatforms(placement.platforms || []);
  hydrating = false;
}

function buildPayload() {
  return {
    docker_machine: els.dockerMachine.value.trim(),
    dns_nameservers: linesToList(els.dnsNameservers.value),
    placement: {
      constraints: linesToList(els.constraints.value),
      platforms: collectPlatforms(),
    },
    nfs_share: els.nfsShare.value.trim(),
    nfs_subpath: els.nfsSubpath.value.trim(),
  };
}

function renderStatus(status) {
  if (!status) return;
  if (status.external_change) {
    els.driftMessage.textContent = "app.tfvars changed on disk outside the app.";
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
    const data = await api("/api/cloud-image-repository/tfvars");
    renderTfvars(data.tfvars);
  } catch (err) {
    /* non-fatal */
  }
}

async function autosave() {
  if (hydrating) return;
  try {
    setSaveState("saving");
    await api("/api/cloud-image-repository/config", {
      method: "PUT",
      body: JSON.stringify(buildPayload()),
    });
    setSaveState("saved");
    refreshTfvars();
  } catch (err) {
    setSaveState("error", err.message);
  }
}

const autosaveDebounced = debounce(autosave, 450);

[
  els.dockerMachine,
  els.dnsNameservers,
  els.nfsShare,
  els.nfsSubpath,
  els.constraints,
].forEach((el) =>
  el.addEventListener("input", () => {
    if (!hydrating) autosaveDebounced();
  })
);

els.addPlatform.addEventListener("click", () => {
  addPlatformRow();
  if (!hydrating) autosaveDebounced();
});

// Never let an accidental Enter submit/reload the page; edits auto-save.
els.form.addEventListener("submit", (event) => {
  event.preventDefault();
  autosave();
});

async function doReload() {
  try {
    const data = await api("/api/cloud-image-repository/reload", {
      method: "POST",
    });
    renderConfig(data.config);
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
    toast("Copied app.tfvars to clipboard", "success");
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

// -- suggestion catalogs (docker machines + NFS shares) ----------------------

async function loadDockerMachines() {
  try {
    const data = await api("/api/docker/providers");
    const names = [];
    (data.derived || []).forEach((p) => p.name && names.push(p.name));
    (data.extra_hosts || []).forEach(
      (h) => (h.name || h.machine) && names.push(h.name || h.machine)
    );
    fillDatalist(els.dockerMachines, Array.from(new Set(names)).sort());
  } catch (err) {
    /* non-fatal: the field still accepts free text */
  }
}

async function loadNfsShares() {
  try {
    const data = await api("/api/nfs/shares");
    const names = (data.shares || []).map((s) => s.name).filter(Boolean);
    fillDatalist(els.nfsShares, names);
  } catch (err) {
    /* non-fatal: the field still accepts free text */
  }
}

socket.on("cloud_image_repository:config", (config) => {
  renderConfig(config);
  refreshTfvars();
});
socket.on("cloud_image_repository:status", renderStatus);
// Keep suggestions fresh when the docker/nfs catalogs change elsewhere.
socket.on("docker:providers", loadDockerMachines);
socket.on("nfs:shares", loadNfsShares);

async function init() {
  setSaveState("idle");
  loadDockerMachines();
  loadNfsShares();
  try {
    const data = await api("/api/cloud-image-repository/config");
    renderConfig(data.config);
    renderStatus(data.status);
    refreshTfvars();
  } catch (err) {
    toast(err.message, "error");
  }
}

init();
