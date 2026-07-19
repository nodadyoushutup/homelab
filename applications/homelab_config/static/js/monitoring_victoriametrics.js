"use strict";

const socket = io();
const API = "/api/monitoring/victoriametrics";

let settings = { docker_machine: "", dns_nameservers: [], placement: null };

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
  return el && (el.matches("input") || el.matches("textarea"));
}

// --- row builders ----------------------------------------------------------

function textRow(container, value, placeholder, attr) {
  const row = document.createElement("div");
  row.className = "flex items-center gap-2";
  row.innerHTML = `
    <input ${attr} value="${escapeHtml(value || "")}" placeholder="${escapeHtml(placeholder)}" class="mon-input font-mono text-xs" />
    <button type="button" data-remove class="rounded-md px-2 py-2 text-slate-400 hover:text-rose-300"><i class="fa-solid fa-xmark"></i></button>`;
  container.appendChild(row);
}

function platformRow(os, arch) {
  const tr = document.createElement("tr");
  tr.innerHTML = `
    <td class="px-2 py-1"><input data-pf-os value="${escapeHtml(os || "")}" placeholder="linux" class="w-full rounded border border-slate-700 bg-slate-950 px-2 py-1 text-slate-100" /></td>
    <td class="px-2 py-1"><input data-pf-arch value="${escapeHtml(arch || "")}" placeholder="aarch64" class="w-full rounded border border-slate-700 bg-slate-950 px-2 py-1 text-slate-100" /></td>
    <td class="px-2 py-1 text-right"><button type="button" data-remove class="rounded px-2 py-1 text-slate-400 hover:text-rose-300"><i class="fa-solid fa-xmark"></i></button></td>`;
  $("platform-rows").appendChild(tr);
}

function render() {
  if (isEditing()) return;
  $("docker_machine").value = settings.docker_machine || "";
  $("dns-list").innerHTML = "";
  (settings.dns_nameservers || []).forEach((ns) => textRow($("dns-list"), ns, "192.168.1.1", "data-dns"));
  const p = settings.placement;
  $("placement-enabled").checked = Boolean(p);
  $("placement-body").style.display = p ? "block" : "none";
  $("constraint-list").innerHTML = "";
  ((p && p.constraints) || []).forEach((c) => textRow($("constraint-list"), c, "node.labels.role==swarm-wk-0", "data-constraint"));
  $("platform-rows").innerHTML = "";
  ((p && p.platforms) || []).forEach((pf) => platformRow(pf.os, pf.architecture));
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

// --- collect + save ---------------------------------------------------------

function collect() {
  const dns = [];
  $("dns-list").querySelectorAll("[data-dns]").forEach((el) => {
    if (el.value.trim()) dns.push(el.value.trim());
  });
  let placement = null;
  if ($("placement-enabled").checked) {
    const constraints = [];
    $("constraint-list").querySelectorAll("[data-constraint]").forEach((el) => {
      if (el.value.trim()) constraints.push(el.value.trim());
    });
    const platforms = [];
    $("platform-rows").querySelectorAll("tr").forEach((tr) => {
      const os = tr.querySelector("[data-pf-os]").value.trim();
      const arch = tr.querySelector("[data-pf-arch]").value.trim();
      if (os || arch) platforms.push({ os, architecture: arch });
    });
    placement = { constraints, platforms };
  }
  return {
    docker_machine: $("docker_machine").value.trim(),
    dns_nameservers: dns,
    placement,
  };
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

// --- wiring -----------------------------------------------------------------

$("docker_machine").addEventListener("input", saveDebounced);

$("dns-add").addEventListener("click", () => {
  textRow($("dns-list"), "", "192.168.1.1", "data-dns");
});
$("dns-list").addEventListener("input", (e) => {
  if (e.target.matches("[data-dns]")) saveDebounced();
});
$("dns-list").addEventListener("click", (e) => {
  if (e.target.closest("[data-remove]")) {
    e.target.closest("div.flex").remove();
    save();
  }
});

$("placement-enabled").addEventListener("change", () => {
  $("placement-body").style.display = $("placement-enabled").checked ? "block" : "none";
  save();
});
$("constraint-add").addEventListener("click", () => {
  textRow($("constraint-list"), "", "node.labels.role==swarm-wk-0", "data-constraint");
});
$("constraint-list").addEventListener("input", (e) => {
  if (e.target.matches("[data-constraint]")) saveDebounced();
});
$("constraint-list").addEventListener("click", (e) => {
  if (e.target.closest("[data-remove]")) {
    e.target.closest("div.flex").remove();
    save();
  }
});
$("platform-add").addEventListener("click", () => platformRow("", ""));
$("platform-rows").addEventListener("input", (e) => {
  if (e.target.matches("[data-pf-os]") || e.target.matches("[data-pf-arch]")) saveDebounced();
});
$("platform-rows").addEventListener("click", (e) => {
  if (e.target.closest("[data-remove]")) {
    e.target.closest("tr").remove();
    save();
  }
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
    toast("Copied app.tfvars to clipboard", "success");
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

socket.on("victoriametrics_config:config", (payload) => {
  settings = payload || settings;
  render();
  refreshTfvars();
});
socket.on("victoriametrics_config:status", renderStatus);

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
