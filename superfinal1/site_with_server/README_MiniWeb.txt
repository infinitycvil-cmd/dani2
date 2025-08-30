
Mini Web Server (Windows) — Quick Start
=======================================

Files included:
  • Start-MiniWeb.ps1  -> PowerShell server (self-elevates; opens firewall; cleans up on exit)
  • Start-MiniWeb.bat  -> Double‑click to run the PowerShell script with default settings (port 8080)

How to use:
  1) Put these two files in the SAME folder as your website (where index.html lives).
  2) Double‑click Start-MiniWeb.bat  (approve the Admin prompt).
  3) Open a browser on another device in your LAN:   http://<your-LAN-IPv4>:8080/
     Example (from your ipconfig): http://10.0.0.13:8080/
  4) To stop the server, press Ctrl+C in the window.

Make it reachable from the Internet (optional!):
  • Log in to your router (looks like 10.0.0.138 from your ipconfig).
  • Create a Port Forward for TCP 8080 to 10.0.0.13 (your PC).
  • Then use:  http://<your-public-ip>:8080/   (the script tries to show your public IP).
  • Alternatively, if IPv6 is enabled and not blocked, you can try:  http://[your-IPv6]:8080/

Notes:
  • The script adds a temporary Windows Firewall rule and URL reservation and removes them on exit.
  • If port 8080 is busy, edit Start-MiniWeb.bat to change PORT, or run:
        powershell -ExecutionPolicy Bypass -File Start-MiniWeb.ps1 -Port 8000
  • For HTTPS you'll need a certificate and extra setup; this script serves plain HTTP only.
  • Keep your machine secure; exposing home IP to the internet is risky. Prefer a reverse proxy or a VPS for production.
