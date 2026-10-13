# BckSnap: Local Android and Wi-Fi Setup

This guide runs the existing FastAPI backend on the Windows laptop and connects
the Android app over a trusted local network. It does not deploy the server,
open PostgreSQL to the network, add sample clinics, or configure router port
forwarding.

## Addresses: laptop versus phone

- `http://127.0.0.1:8000` is the laptop's loopback address. Use it in a browser
  **on the laptop** to test the backend on that laptop. A phone's `127.0.0.1`
  refers to the phone itself, not the laptop.
- `http://0.0.0.0:8000` is the Uvicorn bind address. It tells the server to
  listen on its available IPv4 interfaces; it is not the address to enter in
  the app/browser.
- `http://192.168.1.134:8000` is the laptop's current LAN address as last
  observed. The physical phone must use the laptop's current address on the
  same reachable home network. This address can change.
- Android emulators use `http://10.0.2.2:8000` to reach the host laptop.
- For a deployed service, use its HTTPS origin via the same Flutter
  `BCKSNAP_API_BASE_URL` setting.

The app centralizes the API origin in `lib/services/api_client.dart`. All
services use this client; do not hardcode per-endpoint URLs. The Flutter define
contains only the API origin, never database credentials or backend secrets.

## 1. Verify PostgreSQL and start the backend

The backend uses the existing private `DATABASE_URL` from the repository-root
`.env`. Do not print, share, or put this file in Flutter configuration. The
PostgreSQL service observed on this machine is `postgresql-x64-18`; check it
without displaying credentials:

```powershell
Get-Service postgresql-x64-18
```

Start it from Windows Services or an administrator PowerShell only if it is
stopped. PostgreSQL should remain local to the backend; do not add an inbound
firewall rule for PostgreSQL's port.

Open PowerShell in the project root and start FastAPI/Uvicorn on all laptop
interfaces at the project's configured API port, **8000**:

```powershell
.\.venv\Scripts\python.exe -m uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

Keep this terminal open while using the phone. `--reload` is for local
development. No router port forwarding is needed or appropriate.

## 2. Verify the server on the laptop

In a second PowerShell window, verify the loopback route first:

```powershell
Invoke-RestMethod http://127.0.0.1:8000/health
```

Expected response:

```json
{"status":"ok","database":"connected"}
```

This health endpoint executes a database `SELECT 1`; a connection error or
HTTP 500 is a backend/database problem, not an empty clinic search. The root
URL `http://127.0.0.1:8000/docs` displays the FastAPI API documentation.

Confirm Uvicorn is listening on the correct interface and port:

```powershell
Get-NetTCPConnection -State Listen -LocalPort 8000 |
  Select-Object LocalAddress, LocalPort
```

With the command above, the listener should show `0.0.0.0` on port `8000`.
A listener only on `127.0.0.1` cannot accept phone connections.

## 3. Find the laptop's current address

Check which adapter is connected to the home network and its IPv4 address:

```powershell
Get-NetAdapter |
  Where-Object Status -eq 'Up' |
  Select-Object Name, Status, LinkSpeed

Get-NetIPAddress -AddressFamily IPv4 |
  Where-Object {
    $_.IPAddress -notlike '127.*' -and
    $_.IPAddress -notlike '169.254.*'
  } |
  Select-Object InterfaceAlias, IPAddress, PrefixLength
```

Use the address for the adapter carrying the connection to the same home
router/network as the phone. `192.168.1.134` was the laptop's observed Ethernet
address, not necessarily its Wi-Fi address or a permanent address. A DHCP
renewal or a network change can assign another IP.

The last inspection found Ethernet up with address `192.168.1.134`, Wi-Fi
disconnected, and the Ethernet network profile set to **Public**. Ethernet and
phone Wi-Fi may still reach one another through the same router, but this
environment's physical phone was observed on Wi-Fi as `192.168.1.2/24`, with a
route through `wlan0` to the laptop's `192.168.1.134` address. A phone-side TCP
probe to port 8000 timed out, and the phone did not receive a ping reply. The
laptop's Ethernet network is Public, Windows Firewall's active inbound default
is Block, and no TCP 8000 inbound allow rule was found. This strongly indicates
inbound firewall filtering, but router wired-to-wireless isolation has not
been ruled out. Matching IP prefixes and a phone route do not guarantee that
the router passes traffic.

During this setup attempt, changing Ethernet to Private was denied. Windows
reported that PowerShell may not be elevated or that Group Policy may prohibit
changing the network category. The profile remains Public and the scoped API
firewall rule was not installed. Retry the profile/rule commands from an
administrator PowerShell only if the network is trusted; if Windows still
denies the profile change, a Windows administrator or the policy owner must
authorize the trusted Private profile. Do not work around this by adding a
Public-profile or unrestricted firewall rule.

## 4. Test the LAN route from the laptop

Replace `<laptop-ipv4>` below with the current address found above:

```powershell
Invoke-RestMethod http://<laptop-ipv4>:8000/health
Test-NetConnection -ComputerName <laptop-ipv4> -Port 8000
Invoke-RestMethod http://<laptop-ipv4>:8000/clinics
```

The health response should report `"database":"connected"`. Clinic search
should return a JSON list. An empty list (`[]`) means the request succeeded but
there are no clinics matching the active search filters; it is different from
a connection timeout. The database currently contains the two supplied Santa
Rosa clinic listings. Neither has verified coordinates or confirmed booking
configuration.

## 5. Test the LAN route from the Android phone

Connect the phone to the same trusted home network (not guest Wi-Fi). Turn off
any phone/laptop VPN temporarily if it routes or blocks local network traffic.
In Chrome **on the phone**, open:

```text
http://<laptop-ipv4>:8000/health
```

Do not enter `127.0.0.1` or `0.0.0.0` on the phone. You need to see
`"database":"connected"` before expecting clinic search in the app to work.

If the laptop's loopback health check succeeds but the phone cannot load this
URL, troubleshoot local routing/firewall, not internet access or clinic data:

1. Verify the current laptop adapter/IP and that Uvicorn is bound to
   `0.0.0.0:8000`.
2. Confirm the phone and laptop are on the same reachable home LAN; guest
   wireless, AP/client isolation, VPNs, wired/wireless VLAN separation, and
   network policy can block them.
3. Check the Windows network category. On this machine, Ethernet is currently
   classified Public, and no matching inbound TCP 8000 allow rule was found.
4. On a **trusted home network only**, an administrator may set the network to
   Private and create a local-subnet-only port rule. First identify the exact
   interface name with `Get-NetConnectionProfile`, then (if trusted) run:

   ```powershell
   Set-NetConnectionProfile -InterfaceAlias "Ethernet" -NetworkCategory Private
   New-NetFirewallRule `
     -DisplayName "BckSnap API (Private LAN)" `
     -Direction Inbound `
     -Action Allow `
     -Protocol TCP `
     -LocalPort 8000 `
     -RemoteAddress LocalSubnet `
     -Profile Private
   ```

   Substitute the actual interface alias if not `Ethernet`. These commands
   require administrator privileges. They do not disable the firewall and
   limit access to TCP 8000 from the local subnet on the Private profile. Do
   not change a public/untrusted network to Private. Do not create an
   unrestricted Public rule.
5. Remove the rule when no longer needed:

   ```powershell
   Remove-NetFirewallRule -DisplayName "BckSnap API (Private LAN)"
   ```

Do not configure router port forwarding or expose the development API or
database to the public internet.

## 6. Build and run Flutter on the physical phone

Enable USB debugging, connect/unlock the phone, and accept its debugging
prompt. Check that Flutter can see it:

```powershell
flutter devices
```

Then, from the project root, use the laptop's **current** LAN IPv4 address:

```powershell
flutter pub get
flutter run -d <android-device-id> --dart-define=BCKSNAP_API_BASE_URL=http://<laptop-ipv4>:8000
```

For the currently observed laptop address, the exact development argument is:

```powershell
flutter run -d <android-device-id> --dart-define=BCKSNAP_API_BASE_URL=http://192.168.1.134:8000
```

The define is read by the shared API client and applies to health, clinic
search, authentication, appointments, screening, and other API calls. The
physical phone must not use the emulator address `10.0.2.2`. On an emulator,
omit the define to use the emulator default, or set it explicitly to
`http://10.0.2.2:8000`. On Windows desktop, the default is
`http://127.0.0.1:8000`. For deployment, set the define to the deployed HTTPS
API origin. The Android cleartext exception is included only by the debug
manifest; release builds should use HTTPS and retain secure platform defaults.

When the laptop address changes, find the new address and update only the
`BCKSNAP_API_BASE_URL` argument for the next run/build. No Flutter source or
database configuration needs to change.

## 7. Understand Clinic Discovery errors

- **Request timeout / cannot reach server:** the selected URL, Uvicorn listener,
  firewall, or LAN route is not reachable. Open the phone's `/health` URL
  first.
- **HTTP 5xx or health reports database failure:** the request reached FastAPI;
  inspect the Uvicorn terminal and PostgreSQL service/configuration.
- **HTTP 401/403:** network and API are reachable; sign-in or authorization
  needs attention.
- **Health succeeds and clinic search returns `[]`:** connectivity works, but
  no current clinic matches the query and filters. The database has two
  supplied Santa Rosa listings; clear filters or search for either clinic name.
- **“No clinics can be mapped”:** clinic data was returned, but its coordinates
  are absent or outside valid latitude/longitude ranges. Use list view and
  correct the real clinic record.

The app performs a health check before clinic search, separates health/network
failures from a successful empty result, and its Retry button resends the
requests. Development logs include only the API origin and HTTP/status code,
not credentials, authorization tokens, or patient data.

## 9. Screening result saving

After a measurement is confirmed, the result page remains available while the
app creates or restores the guest/login session and saves the result. It sends
`POST /screenings` to the configured API origin as multipart form data:

- `angle`: the measured angle in degrees.
- `photo`: optional image file captured or selected during screening.
- `Idempotency-Key`: a per-attempt request key used to make retries safe.

The endpoint requires the app's bearer-token session. A successful response is
returned only after the screening row commits to the existing database. The
result page shows **Saved** only after receiving that response; on a timeout,
validation error, authentication failure, or server error it keeps the result
visible as **Not yet saved** and offers **Retry Save**. A retry uses the same
request key, so a request that reached the server before a lost response does
not create a second row. The pending measurement/photo stay in memory on that
result page; they are not written to an additional local health-data queue.

If saving fails, first open `http://<laptop-ipv4>:8000/health` on the phone.
Then check the app's API define and Uvicorn terminal. HTTP 401 means the
session needs attention, HTTP 422 indicates invalid form data, HTTP 5xx means
the backend/database failed, and a timeout means the phone did not receive a
response in time. Clinic discovery is independent: a failed clinic request
does not prevent saving, and a successful empty clinic search does not indicate
a screening-save failure.
