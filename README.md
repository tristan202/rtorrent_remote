# rTorrent Remote

**rTorrent Remote** is a fast, lightweight, native Windows desktop client for remotely managing [rTorrent](https://github.com/rakshasa/rtorrent) instances via XML-RPC over HTTP/HTTPS. Written in PureBasic, it provides a clean, responsive, qBittorrent-inspired user interface without the overhead of a web browser or Electron wrapper.

---

## ✨ Features

* **Familiar Interface:** Clean layout inspired by qBittorrent/ruTorrent featuring a status sidebar, customizable torrent list, and a detailed bottom inspection panel.
* **Multi-Server Management:** Save and quickly switch between multiple rTorrent servers/seedboxes (e.g., Ultra.cc, Whatbox, self-hosted) with HTTP Basic Authentication and optional SSL certificate bypass.
* **Real-Time Monitoring:** Asynchronous background polling every 3 seconds keeps torrent statuses, speeds, and statistics up to date without freezing the UI.
* **Custom Progress Bars:** Native Windows API custom-drawn progress bars directly inside the torrent list view.
* **Sidebar Filtering & Live Search:** Filter torrents by state (*All, Downloading, Seeding, Completed, Stopped, Active, Inactive, Error*) with live counters, or filter instantly by name via the search box.
* **Detailed Torrent Inspection:** 
  * **General:** Hash, save directory, total size, completed bytes, speeds, ratio, seed time, labels, and tracker status messages.
  * **Trackers:** Tracker URLs, status, seeders, leechers, and download counts.
  * **Peers:** Connected peer IPs, ports, client versions, progress, and individual up/down rates.
  * **Content (Files):** Individual file paths, sizes, chunk progress percentages, and priority levels.
* **Easy Torrent Addition:**
  * Add `.torrent` files via file dialog (`Ctrl+O`) or **Drag & Drop** directly onto the window.
  * Add Magnet links or HTTP `.torrent` URLs (supports batch adding multiple links at once, custom target directory on the server, and start-immediately toggle).
  * Drag & Drop raw magnet text directly into the application.
* **Torrent Control:** Start, Stop, Start All, Stop All, Force Recheck (`d.check_hash`), and Remove torrents.
* **Safe Remote Data Deletion:** Option to delete downloaded files directly from the server when removing a torrent, protected by built-in path validation checks (`SafeDataPath`) to prevent accidental root/directory traversal deletions.
* **Customizable UI & Persistence:**
  * Sort by any column (ascending/descending).
  * Show/hide columns via right-click on the table header and resize column widths.
  * Automatically remembers window size, position, maximize state, multi-monitor placement, sidebar visibility, and column layout in `%APPDATA%\rTorrentRemote\servers.ini`.
* **Single Instance Enforcement:** Prevents multiple instances from running simultaneously and automatically brings the existing window to the foreground.

---

## 🖥️ Server Requirements

Your remote rTorrent instance must expose an XML-RPC endpoint over HTTP or HTTPS (commonly `/RPC2` configured via nginx, Apache, or lighttpd) protected by HTTP Basic Authentication.

Example URL format (e.g., Ultra.cc / seedboxes):
```text
https://username.server.usbx.me/RPC2
```

> **Note on "Delete with data":** Removing a torrent *along with its downloaded data* uses the `execute.nothrow.bg` XML-RPC command (`rm -rf -- <path>`). Your rTorrent configuration must permit `execute` commands over RPC for remote file deletion to work.

---

## 🛠️ Building from Source

### Prerequisites
* **OS:** Windows (x64 recommended)
* **Compiler:** [PureBasic 6.x](https://www.purebasic.com/) (tested with PureBasic 6.40 x64)

### Compiler Options
Before compiling or running from the PureBasic IDE, make sure the following option is enabled:
1. Go to **Compiler > Compiler Options...**
2. Enable **"Create threadsafe executable"** (Required! The program will throw a compiler error if disabled).
3. *(Optional)* Enable **DPI Aware** and **Enable modern theme support (for XP and above)** for crisp rendering on modern displays.

### Command Line Compilation
```bash
pbcompiler "rtorrent_remote.pb" /THREAD /XP /DPIAWARE /EXE "rtorrent_remote.exe"
```

---

## ⌨️ Keyboard Shortcuts

| Shortcut | Action |
| :--- | :--- |
| `Ctrl + O` | Add `.torrent` file(s) |
| `Ctrl + U` | Add Magnet link(s) / URL(s) |
| `Ctrl + B` | Toggle status filter sidebar |
| `F5` | Force immediate refresh from server |
| `Right-click (Row)` | Open torrent action context menu |
| `Right-click (Column Header)` | Toggle visible columns |

---

## 📁 Configuration Storage

All settings, window states, column preferences, and server profiles are stored locally in:
```text
%APPDATA%\rTorrentRemote\servers.ini
```
*(Note: Server passwords are obfuscated in the configuration file for basic privacy, not cryptographically encrypted).*

---

## 📄 License

This project is open source. Feel free to modify and adapt it to your needs.
