"use strict";

const socket = io();
const API = "/api/network/fortigate";

const els = {
  vipRows: document.getElementById("vip-rows"),
  vipEmpty: document.getElementById("vip-empty"),
  policyRows: document.getElementById("policy-rows"),
  policyEmpty: document.getElementById("policy-empty"),
  dhcpRows: document.getElementById("dhcp-rows"),
  dhcpEmpty: document.getElementById("dhcp-empty"),
  countVip: document.getElementById("count-vip"),
  countPolicy: document.getElementById("count-policy"),
  countDhcp: document.getElementById("count-dhcp"),
  tfvars: document.getElementById("tfvars-preview"),
  saveState: document.getElementById("save-state"),
  driftBanner: document.getElementById("drift-banner"),
  driftReload: document.getElementById("drift-reload"),
  reloadBtn: document.getElementById("reload-btn"),
  previewBtn: document.getElementById("preview-btn"),
  previewModal: document.getElementById("modal-preview"),
  previewCopy: document.getElementById("preview-copy"),
  // vip modal
  vipModal: document.getElementById("modal-vip"),
  vipForm: document.getElementById("vip-form"),
  vipTitle: document.getElementById("vip-title"),
  // policy modal
  policyModal: document.getElementById("modal-policy"),
  policyForm: document.getElementById("policy-form"),
  policyTitle: document.getElementById("policy-title"),
  // dhcp modal
  dhcpModal: document.getElementById("modal-dhcp"),
  dhcpForm: document.getElementById("dhcp-form"),
  dhcpTitle: document.getElementById("dhcp-title"),
  dhcpAddrRows: document.getElementById("dhcp-addr-rows"),
  dhcpAddRow: document.getElementById("dhcp-add-row"),
};

let currentConfig = {
  virtual_ips: [],
  firewall_policies: [],
  dhcp_server_reservations: [],
};

function $(id) {
  return document.getElementById(id);
}

let saveStateTimer;
function setSaveState(kind, message) {
  clearTimeout(saveStateTimer);
  if (kind === "saving") {
    els.saveState.innerHTML = '<i class="fa-solid fa-circle-notch fa-spin"></i>';
    els.saveState.className = "text-sm text-sky-300";
  } else if (kind === "saved") {
    els.saveState.innerHTML = '<i class="fa-solid fa-cloud-arrow-up"></i>';
    els.saveState.className = "text-sm text-emerald-300";
    saveStateTimer = setTimeout(() => setSaveState("idle"), 1000);
  } else if (kind === "error") {
    els.saveState.innerHTML = `<i class="fa-solid fa-triangle-exclamation mr-1 text-rose-400"></i>${escapeHtml(
      message || "Save failed"
    )}`;
    els.saveState.className = "text-xs font-medium text-rose-300";
  } else {
    els.saveState.innerHTML = '<i class="fa-solid fa-cloud"></i>';
    els.saveState.className = "text-sm text-slate-500";
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

function names(list) {
  return (list || []).join(", ");
}

function statusBadge(status) {
  const enabled = status === "enable";
  return `<span class="rounded-full px-2 py-0.5 text-xs font-medium ${
    enabled
      ? "bg-emerald-500/15 text-emerald-300"
      : "bg-slate-700/50 text-slate-400"
  }">${escapeHtml(status)}</span>`;
}

function actionButtons(collection, key) {
  return `
    <button data-edit-collection="${collection}" data-key="${escapeHtml(key)}" class="mr-1 rounded-md px-2 py-1 text-slate-400 hover:bg-slate-700 hover:text-sky-300" title="Edit">
      <i class="fa-solid fa-pen"></i>
    </button>
    <button data-del-collection="${collection}" data-key="${escapeHtml(key)}" class="rounded-md px-2 py-1 text-slate-400 hover:bg-slate-700 hover:text-rose-300" title="Delete">
      <i class="fa-solid fa-trash"></i>
    </button>`;
}

function renderVips(vips) {
  els.countVip.textContent = vips.length ? `(${vips.length})` : "";
  els.vipRows.innerHTML = "";
  els.vipEmpty.hidden = vips.length > 0;
  vips.forEach((vip) => {
    const importBadge = vip.import_existing
      ? ' <span class="rounded-full bg-sky-500/15 px-1.5 py-0.5 text-[10px] font-medium text-sky-300">import</span>'
      : "";
    const row = document.createElement("tr");
    row.className = "hover:bg-slate-800/40";
    row.innerHTML = `
      <td class="px-4 py-3 font-medium text-slate-100">${escapeHtml(vip.name)}${importBadge}</td>
      <td class="px-4 py-3 font-mono text-xs text-slate-400">${escapeHtml(vip.protocol)} ${escapeHtml(vip.extport)} &rarr; ${escapeHtml(vip.mappedport)}</td>
      <td class="px-4 py-3 font-mono text-xs text-slate-400">${escapeHtml(names(vip.mappedip))}</td>
      <td class="px-4 py-3">${statusBadge(vip.status)}</td>
      <td class="px-4 py-3 text-right whitespace-nowrap">${actionButtons("virtual_ips", vip.name)}</td>`;
    els.vipRows.appendChild(row);
  });
}

function renderPolicies(policies) {
  els.countPolicy.textContent = policies.length ? `(${policies.length})` : "";
  els.policyRows.innerHTML = "";
  els.policyEmpty.hidden = policies.length > 0;
  policies.forEach((p) => {
    const importBadge = p.import_existing
      ? ' <span class="rounded-full bg-sky-500/15 px-1.5 py-0.5 text-[10px] font-medium text-sky-300">import</span>'
      : "";
    const src = [names(p.srcintf), names(p.srcaddr)].filter(Boolean).join(" / ");
    const dst = [names(p.dstintf), names(p.dstaddr)].filter(Boolean).join(" / ");
    const row = document.createElement("tr");
    row.className = "hover:bg-slate-800/40";
    row.innerHTML = `
      <td class="px-4 py-3 font-mono text-xs text-slate-400">${escapeHtml(p.policyid)}</td>
      <td class="px-4 py-3 font-medium text-slate-100">${escapeHtml(p.name)}${importBadge}</td>
      <td class="px-4 py-3 text-xs text-slate-400">${escapeHtml(src)} &rarr; ${escapeHtml(dst)}</td>
      <td class="px-4 py-3 text-xs text-slate-400">${escapeHtml(p.action)}</td>
      <td class="px-4 py-3 text-right whitespace-nowrap">${actionButtons("firewall_policies", p.policyid)}</td>`;
    els.policyRows.appendChild(row);
  });
}

function renderReservations(reservations) {
  els.countDhcp.textContent = reservations.length ? `(${reservations.length})` : "";
  els.dhcpRows.innerHTML = "";
  els.dhcpEmpty.hidden = reservations.length > 0;
  reservations.forEach((res) => {
    const addrs = res.reserved_address || [];
    const summary = addrs
      .slice(0, 3)
      .map((a) => `${escapeHtml(a.ip)} (${escapeHtml(a.description || a.mac)})`)
      .join(", ");
    const more = addrs.length > 3 ? ` +${addrs.length - 3} more` : "";
    const row = document.createElement("tr");
    row.className = "hover:bg-slate-800/40";
    row.innerHTML = `
      <td class="px-4 py-3 font-mono text-xs text-slate-400">${escapeHtml(res.fosid)}</td>
      <td class="px-4 py-3 text-xs text-slate-400">${escapeHtml(res.method)}</td>
      <td class="px-4 py-3 text-xs text-slate-400"><span class="font-medium text-slate-300">${addrs.length}</span> · ${summary}${more}</td>
      <td class="px-4 py-3 text-right whitespace-nowrap">${actionButtons("dhcp_server_reservations", res.fosid)}</td>`;
    els.dhcpRows.appendChild(row);
  });
}

function renderConfig(config) {
  currentConfig = config || currentConfig;
  renderVips(currentConfig.virtual_ips || []);
  renderPolicies(currentConfig.firewall_policies || []);
  renderReservations(currentConfig.dhcp_server_reservations || []);
}

function renderStatus(status) {
  if (!status) return;
  els.driftBanner.style.display = status.external_change ? "flex" : "none";
}

function renderTfvars(text) {
  els.tfvars.textContent = text || "";
}

async function refreshTfvars() {
  try {
    const data = await api(`${API}/tfvars`);
    renderTfvars(data.tfvars);
  } catch (err) {
    /* non-fatal */
  }
}

function openModal(modal) {
  modal.style.display = "flex";
}
function closeModal(modal) {
  modal.style.display = "none";
}

// --- Virtual IP modal ------------------------------------------------------

function openVip(vip) {
  $("vip-orig").value = vip ? vip.name : "";
  $("vip-name").value = vip ? vip.name : "";
  $("vip-type").value = vip ? vip.type : "static-nat";
  $("vip-extintf").value = vip ? vip.extintf : "wan";
  $("vip-extip").value = vip ? vip.extip : "0.0.0.0";
  $("vip-protocol").value = vip ? vip.protocol : "tcp";
  $("vip-extport").value = vip ? vip.extport : "";
  $("vip-mappedport").value = vip ? vip.mappedport : "";
  $("vip-mappedip").value = vip ? names(vip.mappedip) : "";
  $("vip-status").value = vip ? vip.status : "enable";
  $("vip-portforward").value = vip ? vip.portforward : "enable";
  $("vip-import").checked = vip ? Boolean(vip.import_existing) : false;
  els.vipTitle.textContent = vip ? `Edit ${vip.name}` : "Add virtual IP";
  openModal(els.vipModal);
}

function vipPayload() {
  return {
    name: $("vip-name").value.trim(),
    type: $("vip-type").value.trim(),
    extintf: $("vip-extintf").value.trim(),
    extip: $("vip-extip").value.trim(),
    protocol: $("vip-protocol").value.trim(),
    extport: $("vip-extport").value.trim(),
    mappedport: $("vip-mappedport").value.trim(),
    mappedip: $("vip-mappedip").value.trim(),
    status: $("vip-status").value,
    portforward: $("vip-portforward").value,
    import_existing: $("vip-import").checked,
  };
}

els.vipForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  const orig = $("vip-orig").value;
  const payload = vipPayload();
  await saveEntry("virtual_ips", orig, payload, els.vipModal, payload.name);
});

// --- Firewall policy modal -------------------------------------------------

function openPolicy(p) {
  $("policy-orig").value = p ? p.policyid : "";
  $("policy-id").value = p ? p.policyid : "";
  $("policy-name").value = p ? p.name : "";
  $("policy-action").value = p ? p.action : "accept";
  $("policy-status").value = p ? p.status : "enable";
  $("policy-schedule").value = p ? p.schedule : "always";
  $("policy-nat").value = p ? p.nat : "disable";
  $("policy-logtraffic").value = p ? p.logtraffic : "all";
  $("policy-match_vip").value = p ? p.match_vip : "enable";
  $("policy-srcintf").value = p ? names(p.srcintf) : "wan";
  $("policy-dstintf").value = p ? names(p.dstintf) : "lan";
  $("policy-srcaddr").value = p ? names(p.srcaddr) : "all";
  $("policy-dstaddr").value = p ? names(p.dstaddr) : "";
  $("policy-service").value = p ? names(p.service) : "ALL";
  $("policy-import").checked = p ? Boolean(p.import_existing) : false;
  els.policyTitle.textContent = p ? `Edit policy ${p.policyid}` : "Add firewall policy";
  openModal(els.policyModal);
}

function policyPayload() {
  return {
    policyid: $("policy-id").value.trim(),
    name: $("policy-name").value.trim(),
    action: $("policy-action").value.trim(),
    status: $("policy-status").value,
    schedule: $("policy-schedule").value.trim(),
    nat: $("policy-nat").value.trim(),
    logtraffic: $("policy-logtraffic").value.trim(),
    match_vip: $("policy-match_vip").value.trim(),
    srcintf: $("policy-srcintf").value.trim(),
    dstintf: $("policy-dstintf").value.trim(),
    srcaddr: $("policy-srcaddr").value.trim(),
    dstaddr: $("policy-dstaddr").value.trim(),
    service: $("policy-service").value.trim(),
    import_existing: $("policy-import").checked,
  };
}

els.policyForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  const orig = $("policy-orig").value;
  const payload = policyPayload();
  await saveEntry("firewall_policies", orig, payload, els.policyModal, payload.policyid);
});

// --- DHCP reservation modal ------------------------------------------------

function addAddrRow(addr) {
  const tr = document.createElement("tr");
  tr.dataset.type = addr && addr.type ? addr.type : "mac";
  tr.dataset.action = addr && addr.action ? addr.action : "reserved";
  tr.innerHTML = `
    <td class="px-2 py-1"><input data-f="id" type="number" value="${escapeHtml(addr ? addr.id : "")}" class="w-16 rounded border border-slate-700 bg-slate-950 px-2 py-1 text-slate-100" /></td>
    <td class="px-2 py-1"><input data-f="ip" value="${escapeHtml(addr ? addr.ip : "")}" placeholder="192.168.1.200" class="w-full rounded border border-slate-700 bg-slate-950 px-2 py-1 font-mono text-slate-100" /></td>
    <td class="px-2 py-1"><input data-f="mac" value="${escapeHtml(addr ? addr.mac : "")}" placeholder="0a:00:00:00:12:00" class="w-full rounded border border-slate-700 bg-slate-950 px-2 py-1 font-mono text-slate-100" /></td>
    <td class="px-2 py-1"><input data-f="description" value="${escapeHtml(addr ? addr.description : "")}" placeholder="talos-cp-0" class="w-full rounded border border-slate-700 bg-slate-950 px-2 py-1 text-slate-100" /></td>
    <td class="px-2 py-1 text-right"><button type="button" data-remove-row class="rounded px-2 py-1 text-slate-400 hover:text-rose-300"><i class="fa-solid fa-xmark"></i></button></td>`;
  els.dhcpAddrRows.appendChild(tr);
}

function openDhcp(res) {
  $("dhcp-orig").value = res ? res.fosid : "";
  $("dhcp-fosid").value = res ? res.fosid : "";
  $("dhcp-method").value = res ? res.method : "PUT";
  els.dhcpAddrRows.innerHTML = "";
  const addrs = (res && res.reserved_address) || [];
  if (addrs.length) {
    addrs.forEach((a) => addAddrRow(a));
  } else {
    addAddrRow(null);
  }
  els.dhcpTitle.textContent = res ? `Edit reservation ${res.fosid}` : "Add reservation group";
  openModal(els.dhcpModal);
}

els.dhcpAddRow.addEventListener("click", () => addAddrRow(null));
els.dhcpAddrRows.addEventListener("click", (event) => {
  const btn = event.target.closest("[data-remove-row]");
  if (btn) btn.closest("tr").remove();
});

function dhcpPayload() {
  const reserved = [];
  els.dhcpAddrRows.querySelectorAll("tr").forEach((tr) => {
    const get = (f) => tr.querySelector(`[data-f="${f}"]`).value.trim();
    const id = get("id");
    const ip = get("ip");
    const mac = get("mac");
    if (!id && !ip && !mac) return;
    reserved.push({
      id: id,
      type: tr.dataset.type || "mac",
      ip: ip,
      mac: mac,
      action: tr.dataset.action || "reserved",
      description: get("description"),
    });
  });
  return {
    fosid: $("dhcp-fosid").value.trim(),
    method: $("dhcp-method").value.trim(),
    reserved_address: reserved,
  };
}

els.dhcpForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  const orig = $("dhcp-orig").value;
  const payload = dhcpPayload();
  await saveEntry(
    "dhcp_server_reservations",
    orig,
    payload,
    els.dhcpModal,
    payload.fosid
  );
});

// --- shared save -----------------------------------------------------------

async function saveEntry(collection, origKey, payload, modal, newKey) {
  try {
    setSaveState("saving");
    if (origKey) {
      await api(`${API}/${collection}/${encodeURIComponent(origKey)}`, {
        method: "PUT",
        body: JSON.stringify(payload),
      });
      toast(`Saved ${newKey}`, "success");
    } else {
      await api(`${API}/${collection}`, {
        method: "POST",
        body: JSON.stringify(payload),
      });
      toast(`Added ${newKey}`, "success");
    }
    setSaveState("saved");
    closeModal(modal);
    refreshTfvars();
  } catch (err) {
    setSaveState("error", err.message);
    toast(err.message, "error");
  }
}

// --- table + modal wiring --------------------------------------------------

const OPENERS = {
  virtual_ips: (entry) => openVip(entry),
  firewall_policies: (entry) => openPolicy(entry),
  dhcp_server_reservations: (entry) => openDhcp(entry),
};

function findEntry(collection, key) {
  const keyField = {
    virtual_ips: "name",
    firewall_policies: "policyid",
    dhcp_server_reservations: "fosid",
  }[collection];
  return (currentConfig[collection] || []).find(
    (e) => String(e[keyField]) === String(key)
  );
}

document.querySelectorAll("[data-add]").forEach((btn) => {
  btn.addEventListener("click", () => OPENERS[btn.dataset.add](null));
});

document.querySelectorAll("[data-close]").forEach((btn) => {
  btn.addEventListener("click", () => {
    const modal = btn.closest(".fixed");
    if (modal) closeModal(modal);
  });
});

[els.vipModal, els.policyModal, els.dhcpModal, els.previewModal].forEach((modal) => {
  modal.addEventListener("click", (event) => {
    if (event.target === modal) closeModal(modal);
  });
});

function onTableClick(event) {
  const editBtn = event.target.closest("[data-edit-collection]");
  if (editBtn) {
    const collection = editBtn.dataset.editCollection;
    const entry = findEntry(collection, editBtn.dataset.key);
    if (entry) OPENERS[collection](entry);
    return;
  }
  const delBtn = event.target.closest("[data-del-collection]");
  if (delBtn) {
    const collection = delBtn.dataset.delCollection;
    const key = delBtn.dataset.key;
    if (!confirm(`Delete ${collection} entry "${key}"?`)) return;
    api(`${API}/${collection}/${encodeURIComponent(key)}`, { method: "DELETE" })
      .then(() => {
        toast(`Deleted ${key}`, "success");
        refreshTfvars();
      })
      .catch((err) => toast(err.message, "error"));
  }
}

els.vipRows.addEventListener("click", onTableClick);
els.policyRows.addEventListener("click", onTableClick);
els.dhcpRows.addEventListener("click", onTableClick);

// --- reload / preview ------------------------------------------------------

async function doReload() {
  try {
    const data = await api(`${API}/reload`, { method: "POST" });
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
  openModal(els.previewModal);
});
els.previewCopy.addEventListener("click", async () => {
  try {
    await navigator.clipboard.writeText(els.tfvars.textContent || "");
    toast("Copied config.tfvars to clipboard", "success");
  } catch (err) {
    toast("Could not copy to clipboard", "error");
  }
});

document.addEventListener("keydown", (event) => {
  if (event.key === "Escape") {
    [els.vipModal, els.policyModal, els.dhcpModal, els.previewModal].forEach(
      (m) => closeModal(m)
    );
  }
});

socket.on("fortigate_config:config", (config) => {
  renderConfig(config);
  refreshTfvars();
});
socket.on("fortigate_config:status", renderStatus);

async function init() {
  setSaveState("idle");
  try {
    const data = await api(`${API}/config`);
    renderConfig(data.config);
    renderStatus(data.status);
    refreshTfvars();
  } catch (err) {
    toast(err.message, "error");
  }
}

init();
