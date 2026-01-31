const CATEGORIES = ["ВСЕ_ВМ", "DC", "FS", "МЭ", "DLP", "АВЗ", "SIEM", "Clients"];

const DATA = [
  {
    category: "DLP",
    items: [
      {
        id: "IWTM",
        os: "linux",
        title: "INFOWATCH TRAFFIC MONITOR",
        desc: "СИСТЕМА ПРЕДОТВРАЩЕНИЯ УТЕЧЕК ИНФОРМАЦИИ",
        ip: "172.21.30.12",
        ssh: { enabled: true, host: "172.21.30.12", port: 22, user: "astra" },
        rdp: { enabled: false }
      }
    ]
  },
  {
    category: "DLP",
    items: [
      {
        id: "IWDM",
        os: "linux",
        title: "INFOWATCH DEVICE MONITOR",
        desc: "СИСТЕМА ПРЕДОТВРАЩЕНИЯ УТЕЧЕК ИНФОРМАЦИИ",
        ip: "172.21.30.13",
        ssh: { enabled: true, host: "172.21.30.13", port: 22, user: "astra" },
        rdp: { enabled: false }
      }
    ]
  },
  {
    category: "DLP",
    items: [
      {
        id: "IWDD",
        os: "linux",
        title: "INFOWATCH DATA DISCOVERY",
        desc: "СИСТЕМА ПРЕДОТВРАЩЕНИЯ УТЕЧЕК ИНФОРМАЦИИ",
        ip: "172.21.30.14",
        ssh: { enabled: true, host: "172.21.30.14", port: 22, user: "astra" },
        rdp: { enabled: false }
      }
    ]
  },
    {
    category: "АВЗ",
    items: [
      {
        id: "KSC",
        os: "linux",
        title: "KASPERSKY SECURITY CENTER",
        desc: "КОНТРОЛЬ АНТИВИРУСНОЙ ЗАЩИТЫ",
        ip: "172.21.30.11",
        ssh: { enabled: true, host: "172.21.30.11", port: 22, user: "astra" },
        rdp: {  enabled: false }
      }
    ]
  },
    {
    category: "АВЗ",
    items: [
      {
        id: "KSMG",
        os: "linux",
        title: "KASPERSKY SECURITY MAIL GATEWAY",
        desc: "КОНТРОЛЬ ПОЧТОВОГО ТРАФИКА",
        ip: "172.21.30.15",
        ssh: { enabled: false },
        rdp: {  enabled: false },
        info: "https://172.21.30.15/",
        infoType: "link"
      }
    ]
  },
  {
    category: "SIEM",
    items: [
      {
        id: "KUMA",
        os: "linux",
        title: "KUMA",
        desc: "СБОР И НОРМАЛИЗАЦИЯ СОБЫТИЙ",
        ip: "172.21.30.16",
        ssh: { enabled: true, host: "172.21.30.16", port: 22, user: "astra" },
        rdp: { enabled: false }
      }
    ]
  },
  {
    category: "DC",
    items: [
      {
        id: "DC",
        os: "linux",
        title: "ALD PRO DC",
        desc: "КОНТРОЛЛЕР ДОМЕНА АЛД ПРО",
        ip: "172.21.30.2",
        ssh: { enabled: true, host: "172.21.30.2", port: 22, user: "astra" },
        rdp: { enabled: false }
      }
    ]
  },
    {
    category: "DC",
    items: [
      {
        id: "DC",
        os: "windows",
        title: "AD DC",
        desc: "КОНТРОЛЛЕР ДОМЕНА ACTIVE DIRECTORY",
        ip: "172.21.30.3",
        ssh: { enabled: false  },
        rdp: { enabled: true, host: "172.21.30.3", port: 3389, user: "Администратор"}
      }
    ]
  },
    {
    category: "DC",
    items: [
      {
        id: "MAIL",
        os: "linux",
        title: "POSTFIX MAIL SERVER",
        desc: "ПОЧТОВЫЙ СЕРВЕР",
        ip: "172.21.30.110",
        ssh: { enabled: true, host: "172.21.30.110", port: 22, user: "astra" },
        rdp: { enabled: false }
      }
    ]
  },
  {
    category: "МЭ",
    items: [
      {
        id: "PFSENSE",
        os: "linux",
        title: "PFSENSE",
        desc: "МЕЖСЕТЕВОЙ ЭКРАН",
        ip: "172.21.30.254",
        ssh: { enabled: false },
        rdp: { enabled: false },
        info: "http://172.21.30.254/",
        infoType: "link"
      }
    ]
  },
  {
    category: "FS",
    items: [
      {
        id: "FS_LINUX",
        os: "linux",
        title: "FSHARE",
        desc: "ФАЙЛОВЫЙ СЕРВЕР ПРЕДПРИЯТИЯ",
        ip: "172.21.30.4",
        ssh: { enabled: true, host: "172.21.30.4", port: 22, user: "astra" },
        rdp: { enabled: false }
      }
    ]
  },
    {
    category: "FS",
    items: [
      {
        id: "FS_DISTRIB",
        os: "windows",
        title: "FILESHARE_DISTRIB",
        desc: "Дистрибутивы",
        ip: "172.21.30.252",
        ssh: { enabled: false },
        rdp: { enabled: false },
        info: "smb://172.21.30.252/DISTRIB/",
        infoType: "smb"
      }
    ]
  },
  {
    category: "Clients",
    items: [
      {
        id: "Astra_Office",
        os: "linux",
        title: "ASTRA_OFFICE",
        desc: "КЛИЕНТ ОФИСА АСТРА",
        ip: "172.21.30.101",
        ssh: { enabled: true, host: "172.21.30.101", port: 22, user: "astra" },
        rdp: { enabled: false }
      }
    ]
  },
  {
    category: "Clients",
    items: [
      {
        id: "Astra_Filial",
        os: "linux",
        title: "ASTRA_FILIAL",
        desc: "КЛИЕНТ ФИЛИАЛА АСТРА",
        ip: "172.21.31.101",
        ssh: { enabled: true, host: "172.21.31.101", port: 22, user: "astra" },
        rdp: { enabled: false }
      }
    ]
  },
  {
    category: "Clients",
    items: [
      {
        id: "Windows_Office",
        os: "windows",
        title: "WINDOWS_OFFICE",
        desc: "КЛИЕНТ ОФИСА WINDOWS",
        ip: "172.21.30.102",
        ssh: { enabled: false },
        rdp: { enabled: true, host: "172.21.30.102", port: 3389, user: "windows" }
      }
    ]
  }
];

/* ===== DOM ===== */
const tabsEl = document.getElementById("tabs");
const sectionsEl = document.getElementById("sections");
const themeBtn = document.getElementById("themeBtn");

const logoImg = document.getElementById("logoImg");
const rectImg = document.getElementById("rectImg");


let active = "ВСЕ_ВМ";

const VM_MAP = new Map();

function buildVmMap() {
  VM_MAP.clear();

  DATA.forEach((group, gi) => {
    group.items.forEach((vm, vi) => {
      const key = `${group.category}:${vm.id}:${gi}:${vi}`;

      vm._cat = group.category;
      vm._key = key;

      VM_MAP.set(key, vm);
    });
  });
}

buildVmMap();

/* ===== Theme ===== */
function updateBrand() {
  const isLight = document.body.classList.contains("theme-light");

  if (logoImg) logoImg.src = isLight ? "svg/logo.svg" : "svg/logo_blue.svg";

  if (rectImg) rectImg.src = isLight ? "svg/Rectangle.svg" : "svg/Rectangle1.svg";

}

function applyThemeFromStorage() {
  const saved = localStorage.getItem("gs_theme");
  if (saved === "light") document.body.classList.add("theme-light");
  updateBrand();
}

function toggleTheme() {
  document.body.classList.toggle("theme-light");
  localStorage.setItem(
    "gs_theme",
    document.body.classList.contains("theme-light") ? "light" : "blue"
  );
  updateBrand();
}

if (themeBtn) themeBtn.addEventListener("click", toggleTheme);
applyThemeFromStorage();

/* ===== Icons ===== */
function linuxIconImg() {
  return `<img class="osBadge__icon" src="svg/linux-svgrepo-com.svg" alt="" aria-hidden="true">`;
}
function windowsIconSvg() {
  return `
    <svg class="osBadge__icon" viewBox="0 0 24 24" aria-hidden="true">
      <path fill="currentColor" d="M3 5.5 11 4v7H3V5.5Z"/>
      <path fill="currentColor" d="M13 3.7 21 2v9h-8V3.7Z"/>
      <path fill="currentColor" d="M3 13h8v7.5L3 19V13Z"/>
      <path fill="currentColor" d="M13 13h8v9l-8-1.7V13Z"/>
    </svg>
  `;
}
function svgTerminal() {
  return `
    <svg class="icon" viewBox="0 0 24 24" fill="none" aria-hidden="true">
      <path d="M4 5h16v14H4V5Z" stroke="currentColor" stroke-width="2"/>
      <path d="M7 9l3 3-3 3" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
      <path d="M12 15h5" stroke="currentColor" stroke-width="2" stroke-linecap="round"/>
    </svg>
  `;
}
function svgMonitor() {
  return `
    <svg class="icon" viewBox="0 0 24 24" fill="none" aria-hidden="true">
      <path d="M4 5h16v11H4V5Z" stroke="currentColor" stroke-width="2"/>
      <path d="M9 19h6" stroke="currentColor" stroke-width="2" stroke-linecap="round"/>
      <path d="M12 16v3" stroke="currentColor" stroke-width="2" stroke-linecap="round"/>
    </svg>
  `;
}

/* ===== UI helpers ===== */
function osBadgeHTML(os) {
  if (os === "linux") return `<div class="osBadge">${linuxIconImg()} LINUX</div>`;
  return `<div class="osBadge">${windowsIconSvg()} WINDOWS</div>`;
}
function catBadgeHTML(cat) {
  // Маппинг категорий на CSS классы
  const catMap = {
    "DLP": "dlp",
    "АВЗ": "avz",
    "SIEM": "siem",
    "DC": "pam",
    "МЭ": "me",
    "FS": "nsd",
    "Clients": "clients"
  };
  const catClass = catMap[cat] ? `osBadge--cat-${catMap[cat]}` : "";
  return `<div class="osBadge osBadge--cat ${catClass}">${cat}</div>`;
}

function openSsh(vm) {
  if (!vm.ssh?.enabled || !vm.ssh?.host) {
    console.error("SSH не настроен для этой ВМ");
    return;
  }

  const host = vm.ssh.host;
  const port = vm.ssh.port ?? 22;

  const url = `ssh://${host}:${port}`;
  const cmd = `ssh ${host} -p ${port}`; 

  window.location.href = url;

  setTimeout(() => {
    prompt("Если SSH-клиент не открылся — скопируй команду:", cmd);
  }, 600);
}

function downloadRdp(vm) {
  if (!vm.rdp?.enabled || !vm.rdp?.host) {
    console.error("RDP не настроен для этой ВМ");
    return;
  }

  const host = vm.rdp.host;
  const port = vm.rdp.port ?? 3389;

  const lines = [
    `full address:s:${host}:${port}`,
    `prompt for credentials:i:1`,
  ];

  const content = lines.join("\r\n") + "\r\n";
  const blob = new Blob([content], { type: "application/x-rdp" });

  const a = document.createElement("a");
  a.href = URL.createObjectURL(blob);
  a.download = `${vm._cat}_${vm.id}.rdp`;
  document.body.appendChild(a);
  a.click();
  a.remove();

  setTimeout(() => URL.revokeObjectURL(a.href), 1500);
}

/* ===== Card rendering ===== */
function cardHTML(vm, category) {
  const key = `${category}:${vm.id}`;

  const sshDisabled = vm.ssh?.enabled ? "" : "disabled";
  const rdpDisabled = vm.rdp?.enabled ? "" : "disabled";

  // Если у объекта есть поле info, показываем его вместо кнопок SSH/RDP
  let actionsHTML;
  if (vm.info) {
    if (vm.infoType === "link") {
      // Для PFSENSE - ссылка
      actionsHTML = `<a href="${vm.info}" target="_blank" class="card__info card__info--link">${vm.info}</a>`;
    } else if (vm.infoType === "smb") {
      // Для FS - только окантовка
      actionsHTML = `<div class="card__info card__info--smb">${vm.info}</div>`;
    } else {
      // Стандартный вид
      actionsHTML = `<div class="card__info">${vm.info}</div>`;
    }
  } else {
    actionsHTML = `
      <button class="btn btn--ssh" ${sshDisabled}
        type="button" data-action="ssh" data-key="${vm._key}">
        ${svgTerminal()} SSH
      </button>

      <button class="btn btn--rdp" ${rdpDisabled}
        type="button" data-action="rdp" data-key="${vm._key}">
        ${svgMonitor()} RDP
      </button>
    `;
  }

  return `
    <article class="card">
      <div class="card__top">
        <div class="badgeRow">
          ${osBadgeHTML(vm.os)}
          ${catBadgeHTML(category)}
        </div>
        <div class="card__id">${vm.id}</div>
      </div>

      <div class="card__title">${vm.title}</div>
      <p class="card__desc">${vm.desc}</p>
      ${vm.ip ? `<p class="card__ip">${vm.ip}</p>` : ''}

      <div class="card__actions">
        ${actionsHTML}
      </div>
    </article>
  `;
}

/* ===== Render tabs ===== */
function renderTabs() {
  tabsEl.innerHTML = "";
  CATEGORIES.forEach((cat) => {
    const b = document.createElement("button");
    b.type = "button";
    b.className = "tab" + (cat === active ? " tab--active" : "");
    b.textContent = cat;
    b.addEventListener("click", () => {
      active = cat;
      render();
    });
    tabsEl.appendChild(b);
  });
}

/* ===== Render screens ===== */
function renderAllVMGrid() {
  const all = DATA.flatMap(group => group.items); 

  sectionsEl.innerHTML = `
    <div class="cardsGrid">
      ${all.map(vm => cardHTML(vm, vm._cat)).join("")}
    </div>
  `;
}

function renderByCategory() {
  const list = DATA
    .filter(g => g.category === active)
    .flatMap(g => g.items); 

  sectionsEl.innerHTML = `
    <div class="cardsGrid">
      ${list.map(vm => cardHTML(vm, active)).join("")}
    </div>
  `;
}

/* ===== Click handling ===== */
function handleActions(e) {
  const btn = e.target.closest("button[data-action][data-key]");
  if (!btn) return;
  if (btn.disabled) return;

  const key = btn.dataset.key;
  const vm = VM_MAP.get(key);
  if (!vm) return;

  if (btn.dataset.action === "ssh") openSsh(vm);
  if (btn.dataset.action === "rdp") downloadRdp(vm);
}

sectionsEl.addEventListener("click", handleActions);

/* ===== Main render ===== */
function render() {
  renderTabs();

  if (active === "ВСЕ_ВМ") renderAllVMGrid();
  else renderByCategory();
}

render();
