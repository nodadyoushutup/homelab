"use strict";

const socket = io();

const els = {
  form: document.getElementById("talos-form"),
  clusterName: document.getElementById("f-cluster-name"),
  clusterEndpoint: document.getElementById("f-cluster-endpoint"),
  endpoint: document.getElementById("f-endpoint"),
  bootstrapNode: document.getElementById("f-bootstrap-node"),
  talosVersion: document.getElementById("f-talos-version"),
  kubernetesVersion: document.getElementById("f-kubernetes-version"),
  kubeconfigRenewal: document.getElementById("f-kubeconfig-renewal"),
  nodeRows: document.getElementById("node-rows"),
  clientEndpoints: document.getElementById("f-client-endpoints"),
  talosconfigOutput: document.getElementById("f-talosconfig-output"),
  kubeconfigOutput: document.getElementById("f-kubeconfig-output"),
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
// Fixed node roster (name + role), learned from the first config payload.
let nodeOrder = [];

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

function roleBadge(role) {
  const isCp = role === "controlplane";
  const cls = isCp
    ? "bg-sky-500/15 text-sky-300"
    : "bg-slate-700/50 text-slate-300";
  return `<span class="ml-2 rounded px-1.5 py-0.5 text-[10px] font-medium uppercase ${cls}">${escapeHtml(
    role
  )}</span>`;
}

function renderNodes(nodes) {
  nodeOrder = nodes.map((n) => ({ name: n.name, role: n.role }));
  els.nodeRows.innerHTML = "";
  nodes.forEach((node) => {
    const row = document.createElement("tr");
    row.className = "align-top hover:bg-slate-800/40";
    row.dataset.nodeName = node.name;
    row.innerHTML = `
      <td class="px-4 py-3 whitespace-nowrap">
        <span class="font-medium text-slate-100">${escapeHtml(node.name)}</span>
        ${roleBadge(node.role)}
      </td>
      <td class="px-4 py-3">
        <input
          class="node-ip w-full rounded-lg border border-slate-700 bg-slate-950 px-3 py-2 font-mono text-xs text-slate-100 focus:border-sky-500 focus:outline-none"
          placeholder="10.0.0.x"
          value="${escapeHtml(node.node || "")}"
        />
      </td>
      <td class="px-4 py-3">
        <textarea
          rows="2"
          class="node-patches w-full rounded-lg border border-slate-700 bg-slate-950 px-3 py-2 font-mono text-xs text-slate-100 focus:border-sky-500 focus:outline-none"
          placeholder="path/to/patch.yaml (one per line)"
        >${escapeHtml((node.config_patch_paths || []).join("\n"))}</textarea>
      </td>`;
    els.nodeRows.appendChild(row);
  });

  els.nodeRows.querySelectorAll(".node-ip, .node-patches").forEach((el) =>
    el.addEventListener("input", () => {
      if (!hydrating) autosaveDebounced();
    })
  );
}

function linesToList(text) {
  return String(text || "")
    .split("\n")
    .map((line) => line.trim())
    .filter(Boolean);
}

function renderConfig(config) {
  if (!config) return;
  hydrating = true;
  const c = config.cluster || {};
  els.clusterName.value = c.cluster_name || "";
  els.clusterEndpoint.value = c.cluster_endpoint || "";
  els.endpoint.value = c.endpoint || "";
  els.bootstrapNode.value = c.bootstrap_node || "";
  els.talosVersion.value = c.talos_version || "";
  els.kubernetesVersion.value = c.kubernetes_version || "";
  els.kubeconfigRenewal.value = c.kubeconfig_renewal || "";
  renderNodes(config.nodes || []);
  els.clientEndpoints.value = (config.client_endpoints || []).join("\n");
  els.talosconfigOutput.value = config.talosconfig_output_path || "";
  els.kubeconfigOutput.value = config.kubeconfig_output_path || "";
  hydrating = false;
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
    const data = await api("/api/talos/tfvars");
    renderTfvars(data.tfvars);
  } catch (err) {
    /* non-fatal */
  }
}

function collectNodes() {
  const rows = els.nodeRows.querySelectorAll("tr[data-node-name]");
  return Array.from(rows).map((row) => ({
    name: row.dataset.nodeName,
    node: row.querySelector(".node-ip").value.trim(),
    config_patch_paths: linesToList(row.querySelector(".node-patches").value),
  }));
}

function buildPayload() {
  return {
    cluster: {
      cluster_name: els.clusterName.value.trim(),
      cluster_endpoint: els.clusterEndpoint.value.trim(),
      endpoint: els.endpoint.value.trim(),
      bootstrap_node: els.bootstrapNode.value.trim(),
      talos_version: els.talosVersion.value.trim(),
      kubernetes_version: els.kubernetesVersion.value.trim(),
      kubeconfig_renewal: els.kubeconfigRenewal.value.trim(),
    },
    nodes: collectNodes(),
    client_endpoints: linesToList(els.clientEndpoints.value),
    talosconfig_output_path: els.talosconfigOutput.value.trim(),
    kubeconfig_output_path: els.kubeconfigOutput.value.trim(),
  };
}

async function autosave() {
  if (hydrating) return;
  try {
    setSaveState("saving");
    await api("/api/talos/config", {
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

// Cluster + output text inputs autosave (debounced) as you type.
[
  els.clusterName,
  els.clusterEndpoint,
  els.endpoint,
  els.bootstrapNode,
  els.talosVersion,
  els.kubernetesVersion,
  els.kubeconfigRenewal,
  els.clientEndpoints,
  els.talosconfigOutput,
  els.kubeconfigOutput,
].forEach((el) =>
  el.addEventListener("input", () => {
    if (!hydrating) autosaveDebounced();
  })
);

// Never let an accidental Enter submit/reload the page; edits auto-save.
els.form.addEventListener("submit", (event) => {
  event.preventDefault();
  autosave();
});

async function doReload() {
  try {
    const data = await api("/api/talos/reload", { method: "POST" });
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

socket.on("talos:config", (config) => {
  renderConfig(config);
  refreshTfvars();
});
socket.on("talos:status", renderStatus);

async function init() {
  setSaveState("idle");
  try {
    const data = await api("/api/talos/config");
    renderConfig(data.config);
    renderStatus(data.status);
    refreshTfvars();
  } catch (err) {
    toast(err.message, "error");
  }
}

init();
