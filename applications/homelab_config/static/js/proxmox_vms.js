"use strict";

const socket = io();

let currentImages = [];
let currentMachines = [];

// --- shared helpers -------------------------------------------------------

function debounce(fn, ms) {
  let timer;
  return (...args) => {
    clearTimeout(timer);
    timer = setTimeout(() => fn(...args), ms);
  };
}

const saveStateEl = document.getElementById("save-state");
let saveStateTimer;
function setSaveState(kind, message) {
  clearTimeout(saveStateTimer);
  if (kind === "saving") {
    saveStateEl.innerHTML = '<i class="fa-solid fa-circle-notch fa-spin"></i>';
    saveStateEl.className = "text-sm text-sky-300";
    saveStateEl.title = "Saving…";
  } else if (kind === "saved") {
    saveStateEl.innerHTML = '<i class="fa-solid fa-cloud-arrow-up"></i>';
    saveStateEl.className = "text-sm text-emerald-300";
    saveStateEl.title = "Saved";
    saveStateTimer = setTimeout(() => setSaveState("idle"), 1000);
  } else if (kind === "error") {
    saveStateEl.innerHTML = `<i class="fa-solid fa-triangle-exclamation mr-1 text-rose-400"></i>${escapeHtml(
      message || "Save failed"
    )}`;
    saveStateEl.className = "text-xs font-medium text-rose-300";
    saveStateEl.title = message || "Save failed";
  } else {
    saveStateEl.innerHTML = '<i class="fa-solid fa-cloud"></i>';
    saveStateEl.className = "text-sm text-slate-500";
    saveStateEl.title = "Auto-save on";
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

function toList(value) {
  return String(value || "")
    .split(",")
    .map((part) => part.trim())
    .filter(Boolean);
}

async function refreshTfvars() {
  try {
    const data = await api("/api/proxmox-vms/tfvars");
    document.getElementById("tfvars-preview").textContent = data.tfvars || "";
  } catch (err) {
    /* non-fatal */
  }
}

function renderStatus(status) {
  const banner = document.getElementById("drift-banner");
  if (status && status.external_change) {
    document.getElementById("drift-message").textContent =
      "app.tfvars changed on disk outside the app.";
    banner.style.display = "flex";
  } else {
    banner.style.display = "none";
  }
}

// ============================ IMAGES ============================

const img = {
  form: document.getElementById("img-form"),
  orig: document.getElementById("img-orig"),
  key: document.getElementById("img-key"),
  fileName: document.getElementById("img-file-name"),
  url: document.getElementById("img-url"),
  contentType: document.getElementById("img-content-type"),
  datastore: document.getElementById("img-datastore"),
  node: document.getElementById("img-node"),
  uploadTimeout: document.getElementById("img-upload-timeout"),
  verify: document.getElementById("img-verify"),
  overwrite: document.getElementById("img-overwrite"),
  overwriteUnmanaged: document.getElementById("img-overwrite-unmanaged"),
  rows: document.getElementById("img-rows"),
  empty: document.getElementById("img-empty"),
  title: document.getElementById("img-form-title"),
  saveBtn: document.getElementById("img-save-btn"),
  cancel: document.getElementById("img-cancel"),
};

function imgEditing() {
  return Boolean(img.orig.value);
}

function imgPayload() {
  const payload = {
    key: img.key.value.trim(),
    file_name: img.fileName.value.trim(),
    url: img.url.value.trim(),
    verify: img.verify.checked,
    overwrite: img.overwrite.checked,
    overwrite_unmanaged: img.overwriteUnmanaged.checked,
  };
  if (img.contentType.value.trim()) payload.content_type = img.contentType.value.trim();
  if (img.datastore.value.trim()) payload.datastore_id = img.datastore.value.trim();
  if (img.node.value.trim()) payload.node_name = img.node.value.trim();
  if (img.uploadTimeout.value.trim())
    payload.upload_timeout = Number(img.uploadTimeout.value.trim());
  return payload;
}

function imgReset() {
  img.orig.value = "";
  img.form.reset();
  img.overwrite.checked = true;
  img.overwriteUnmanaged.checked = true;
  img.title.textContent = "Add image";
  img.saveBtn.hidden = false;
  img.saveBtn.innerHTML = '<i class="fa-solid fa-plus mr-2"></i>Add image';
  img.cancel.hidden = true;
}

function imgStartEdit(image) {
  img.orig.value = image.key;
  img.key.value = image.key;
  img.fileName.value = image.file_name;
  img.url.value = image.url;
  img.contentType.value = image.content_type;
  img.datastore.value = image.datastore_id;
  img.node.value = image.node_name;
  img.uploadTimeout.value = image.upload_timeout;
  img.verify.checked = image.verify;
  img.overwrite.checked = image.overwrite;
  img.overwriteUnmanaged.checked = image.overwrite_unmanaged;
  img.title.textContent = `Edit ${image.key}`;
  img.saveBtn.hidden = true;
  img.cancel.hidden = false;
  img.cancel.innerHTML = '<i class="fa-solid fa-check mr-2"></i>Done';
  img.key.focus();
}

async function imgAutosave() {
  const orig = img.orig.value;
  if (!orig) return;
  const payload = imgPayload();
  if (!payload.key || !payload.file_name || !payload.url) {
    setSaveState("error", "Key, file name and URL are required");
    return;
  }
  try {
    setSaveState("saving");
    const updated = await api(`/api/proxmox-vms/images/${encodeURIComponent(orig)}`, {
      method: "PUT",
      body: JSON.stringify(payload),
    });
    img.orig.value = updated.key;
    img.title.textContent = `Edit ${updated.key}`;
    setSaveState("saved");
    refreshTfvars();
  } catch (err) {
    setSaveState("error", err.message);
  }
}

const imgAutosaveDebounced = debounce(imgAutosave, 450);

function renderImages(images) {
  currentImages = images;
  img.rows.innerHTML = "";
  if (!images.length) {
    img.empty.hidden = false;
  } else {
    img.empty.hidden = true;
    images.forEach((image) => {
      const row = document.createElement("tr");
      row.className = "hover:bg-slate-800/40";
      row.innerHTML = `
        <td class="px-4 py-3">
          <div class="font-medium text-slate-100">${escapeHtml(image.key)}</div>
          <div class="text-xs text-slate-500">${escapeHtml(image.content_type)} · ${escapeHtml(image.datastore_id)}@${escapeHtml(image.node_name)}</div>
        </td>
        <td class="px-4 py-3 font-mono text-xs text-slate-400">${escapeHtml(image.file_name)}</td>
        <td class="px-4 py-3 max-w-xs truncate font-mono text-xs text-slate-500" title="${escapeHtml(image.url)}">${escapeHtml(image.url)}</td>
        <td class="px-4 py-3 text-right whitespace-nowrap">
          <button data-img-edit="${escapeHtml(image.key)}" class="mr-1 rounded-md px-2 py-1 text-slate-400 hover:bg-slate-700 hover:text-sky-300" title="Edit"><i class="fa-solid fa-pen"></i></button>
          <button data-img-delete="${escapeHtml(image.key)}" class="rounded-md px-2 py-1 text-slate-400 hover:bg-slate-700 hover:text-rose-300" title="Delete"><i class="fa-solid fa-trash"></i></button>
        </td>`;
      img.rows.appendChild(row);
    });
  }
  refreshImageOptions();
}

img.form.addEventListener("submit", async (event) => {
  event.preventDefault();
  if (imgEditing()) {
    imgAutosave();
    return;
  }
  try {
    await api("/api/proxmox-vms/images", {
      method: "POST",
      body: JSON.stringify(imgPayload()),
    });
    toast(`Added image ${img.key.value.trim()}`, "success");
    imgReset();
    refreshTfvars();
  } catch (err) {
    toast(err.message, "error");
  }
});

img.cancel.addEventListener("click", imgReset);

[
  img.key, img.fileName, img.url, img.contentType, img.datastore,
  img.node, img.uploadTimeout,
].forEach((el) =>
  el.addEventListener("input", () => {
    if (imgEditing()) imgAutosaveDebounced();
  })
);
[img.verify, img.overwrite, img.overwriteUnmanaged].forEach((el) =>
  el.addEventListener("change", () => {
    if (imgEditing()) imgAutosave();
  })
);

img.rows.addEventListener("click", async (event) => {
  const editBtn = event.target.closest("[data-img-edit]");
  if (editBtn) {
    const image = currentImages.find((i) => i.key === editBtn.dataset.imgEdit);
    if (image) imgStartEdit(image);
    return;
  }
  const delBtn = event.target.closest("[data-img-delete]");
  if (delBtn) {
    if (!confirm(`Delete image "${delBtn.dataset.imgDelete}"?`)) return;
    try {
      await api(`/api/proxmox-vms/images/${encodeURIComponent(delBtn.dataset.imgDelete)}`, {
        method: "DELETE",
      });
      toast(`Deleted image ${delBtn.dataset.imgDelete}`, "success");
      refreshTfvars();
    } catch (err) {
      toast(err.message, "error");
    }
  }
});

// ============================ MACHINES ============================

const m = {
  form: document.getElementById("m-form"),
  orig: document.getElementById("m-orig"),
  name: document.getElementById("m-name"),
  vmId: document.getElementById("m-vm-id"),
  node: document.getElementById("m-node"),
  cores: document.getElementById("m-cores"),
  memory: document.getElementById("m-memory"),
  cpuType: document.getElementById("m-cpu-type"),
  tags: document.getElementById("m-tags"),
  bootOrder: document.getElementById("m-boot-order"),
  diskDatastore: document.getElementById("m-disk-datastore"),
  diskInterface: document.getElementById("m-disk-interface"),
  diskSize: document.getElementById("m-disk-size"),
  diskImage: document.getElementById("m-disk-image"),
  cdromInterface: document.getElementById("m-cdrom-interface"),
  cdromImage: document.getElementById("m-cdrom-image"),
  initDatastore: document.getElementById("m-init-datastore"),
  initInterface: document.getElementById("m-init-interface"),
  userConfigPath: document.getElementById("m-user-config-path"),
  networkConfigPath: document.getElementById("m-network-config-path"),
  netBridge: document.getElementById("m-net-bridge"),
  netModel: document.getElementById("m-net-model"),
  netMac: document.getElementById("m-net-mac"),
  bios: document.getElementById("m-bios"),
  machine: document.getElementById("m-machine"),
  osType: document.getElementById("m-os-type"),
  efiDatastore: document.getElementById("m-efi-datastore"),
  efiType: document.getElementById("m-efi-type"),
  efiPreEnrolled: document.getElementById("m-efi-pre-enrolled"),
  started: document.getElementById("m-started"),
  onBoot: document.getElementById("m-on-boot"),
  rows: document.getElementById("m-rows"),
  empty: document.getElementById("m-empty"),
  title: document.getElementById("m-form-title"),
  saveBtn: document.getElementById("m-save-btn"),
  cancel: document.getElementById("m-cancel"),
};

function refreshImageOptions() {
  [m.diskImage, m.cdromImage].forEach((select) => {
    const previous = select.value;
    const noneLabel = select === m.diskImage ? "(none / blank disk)" : "(none)";
    select.innerHTML = `<option value="">${noneLabel}</option>`;
    currentImages.forEach((image) => {
      const opt = document.createElement("option");
      opt.value = image.key;
      opt.textContent = image.key;
      select.appendChild(opt);
    });
    select.value = previous;
    if (select.value !== previous) select.value = "";
  });
}

function mEditing() {
  return Boolean(m.orig.value);
}

function mPayload() {
  const payload = {
    name: m.name.value.trim(),
    vm_id: Number(m.vmId.value.trim()),
    memory: Number(m.memory.value.trim()),
    disk_size: Number(m.diskSize.value.trim()),
    net_mac_address: m.netMac.value.trim(),
    user_config_path: m.userConfigPath.value.trim(),
    network_config_path: m.networkConfigPath.value.trim(),
    disk_image: m.diskImage.value,
    cdrom_image: m.cdromImage.value,
    tags: toList(m.tags.value),
    boot_order: toList(m.bootOrder.value),
    started: m.started.checked,
    on_boot: m.onBoot.checked,
    efi_pre_enrolled_keys: m.efiPreEnrolled.checked,
  };
  const optionalStr = {
    node_name: m.node.value,
    cpu_type: m.cpuType.value,
    disk_datastore_id: m.diskDatastore.value,
    disk_interface: m.diskInterface.value,
    cdrom_interface: m.cdromInterface.value,
    init_datastore_id: m.initDatastore.value,
    init_interface: m.initInterface.value,
    net_bridge: m.netBridge.value,
    net_model: m.netModel.value,
    bios: m.bios.value,
    machine: m.machine.value,
    os_type: m.osType.value,
    efi_datastore_id: m.efiDatastore.value,
    efi_type: m.efiType.value,
  };
  Object.entries(optionalStr).forEach(([k, v]) => {
    const trimmed = String(v || "").trim();
    if (trimmed) payload[k] = trimmed;
  });
  if (m.cores.value.trim()) payload.cores = Number(m.cores.value.trim());
  return payload;
}

function mReset() {
  m.orig.value = "";
  m.form.reset();
  m.started.checked = true;
  m.onBoot.checked = true;
  refreshImageOptions();
  m.title.textContent = "Add machine";
  m.saveBtn.hidden = false;
  m.saveBtn.innerHTML = '<i class="fa-solid fa-plus mr-2"></i>Add machine';
  m.cancel.hidden = true;
}

function mStartEdit(machine) {
  m.orig.value = machine.name;
  m.name.value = machine.name;
  m.vmId.value = machine.vm_id;
  m.node.value = machine.node_name;
  m.cores.value = machine.cores;
  m.memory.value = machine.memory;
  m.cpuType.value = machine.cpu_type;
  m.tags.value = (machine.tags || []).join(", ");
  m.bootOrder.value = (machine.boot_order || []).join(", ");
  m.diskDatastore.value = machine.disk_datastore_id;
  m.diskInterface.value = machine.disk_interface;
  m.diskSize.value = machine.disk_size;
  refreshImageOptions();
  m.diskImage.value = machine.disk_image || "";
  m.cdromInterface.value = machine.cdrom_interface || "";
  m.cdromImage.value = machine.cdrom_image || "";
  m.initDatastore.value = machine.init_datastore_id;
  m.initInterface.value = machine.init_interface;
  m.userConfigPath.value = machine.user_config_path;
  m.networkConfigPath.value = machine.network_config_path;
  m.netBridge.value = machine.net_bridge;
  m.netModel.value = machine.net_model;
  m.netMac.value = machine.net_mac_address;
  m.bios.value = machine.bios;
  m.machine.value = machine.machine;
  m.osType.value = machine.os_type;
  m.efiDatastore.value = machine.efi_datastore_id;
  m.efiType.value = machine.efi_type;
  m.efiPreEnrolled.checked = machine.efi_pre_enrolled_keys;
  m.started.checked = machine.started;
  m.onBoot.checked = machine.on_boot;
  m.title.textContent = `Edit ${machine.name}`;
  m.saveBtn.hidden = true;
  m.cancel.hidden = false;
  m.cancel.innerHTML = '<i class="fa-solid fa-check mr-2"></i>Done';
  m.name.focus();
}

async function mAutosave() {
  const orig = m.orig.value;
  if (!orig) return;
  const payload = mPayload();
  if (
    !payload.name ||
    !payload.vm_id ||
    !payload.memory ||
    !payload.disk_size ||
    !payload.net_mac_address ||
    !payload.user_config_path ||
    !payload.network_config_path
  ) {
    setSaveState("error", "Name, VM ID, memory, disk size, MAC and cloud-init paths are required");
    return;
  }
  try {
    setSaveState("saving");
    const updated = await api(`/api/proxmox-vms/machines/${encodeURIComponent(orig)}`, {
      method: "PUT",
      body: JSON.stringify(payload),
    });
    m.orig.value = updated.name;
    m.title.textContent = `Edit ${updated.name}`;
    setSaveState("saved");
    refreshTfvars();
  } catch (err) {
    setSaveState("error", err.message);
  }
}

const mAutosaveDebounced = debounce(mAutosave, 450);

function renderMachines(machines) {
  currentMachines = machines;
  m.rows.innerHTML = "";
  if (!machines.length) {
    m.empty.hidden = false;
    return;
  }
  m.empty.hidden = true;
  machines.forEach((machine) => {
    const bootBits = [];
    if (machine.disk_image) bootBits.push(`disk:${machine.disk_image}`);
    if (machine.cdrom_image) bootBits.push(`cdrom:${machine.cdrom_image}`);
    const boot = bootBits.length
      ? bootBits.map((b) => escapeHtml(b)).join(" · ")
      : '<span class="text-slate-600">&mdash;</span>';
    const row = document.createElement("tr");
    row.className = "hover:bg-slate-800/40";
    row.innerHTML = `
      <td class="px-4 py-3">
        <div class="font-medium text-slate-100">${escapeHtml(machine.name)}</div>
        <div class="text-xs text-slate-500">#${escapeHtml(machine.vm_id)} · ${escapeHtml((machine.tags || []).join(", "))}</div>
      </td>
      <td class="px-4 py-3 text-xs text-slate-400">${escapeHtml(machine.cores)} vCPU · ${escapeHtml(machine.memory)} MiB · ${escapeHtml(machine.disk_size)} GiB</td>
      <td class="px-4 py-3 font-mono text-xs text-slate-400">${boot}</td>
      <td class="px-4 py-3 font-mono text-xs text-slate-500">${escapeHtml(machine.net_mac_address)}</td>
      <td class="px-4 py-3 text-right whitespace-nowrap">
        <button data-m-edit="${escapeHtml(machine.name)}" class="mr-1 rounded-md px-2 py-1 text-slate-400 hover:bg-slate-700 hover:text-sky-300" title="Edit"><i class="fa-solid fa-pen"></i></button>
        <button data-m-delete="${escapeHtml(machine.name)}" class="rounded-md px-2 py-1 text-slate-400 hover:bg-slate-700 hover:text-rose-300" title="Delete"><i class="fa-solid fa-trash"></i></button>
      </td>`;
    m.rows.appendChild(row);
  });
}

m.form.addEventListener("submit", async (event) => {
  event.preventDefault();
  if (mEditing()) {
    mAutosave();
    return;
  }
  try {
    await api("/api/proxmox-vms/machines", {
      method: "POST",
      body: JSON.stringify(mPayload()),
    });
    toast(`Added machine ${m.name.value.trim()}`, "success");
    mReset();
    refreshTfvars();
  } catch (err) {
    toast(err.message, "error");
  }
});

m.cancel.addEventListener("click", mReset);

[
  m.name, m.vmId, m.node, m.cores, m.memory, m.cpuType, m.tags, m.bootOrder,
  m.diskDatastore, m.diskInterface, m.diskSize, m.cdromInterface,
  m.initDatastore, m.initInterface, m.userConfigPath, m.networkConfigPath,
  m.netBridge, m.netModel, m.netMac, m.bios, m.machine, m.osType,
  m.efiDatastore, m.efiType,
].forEach((el) =>
  el.addEventListener("input", () => {
    if (mEditing()) mAutosaveDebounced();
  })
);
[
  m.diskImage, m.cdromImage, m.efiPreEnrolled, m.started, m.onBoot,
].forEach((el) =>
  el.addEventListener("change", () => {
    if (mEditing()) mAutosave();
  })
);

m.rows.addEventListener("click", async (event) => {
  const editBtn = event.target.closest("[data-m-edit]");
  if (editBtn) {
    const machine = currentMachines.find((x) => x.name === editBtn.dataset.mEdit);
    if (machine) mStartEdit(machine);
    return;
  }
  const delBtn = event.target.closest("[data-m-delete]");
  if (delBtn) {
    if (!confirm(`Delete machine "${delBtn.dataset.mDelete}"?`)) return;
    try {
      await api(`/api/proxmox-vms/machines/${encodeURIComponent(delBtn.dataset.mDelete)}`, {
        method: "DELETE",
      });
      toast(`Deleted machine ${delBtn.dataset.mDelete}`, "success");
      refreshTfvars();
    } catch (err) {
      toast(err.message, "error");
    }
  }
});

// ============================ shared controls ============================

async function doReload() {
  try {
    const data = await api("/api/proxmox-vms/reload", { method: "POST" });
    renderImages(data.images);
    renderMachines(data.machines);
    renderStatus(data.status);
    imgReset();
    mReset();
    refreshTfvars();
    toast("Reloaded from disk", "success");
  } catch (err) {
    toast(err.message, "error");
  }
}

document.getElementById("reload-btn").addEventListener("click", doReload);
document.getElementById("drift-reload").addEventListener("click", doReload);

const previewModal = document.getElementById("modal-preview");
document.getElementById("preview-btn").addEventListener("click", async () => {
  await refreshTfvars();
  previewModal.style.display = "flex";
});
document.getElementById("preview-copy").addEventListener("click", async () => {
  try {
    await navigator.clipboard.writeText(
      document.getElementById("tfvars-preview").textContent || ""
    );
    toast("Copied app.tfvars to clipboard", "success");
  } catch (err) {
    toast("Could not copy to clipboard", "error");
  }
});
previewModal.addEventListener("click", (event) => {
  if (event.target === previewModal || event.target.closest("[data-close]")) {
    previewModal.style.display = "none";
  }
});
document.addEventListener("keydown", (event) => {
  if (event.key === "Escape") previewModal.style.display = "none";
});

// ============================ live updates ============================

socket.on("proxmox_vms:images", (images) => {
  renderImages(images);
  refreshTfvars();
});
socket.on("proxmox_vms:machines", (machines) => {
  renderMachines(machines);
  refreshTfvars();
});
socket.on("proxmox_vms:status", renderStatus);

async function init() {
  setSaveState("idle");
  try {
    const data = await api("/api/proxmox-vms");
    renderImages(data.images);
    renderMachines(data.machines);
    renderStatus(data.status);
    refreshTfvars();
  } catch (err) {
    toast(err.message, "error");
  }
}

init();
