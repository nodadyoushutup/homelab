"use strict";

const socket = io();
const API = "/api/network/npm";
const COLLECTIONS = [
  "certificates",
  "proxy_hosts",
  "redirections",
  "streams",
  "access_lists",
];

let currentConfig = {
  default: {},
  certificates: [],
  proxy_hosts: [],
  redirections: [],
  streams: [],
  access_lists: [],
};

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
    el.innerHTML = `<i class="fa-solid fa-triangle-exclamation mr-1 text-rose-400"></i>${escapeHtml(
      message || "Save failed"
    )}`;
    el.className = "text-xs font-medium text-rose-300";
  } else {
    el.innerHTML = '<i class="fa-solid fa-cloud"></i>';
    el.className = "text-sm text-slate-500";
  }
}

function escapeHtml(value) {
  return String(value ?? "").replace(
    /[&<>"']/g,
    (ch) =>
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

function domainsToText(list) {
  return (list || []).join("\n");
}

function badge(text, tone) {
  const tones = {
    on: "bg-emerald-500/15 text-emerald-300",
    off: "bg-slate-700/50 text-slate-400",
    info: "bg-sky-500/15 text-sky-300",
  };
  return `<span class="rounded-full px-2 py-0.5 text-xs font-medium ${tones[tone] || tones.off}">${escapeHtml(text)}</span>`;
}

function actionButtons(collection, key) {
  return `
    <button data-edit-collection="${collection}" data-key="${escapeHtml(key)}" class="mr-1 rounded-md px-2 py-1 text-slate-400 hover:bg-slate-700 hover:text-sky-300" title="Edit"><i class="fa-solid fa-pen"></i></button>
    <button data-del-collection="${collection}" data-key="${escapeHtml(key)}" class="rounded-md px-2 py-1 text-slate-400 hover:bg-slate-700 hover:text-rose-300" title="Delete"><i class="fa-solid fa-trash"></i></button>`;
}

// --- table rendering -------------------------------------------------------

function setCount(collection, n) {
  $(`count-${collection}`).textContent = n ? `(${n})` : "";
}

function renderRows(collection, html) {
  const list = currentConfig[collection] || [];
  setCount(collection, list.length);
  $(`${collection}-empty`).hidden = list.length > 0;
  $(`${collection}-rows`).innerHTML = html;
}

function renderProxyHosts() {
  const rows = (currentConfig.proxy_hosts || [])
    .map((h) => {
      const domains = (h.domain_names || []).join(", ");
      const cert = h.certificate ? badge(h.certificate, "info") : badge("none", "off");
      const ssl = h.ssl_forced ? badge("forced", "on") : badge("off", "off");
      const disabled = h.enabled ? "" : ` ${badge("disabled", "off")}`;
      return `<tr class="hover:bg-slate-800/40">
        <td class="px-4 py-3"><div class="font-medium text-slate-100">${escapeHtml(h.name)}${disabled}</div><div class="font-mono text-xs text-slate-500">${escapeHtml(domains)}</div></td>
        <td class="px-4 py-3 font-mono text-xs text-slate-400">${escapeHtml(h.forward_scheme)}://${escapeHtml(h.forward_host)}:${escapeHtml(h.forward_port)}</td>
        <td class="px-4 py-3">${cert}</td>
        <td class="px-4 py-3">${ssl}</td>
        <td class="px-4 py-3 text-right whitespace-nowrap">${actionButtons("proxy_hosts", h.name)}</td></tr>`;
    })
    .join("");
  renderRows("proxy_hosts", rows);
}

function renderCertificates() {
  const rows = (currentConfig.certificates || [])
    .map((c) => {
      const domains = (c.domain_names || []).join(", ");
      const dns = c.dns_challenge
        ? badge(c.dns_challenge.provider || "dns", "info")
        : badge("http", "off");
      return `<tr class="hover:bg-slate-800/40">
        <td class="px-4 py-3 font-medium text-slate-100">${escapeHtml(c.name)}</td>
        <td class="px-4 py-3 font-mono text-xs text-slate-400">${escapeHtml(domains)}</td>
        <td class="px-4 py-3">${dns}</td>
        <td class="px-4 py-3 text-right whitespace-nowrap">${actionButtons("certificates", c.name)}</td></tr>`;
    })
    .join("");
  renderRows("certificates", rows);
}

function renderRedirections() {
  const rows = (currentConfig.redirections || [])
    .map((r) => {
      const domains = (r.domain_names || []).join(", ");
      return `<tr class="hover:bg-slate-800/40">
        <td class="px-4 py-3"><div class="font-medium text-slate-100">${escapeHtml(r.name)}</div><div class="font-mono text-xs text-slate-500">${escapeHtml(domains)}</div></td>
        <td class="px-4 py-3 font-mono text-xs text-slate-400">${escapeHtml(r.forward_scheme)}://${escapeHtml(r.forward_domain_name)}</td>
        <td class="px-4 py-3 text-xs text-slate-400">${escapeHtml(r.forward_http_code)}</td>
        <td class="px-4 py-3 text-right whitespace-nowrap">${actionButtons("redirections", r.name)}</td></tr>`;
    })
    .join("");
  renderRows("redirections", rows);
}

function renderStreams() {
  const rows = (currentConfig.streams || [])
    .map((s) => {
      const proto = [s.tcp_forwarding ? "TCP" : "", s.udp_forwarding ? "UDP" : ""]
        .filter(Boolean)
        .join("/");
      return `<tr class="hover:bg-slate-800/40">
        <td class="px-4 py-3 font-medium text-slate-100">${escapeHtml(s.name)}</td>
        <td class="px-4 py-3 font-mono text-xs text-slate-400">${escapeHtml(s.incoming_port)} &rarr; ${escapeHtml(s.forwarding_host)}:${escapeHtml(s.forwarding_port)}</td>
        <td class="px-4 py-3 text-xs text-slate-400">${escapeHtml(proto)}</td>
        <td class="px-4 py-3 text-right whitespace-nowrap">${actionButtons("streams", s.name)}</td></tr>`;
    })
    .join("");
  renderRows("streams", rows);
}

function renderAccessLists() {
  const rows = (currentConfig.access_lists || [])
    .map((a) => {
      const users = (a.authorizations || []).map((u) => u.username).join(", ") || "—";
      const rules = (a.access || []).length;
      return `<tr class="hover:bg-slate-800/40">
        <td class="px-4 py-3 font-medium text-slate-100">${escapeHtml(a.name)}</td>
        <td class="px-4 py-3 text-xs text-slate-400">${escapeHtml(users)}</td>
        <td class="px-4 py-3 text-xs text-slate-400">${rules} rule(s)</td>
        <td class="px-4 py-3 text-right whitespace-nowrap">${actionButtons("access_lists", a.name)}</td></tr>`;
    })
    .join("");
  renderRows("access_lists", rows);
}

function renderDefault(def) {
  def = def || {};
  if (document.activeElement && document.activeElement.id.startsWith("def-")) return;
  $("def-email").value = def.certificate_email || "";
  const dns = def.dns_challenge || {};
  $("def-dns-enabled").checked = Boolean(dns.enabled);
  $("def-dns-provider").value = dns.provider || "";
  $("def-dns-prop").value = dns.propagation_seconds != null ? dns.propagation_seconds : "";
  $("def-dns-creds").value = dns.credentials || "";
}

function renderConfig(config) {
  currentConfig = config || currentConfig;
  renderDefault(currentConfig.default);
  renderProxyHosts();
  renderCertificates();
  renderRedirections();
  renderStreams();
  renderAccessLists();
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

function openModal(id) {
  $(id).style.display = "flex";
}
function closeModal(el) {
  el.style.display = "none";
}

function fillSelect(el, collection, current, emptyLabel) {
  const names = (currentConfig[collection] || []).map((e) => e.name);
  const options = [`<option value="">${escapeHtml(emptyLabel)}</option>`].concat(
    names.map(
      (n) =>
        `<option value="${escapeHtml(n)}"${n === current ? " selected" : ""}>${escapeHtml(n)}</option>`
    )
  );
  // Keep a current value even if it no longer matches a known entry.
  if (current && !names.includes(current)) {
    options.push(`<option value="${escapeHtml(current)}" selected>${escapeHtml(current)} (missing)</option>`);
  }
  el.innerHTML = options.join("");
}

// --- default settings (autosave) -------------------------------------------

function defaultPayload() {
  const payload = { certificate_email: $("def-email").value.trim() };
  const enabled = $("def-dns-enabled").checked;
  const provider = $("def-dns-provider").value.trim();
  const creds = $("def-dns-creds").value.trim();
  const prop = $("def-dns-prop").value.trim();
  if (enabled || provider || creds || prop) {
    payload.dns_challenge = {
      enabled,
      provider,
      credentials: creds,
      propagation_seconds: prop,
    };
  }
  return payload;
}

async function saveDefault() {
  try {
    setSaveState("saving");
    await api(`${API}/default`, {
      method: "PUT",
      body: JSON.stringify(defaultPayload()),
    });
    setSaveState("saved");
    refreshTfvars();
  } catch (err) {
    setSaveState("error", err.message);
  }
}
const saveDefaultDebounced = debounce(saveDefault, 600);
["def-email", "def-dns-provider", "def-dns-creds", "def-dns-prop"].forEach((id) =>
  $(id).addEventListener("input", saveDefaultDebounced)
);
$("def-dns-enabled").addEventListener("change", saveDefault);

// --- nested sub-tables ------------------------------------------------------

function addLocationRow(loc) {
  const tr = document.createElement("tr");
  tr.innerHTML = `
    <td class="px-2 py-1"><input data-f="path" value="${escapeHtml(loc ? loc.path : "")}" placeholder="/api" class="w-full rounded border border-slate-700 bg-slate-950 px-2 py-1 font-mono text-slate-100" /></td>
    <td class="px-2 py-1"><input data-f="forward_scheme" value="${escapeHtml(loc ? loc.forward_scheme : "http")}" class="w-20 rounded border border-slate-700 bg-slate-950 px-2 py-1 text-slate-100" /></td>
    <td class="px-2 py-1"><input data-f="forward_host" value="${escapeHtml(loc ? loc.forward_host : "")}" placeholder="10.0.0.1" class="w-full rounded border border-slate-700 bg-slate-950 px-2 py-1 font-mono text-slate-100" /></td>
    <td class="px-2 py-1"><input data-f="forward_port" type="number" value="${escapeHtml(loc ? loc.forward_port : "")}" class="w-20 rounded border border-slate-700 bg-slate-950 px-2 py-1 text-slate-100" /></td>
    <td class="px-2 py-1 text-right"><button type="button" data-remove-row class="rounded px-2 py-1 text-slate-400 hover:text-rose-300"><i class="fa-solid fa-xmark"></i></button></td>`;
  $("ph-loc-rows").appendChild(tr);
}

function addAuthRow(auth) {
  const tr = document.createElement("tr");
  tr.innerHTML = `
    <td class="px-2 py-1"><input data-f="username" value="${escapeHtml(auth ? auth.username : "")}" placeholder="user" class="w-full rounded border border-slate-700 bg-slate-950 px-2 py-1 text-slate-100" /></td>
    <td class="px-2 py-1"><input data-f="password" value="${escapeHtml(auth ? auth.password : "")}" placeholder="password" class="w-full rounded border border-slate-700 bg-slate-950 px-2 py-1 font-mono text-slate-100" /></td>
    <td class="px-2 py-1 text-right"><button type="button" data-remove-row class="rounded px-2 py-1 text-slate-400 hover:text-rose-300"><i class="fa-solid fa-xmark"></i></button></td>`;
  $("al-auth-rows").appendChild(tr);
}

function addAccessRow(rule) {
  const tr = document.createElement("tr");
  const dir = rule ? rule.directive : "allow";
  tr.innerHTML = `
    <td class="px-2 py-1"><select data-f="directive" class="rounded border border-slate-700 bg-slate-950 px-2 py-1 text-slate-100"><option value="allow"${dir === "allow" ? " selected" : ""}>allow</option><option value="deny"${dir === "deny" ? " selected" : ""}>deny</option></select></td>
    <td class="px-2 py-1"><input data-f="address" value="${escapeHtml(rule ? rule.address : "")}" placeholder="192.168.1.0/24" class="w-full rounded border border-slate-700 bg-slate-950 px-2 py-1 font-mono text-slate-100" /></td>
    <td class="px-2 py-1 text-right"><button type="button" data-remove-row class="rounded px-2 py-1 text-slate-400 hover:text-rose-300"><i class="fa-solid fa-xmark"></i></button></td>`;
  $("al-access-rows").appendChild(tr);
}

function collectRows(tbodyId, fields) {
  const out = [];
  $(tbodyId).querySelectorAll("tr").forEach((tr) => {
    const row = {};
    let any = false;
    fields.forEach((f) => {
      const el = tr.querySelector(`[data-f="${f}"]`);
      row[f] = el ? el.value.trim() : "";
      if (row[f]) any = true;
    });
    if (any) out.push(row);
  });
  return out;
}

$("ph-add-loc").addEventListener("click", () => addLocationRow(null));
$("al-add-auth").addEventListener("click", () => addAuthRow(null));
$("al-add-access").addEventListener("click", () => addAccessRow(null));
["ph-loc-rows", "al-auth-rows", "al-access-rows"].forEach((id) =>
  $(id).addEventListener("click", (e) => {
    const btn = e.target.closest("[data-remove-row]");
    if (btn) btn.closest("tr").remove();
  })
);

// --- openers ---------------------------------------------------------------

function chk(id, value, dflt) {
  $(id).checked = value === undefined ? dflt : Boolean(value);
}

function openProxyHost(h) {
  $("ph-orig").value = h ? h.name : "";
  $("ph-name").value = h ? h.name : "";
  $("ph-forward_scheme").value = h ? h.forward_scheme : "http";
  $("ph-domain_names").value = h ? domainsToText(h.domain_names) : "";
  $("ph-forward_host").value = h ? h.forward_host : "";
  $("ph-forward_port").value = h ? h.forward_port : "";
  fillSelect($("ph-certificate"), "certificates", h ? h.certificate : "", "— no certificate —");
  fillSelect($("ph-access_list"), "access_lists", h ? h.access_list : "", "— no access list —");
  chk("ph-enabled", h && h.enabled, true);
  chk("ph-ssl_forced", h && h.ssl_forced, true);
  chk("ph-block_exploits", h && h.block_exploits, true);
  chk("ph-caching_enabled", h && h.caching_enabled, false);
  chk("ph-allow_websocket_upgrade", h && h.allow_websocket_upgrade, true);
  chk("ph-http2_support", h && h.http2_support, true);
  chk("ph-hsts_enabled", h && h.hsts_enabled, false);
  chk("ph-hsts_subdomains", h && h.hsts_subdomains, false);
  $("ph-loc-rows").innerHTML = "";
  ((h && h.locations) || []).forEach((l) => addLocationRow(l));
  $("proxy_hosts-title").textContent = h ? `Edit ${h.name}` : "Add proxy host";
  openModal("modal-proxy_hosts");
}

function proxyHostPayload() {
  return {
    name: $("ph-name").value.trim(),
    forward_scheme: $("ph-forward_scheme").value,
    domain_names: $("ph-domain_names").value.trim(),
    forward_host: $("ph-forward_host").value.trim(),
    forward_port: $("ph-forward_port").value.trim(),
    certificate: $("ph-certificate").value,
    access_list: $("ph-access_list").value,
    enabled: $("ph-enabled").checked,
    ssl_forced: $("ph-ssl_forced").checked,
    block_exploits: $("ph-block_exploits").checked,
    caching_enabled: $("ph-caching_enabled").checked,
    allow_websocket_upgrade: $("ph-allow_websocket_upgrade").checked,
    http2_support: $("ph-http2_support").checked,
    hsts_enabled: $("ph-hsts_enabled").checked,
    hsts_subdomains: $("ph-hsts_subdomains").checked,
    locations: collectRows("ph-loc-rows", ["path", "forward_scheme", "forward_host", "forward_port"]),
  };
}

function openCertificate(c) {
  $("cert-orig").value = c ? c.name : "";
  $("cert-name").value = c ? c.name : "";
  $("cert-letsencrypt_email").value = c ? c.letsencrypt_email || "" : "";
  $("cert-domain_names").value = c ? domainsToText(c.domain_names) : "";
  chk("cert-letsencrypt_agree", c ? c.letsencrypt_agree : undefined, true);
  const dns = (c && c.dns_challenge) || {};
  $("cert-dns-enabled").checked = Boolean(dns.enabled);
  $("cert-dns-provider").value = dns.provider || "";
  $("cert-dns-prop").value = dns.propagation_seconds != null ? dns.propagation_seconds : "";
  $("cert-dns-creds").value = dns.credentials || "";
  $("certificates-title").textContent = c ? `Edit ${c.name}` : "Add certificate";
  openModal("modal-certificates");
}

function certificatePayload() {
  const payload = {
    name: $("cert-name").value.trim(),
    domain_names: $("cert-domain_names").value.trim(),
    letsencrypt_email: $("cert-letsencrypt_email").value.trim(),
    letsencrypt_agree: $("cert-letsencrypt_agree").checked,
  };
  const enabled = $("cert-dns-enabled").checked;
  const provider = $("cert-dns-provider").value.trim();
  const creds = $("cert-dns-creds").value.trim();
  const prop = $("cert-dns-prop").value.trim();
  if (enabled || provider || creds || prop) {
    payload.dns_challenge = { enabled, provider, credentials: creds, propagation_seconds: prop };
  }
  return payload;
}

function openRedirection(r) {
  $("rd-orig").value = r ? r.name : "";
  $("rd-name").value = r ? r.name : "";
  $("rd-forward_domain_name").value = r ? r.forward_domain_name : "";
  $("rd-domain_names").value = r ? domainsToText(r.domain_names) : "";
  $("rd-forward_scheme").value = r ? r.forward_scheme : "auto";
  $("rd-forward_http_code").value = r ? r.forward_http_code : 301;
  fillSelect($("rd-certificate"), "certificates", r ? r.certificate : "", "— no certificate —");
  chk("rd-enabled", r && r.enabled, true);
  chk("rd-preserve_path", r && r.preserve_path, true);
  chk("rd-ssl_forced", r && r.ssl_forced, true);
  chk("rd-block_exploits", r && r.block_exploits, true);
  chk("rd-http2_support", r && r.http2_support, true);
  chk("rd-hsts_enabled", r && r.hsts_enabled, false);
  chk("rd-hsts_subdomains", r && r.hsts_subdomains, false);
  $("redirections-title").textContent = r ? `Edit ${r.name}` : "Add redirection";
  openModal("modal-redirections");
}

function redirectionPayload() {
  return {
    name: $("rd-name").value.trim(),
    forward_domain_name: $("rd-forward_domain_name").value.trim(),
    domain_names: $("rd-domain_names").value.trim(),
    forward_scheme: $("rd-forward_scheme").value,
    forward_http_code: $("rd-forward_http_code").value.trim(),
    certificate: $("rd-certificate").value,
    enabled: $("rd-enabled").checked,
    preserve_path: $("rd-preserve_path").checked,
    ssl_forced: $("rd-ssl_forced").checked,
    block_exploits: $("rd-block_exploits").checked,
    http2_support: $("rd-http2_support").checked,
    hsts_enabled: $("rd-hsts_enabled").checked,
    hsts_subdomains: $("rd-hsts_subdomains").checked,
  };
}

function openStream(s) {
  $("st-orig").value = s ? s.name : "";
  $("st-name").value = s ? s.name : "";
  $("st-incoming_port").value = s ? s.incoming_port : "";
  $("st-forwarding_host").value = s ? s.forwarding_host : "";
  $("st-forwarding_port").value = s ? s.forwarding_port : "";
  fillSelect($("st-certificate"), "certificates", s ? s.certificate : "", "— no certificate —");
  chk("st-tcp_forwarding", s && s.tcp_forwarding, true);
  chk("st-udp_forwarding", s && s.udp_forwarding, false);
  chk("st-enabled", s && s.enabled, true);
  $("streams-title").textContent = s ? `Edit ${s.name}` : "Add stream";
  openModal("modal-streams");
}

function streamPayload() {
  return {
    name: $("st-name").value.trim(),
    incoming_port: $("st-incoming_port").value.trim(),
    forwarding_host: $("st-forwarding_host").value.trim(),
    forwarding_port: $("st-forwarding_port").value.trim(),
    certificate: $("st-certificate").value,
    tcp_forwarding: $("st-tcp_forwarding").checked,
    udp_forwarding: $("st-udp_forwarding").checked,
    enabled: $("st-enabled").checked,
  };
}

function openAccessList(a) {
  $("al-orig").value = a ? a.name : "";
  $("al-name").value = a ? a.name : "";
  $("al-satisfy_any").checked = Boolean(a && a.satisfy_any);
  $("al-pass_auth").checked = Boolean(a && a.pass_auth);
  $("al-auth-rows").innerHTML = "";
  ((a && a.authorizations) || []).forEach((u) => addAuthRow(u));
  $("al-access-rows").innerHTML = "";
  ((a && a.access) || []).forEach((r) => addAccessRow(r));
  $("access_lists-title").textContent = a ? `Edit ${a.name}` : "Add access list";
  openModal("modal-access_lists");
}

function accessListPayload() {
  return {
    name: $("al-name").value.trim(),
    satisfy_any: $("al-satisfy_any").checked,
    pass_auth: $("al-pass_auth").checked,
    authorizations: collectRows("al-auth-rows", ["username", "password"]),
    access: collectRows("al-access-rows", ["directive", "address"]),
  };
}

const OPENERS = {
  proxy_hosts: openProxyHost,
  certificates: openCertificate,
  redirections: openRedirection,
  streams: openStream,
  access_lists: openAccessList,
};
const PAYLOADS = {
  proxy_hosts: proxyHostPayload,
  certificates: certificatePayload,
  redirections: redirectionPayload,
  streams: streamPayload,
  access_lists: accessListPayload,
};

// --- form submit / shared save ---------------------------------------------

async function saveEntry(collection, origKey, payload) {
  try {
    setSaveState("saving");
    if (origKey) {
      await api(`${API}/${collection}/${encodeURIComponent(origKey)}`, {
        method: "PUT",
        body: JSON.stringify(payload),
      });
      toast(`Saved ${payload.name}`, "success");
    } else {
      await api(`${API}/${collection}`, {
        method: "POST",
        body: JSON.stringify(payload),
      });
      toast(`Added ${payload.name}`, "success");
    }
    setSaveState("saved");
    closeModal($(`modal-${collection}`));
    refreshTfvars();
  } catch (err) {
    setSaveState("error", err.message);
    toast(err.message, "error");
  }
}

COLLECTIONS.forEach((collection) => {
  $(`${collection}-form`).addEventListener("submit", (event) => {
    event.preventDefault();
    const origId = { proxy_hosts: "ph-orig", certificates: "cert-orig", redirections: "rd-orig", streams: "st-orig", access_lists: "al-orig" }[collection];
    saveEntry(collection, $(origId).value, PAYLOADS[collection]());
  });
});

// --- table + modal wiring --------------------------------------------------

function findEntry(collection, key) {
  return (currentConfig[collection] || []).find((e) => String(e.name) === String(key));
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
document.querySelectorAll(".fixed").forEach((modal) => {
  modal.addEventListener("click", (event) => {
    if (event.target === modal) closeModal(modal);
  });
});

function onTableClick(event) {
  const editBtn = event.target.closest("[data-edit-collection]");
  if (editBtn) {
    const c = editBtn.dataset.editCollection;
    const entry = findEntry(c, editBtn.dataset.key);
    if (entry) OPENERS[c](entry);
    return;
  }
  const delBtn = event.target.closest("[data-del-collection]");
  if (delBtn) {
    const c = delBtn.dataset.delCollection;
    const key = delBtn.dataset.key;
    if (!confirm(`Delete ${c} entry "${key}"?`)) return;
    api(`${API}/${c}/${encodeURIComponent(key)}`, { method: "DELETE" })
      .then(() => {
        toast(`Deleted ${key}`, "success");
        refreshTfvars();
      })
      .catch((err) => toast(err.message, "error"));
  }
}
COLLECTIONS.forEach((c) => $(`${c}-rows`).addEventListener("click", onTableClick));

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
$("reload-btn").addEventListener("click", doReload);
$("drift-reload").addEventListener("click", doReload);

$("preview-btn").addEventListener("click", async () => {
  await refreshTfvars();
  openModal("modal-preview");
});
$("preview-copy").addEventListener("click", async () => {
  try {
    await navigator.clipboard.writeText($("tfvars-preview").textContent || "");
    toast("Copied config.tfvars to clipboard", "success");
  } catch (err) {
    toast("Could not copy to clipboard", "error");
  }
});
document.addEventListener("keydown", (event) => {
  if (event.key === "Escape") document.querySelectorAll(".fixed").forEach((m) => closeModal(m));
});

socket.on("npm_config:config", (config) => {
  renderConfig(config);
  refreshTfvars();
});
socket.on("npm_config:status", renderStatus);

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
