# Torrentry

**Torrentry** is a fast, lightweight, native Windows desktop client for remotely managing torrent clients on your seedbox or home server. It supports **rTorrent**, **qBittorrent**, **Transmission** and **Deluge** from one qBittorrent-inspired interface. It is written in PureBasic and needs no web browser, Electron wrapper or runtime.

> **Note:** The user interface is currently in Danish.

*Formerly known as rTorrent Remote. Existing settings are carried over automatically on first start.*

---

## ✨ Features

* **One app, four clients:** rTorrent (XML-RPC), qBittorrent (WebUI API v2), Transmission (JSON-RPC) and Deluge (Web UI JSON-RPC). Choose the client type per server.
* **Familiar interface:** Status sidebar, customizable torrent list and a detailed bottom inspection panel.
* **Multi-server management:** Save several servers or seedboxes (e.g. Ultra.cc, Whatbox, self-hosted), even with different clients, and switch between them from the toolbar. Optionally ignore SSL certificate errors.
* **Real-time monitoring:** Background polling keeps statuses, speeds and statistics up to date without freezing the UI.
* **Custom progress bars:** Drawn directly inside the torrent list.
* **Sidebar filtering & live search:** Filter by state (*All, Downloading, Seeding, Completed, Stopped, Active, Inactive, Error*) with live counters, or by name via the search box. Toggle the sidebar with `Ctrl+B`.
* **Detailed torrent inspection:**
  * **General:** Hash, save location, size, downloaded, progress, status, ratio, totals, seed time, label/category and error messages.
  * **Trackers:** URLs, status, seeders, leechers and download counts (where the client provides them).
  * **Peers:** IPs (IPv4 and IPv6), ports, client names, progress and up/down rates.
  * **Content:** Files with size, progress and priority.
* **Easy torrent addition:**
  * Add `.torrent` files via file dialog (`Ctrl+O`) or drag & drop onto the window.
  * Add magnet links or `.torrent` URLs (`Ctrl+U`), several at once, with an optional target folder on the server and a "start immediately" option.
  * Drag magnet text straight into the window.
* **Torrent control:** Start, Stop, Start all, Stop all and Recheck from the menu, the icon toolbar or the right-click menu.
* **Delete submenu:** *Delete torrent* or *Delete torrent + data*. Deleting data asks for confirmation first.
* **Customizable UI & persistence:** Sort by any column, show/hide and resize columns (right-click the header). Window size, position (multi-monitor aware), sidebar visibility and column layout are remembered.
* **Portable mode:** Keep settings next to the exe instead of in `%APPDATA%`.
* **Single instance:** Launching it again brings the existing window to the front.

---

## 🖥️ Server Setup

Open **Server → Administrer servere…**, click **Ny**, pick the **Klient** type and fill in the URL and login. If you leave out the path, Torrentry adds the client's usual one.

| Client | Example URL | Login |
| :--- | :--- | :--- |
| rTorrent | `https://username.server.usbx.me/RPC2` | HTTP Basic Auth (username + password) |
| qBittorrent | `https://username.server.usbx.me/qbittorrent` | WebUI username + password |
| Transmission | `https://username.server.usbx.me/transmission/rpc` | RPC username + password |
| Deluge | `https://username.server.usbx.me/deluge` | Web UI password only |

Use **Server → Test forbindelse** to check the connection; it shows the client version and default download folder.

> **rTorrent and "Delete torrent + data":** rTorrent has no built-in delete-with-data, so Torrentry runs `rm -rf -- <path>` through `execute.nothrow.bg` after validating the path. Your rTorrent configuration must allow `execute` commands over RPC. The other clients delete data themselves.
>
> **qBittorrent:** qBittorrent bans an IP address for a while after too many failed logins.
>
> **Deluge:** If the Web UI is not connected to a daemon, Torrentry connects it to the first one in its host list.

---

## 📦 Installation

Download a release and either:

* run **`Torrentry-<version>-setup.exe`** (all users or just you, optional desktop shortcut), or
* extract **`Torrentry-<version>-portable.zip`** anywhere. Settings are stored in `servers.ini` next to the program while `portable.txt` is present.

Requires Windows x64.

---

## 🛠️ Building from Source

### Prerequisites
* **OS:** Windows (x64 recommended)
* **Compiler:** [PureBasic 6.x](https://www.purebasic.com/) (tested with PureBasic 6.40 x64)
* **Installer (optional):** [Inno Setup 6](https://jrsoftware.org/isinfo.php)

### Compiler Options
In the PureBasic IDE (**Compiler > Compiler Options...**):
1. Enable **"Create threadsafe executable"** (required; the program refuses to compile without it).
2. *(Optional)* Enable **DPI Aware** and **modern theme support** for crisp rendering.

### Command Line
```bash
pbcompiler "torrentry.pb" /THREAD /XP /DPIAWARE /ICON "torrentry.ico" /EXE "torrentry.exe"
```

`build.cmd` compiles the program and builds both the installer and the portable zip in `dist\`.

### Code Layout
| File | Purpose |
| :--- | :--- |
| `torrentry.pb` | User interface |
| `backend.pbi` | Shared types and `Backend_*` procedures the UI calls |
| `backend_rtorrent.pbi` | rTorrent (XML-RPC) |
| `backend_qbittorrent.pbi` | qBittorrent (WebUI API v2) |
| `backend_transmission.pbi` | Transmission (JSON-RPC) |
| `backend_deluge.pbi` | Deluge (Web UI JSON-RPC) |

---

## ⌨️ Keyboard Shortcuts

| Shortcut | Action |
| :--- | :--- |
| `Ctrl + O` | Add `.torrent` file(s) |
| `Ctrl + U` | Add magnet link(s) / URL(s) |
| `Ctrl + B` | Toggle status filter sidebar |
| `F5` | Refresh from server now |
| `Right-click (row)` | Torrent context menu |
| `Right-click (column header)` | Show/hide columns |

---

## 📁 Configuration Storage

Settings, window state, column preferences and server profiles are stored in:
```text
%APPDATA%\Torrentry\servers.ini
```
or next to `torrentry.exe` in portable mode. *Server passwords are obfuscated in this file, not encrypted.*

---

## 📄 License

This project is open source. Feel free to modify and adapt it to your needs.
