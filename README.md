# BckSnap

BckSnap is a Flutter app with a FastAPI backend and PostgreSQL persistence for
clinic discovery, appointments, in-app notifications, screening, and messaging.

## Prerequisites

- Flutter and Dart (Dart SDK `^3.13.5`)
- Python 3.11 or newer
- PostgreSQL
- Android Studio and Android SDK when targeting Android

Check the Flutter platform toolchain with `flutter doctor -v`.

## Database and API setup

Create a PostgreSQL application role and database if they do not already exist.
Use your own local password:

```sql
CREATE ROLE bcksnap_app LOGIN PASSWORD 'replace-with-a-local-password';
CREATE DATABASE bcksnap OWNER bcksnap_app;
```

Copy `.env.example` to `.env`, then set `DATABASE_URL` to those credentials
and replace `SECRET_KEY` with a long, randomly generated value. Keep `.env`
local; it is ignored by Git. Optional `CONSULTATION_URL_TEMPLATE` must be an
actual HTTPS meeting-provider URL template containing `{reference}`. If a
provider does not use that format, clinic staff can supply its real meeting URL
when approving an online appointment.

Install the pinned API dependencies and start the backend in PowerShell from
the repository root:

```powershell
py -3.11 -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
.\.venv\Scripts\python.exe -m uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

The API reads `.env` from the repository root, including when started from the
`app` directory (`python -m uvicorn main:app --reload`). At startup it creates
new tables and applies the versioned, additive clinic-booking migration. The
migration preserves existing records and adds nullable clinic-booking fields
to old appointments. Account-registration migration 005 adds nullable profile
fields for existing users and a case-insensitive unique email index without
rewriting legacy names or deleting accounts. If legacy records contain email
addresses that differ only by case, startup stops with an explicit migration
error so those records can be reconciled deliberately. Verify the API/database with
<http://127.0.0.1:8000/health>; inspect and exercise the API at
<http://127.0.0.1:8000/docs>.

### Account registration

Create Account is available from Login, the signed-in/guest Home screen, and
the first photo-selection action in the screening flow. The screening prompt
also offers Log In, Cancel, and an explicit Continue as guest option. Guest
screening remains available; upgrading a guest to an account preserves that
user's existing screenings.

Registration is submitted to `POST /auth/signup`. It collects first and last
name, optional middle initial, birthdate, address, gender, email, Philippine
mobile number, password, and confirmation. The API normalizes email and mobile
numbers, validates input, and stores only a bcrypt password hash. Existing
legacy user rows continue to work with their original `name`; newly registered
accounts also populate that field for compatibility. Structured profile
details are returned only through the authenticated user's profile response
and existing authorized staff patient views.

For a physical Android phone, the backend must listen on `0.0.0.0` (as in the
command above), and the phone and laptop must be on the same reachable home
network. Ethernet on the laptop can work with Wi-Fi on the phone when both
connect to the same router/subnet. Find the laptop address on the adapter
connected to that network:

```powershell
Get-NetIPAddress -AddressFamily IPv4 |
  Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' } |
  Select-Object InterfaceAlias, IPAddress
```

At the time this guide was updated, the laptop address was `192.168.1.134` on
Ethernet; it may change when DHCP renews or the laptop switches networks.
Re-run the command each time and use the IPv4 address of the adapter connected
to the same home network as the phone. The current Ethernet network is
classified as **Public** in Windows. Check its current profile with
`Get-NetConnectionProfile`. No firewall rule is added automatically. From the
phone's browser, open
`http://192.168.1.134:8000/health`. A successful response includes
`"database":"connected"`. Then run Flutter with the same current laptop address:

```powershell
flutter devices
flutter run -d <android-device-id> --dart-define=BCKSNAP_API_BASE_URL=http://192.168.1.134:8000
```

The compile-time `BCKSNAP_API_BASE_URL` setting centralizes the API address;
only the run command changes when the laptop's DHCP address changes. The API
client and individual endpoints do not need source edits.
Android emulators use `http://10.0.2.2:8000` by default; physical Android
devices must use the laptop's reachable LAN IPv4 address. Windows, web, and
iOS simulators use `http://127.0.0.1:8000` by default. Set the same define to
the deployed HTTPS origin for deployment, e.g.
`--dart-define=BCKSNAP_API_BASE_URL=https://api.example.invalid`.

HTTP cleartext is enabled only through the Android debug manifest/network
security configuration. Release builds retain Android's secure default and
must use HTTPS. If Windows Firewall blocks the LAN request, first ensure the
network is a trusted private network before changing its profile. On a trusted
home/development network, an administrator may classify the active Ethernet
profile as Private and create a scoped inbound rule. Do not do this on a public
or untrusted network:

```powershell
Set-NetConnectionProfile -InterfaceAlias "Ethernet" -NetworkCategory Private
New-NetFirewallRule -DisplayName "BckSnap API (Private LAN)" -Direction Inbound -Action Allow -Protocol TCP -LocalPort 8000 -RemoteAddress LocalSubnet -Profile Private
```

This permits only TCP 8000 from the local subnet on the Private profile. Remove
the rule when development access is no longer needed:

```powershell
Remove-NetFirewallRule -DisplayName "BckSnap API (Private LAN)"
```

Do not disable Windows Firewall or add a broad inbound rule. If the laptop
`/health` works but the phone cannot open it, check the selected IPv4 address,
the active firewall profile/rule, and whether the Wi-Fi access point isolates
wireless clients. Guest Wi-Fi, client/AP isolation, VPN software, and router or
organization network policies can prevent phone-to-laptop connections. Do not
configure router port forwarding or expose this development server to the
public internet.

### Quick local test checklist

1. Connect the phone and laptop to the same trusted home LAN; turn off VPNs
   temporarily if they route local traffic away from that LAN.
2. In the repository root, start the API using the command above.
3. On the laptop, verify `http://127.0.0.1:8000/health` in a browser, then
   verify `http://<current-laptop-ipv4>:8000/health`.
4. If the LAN address works on the laptop but not the phone, check the active
   Windows network profile and add only the scoped Private-profile firewall
   rule above, then retry the phone browser health URL.
5. Run `flutter devices` and launch using
   `--dart-define=BCKSNAP_API_BASE_URL=http://<current-laptop-ipv4>:8000`.
6. Open Clinic Discovery. A server/health failure has a Retry button; a
   successful empty search is shown separately and means no clinic matches
   the current query and filters. Two supplied Santa Rosa listings are
   currently provisioned.

## Provision real clinic data

The supplied Santa Rosa clinic listings can be added to the configured database
with the repeatable seed command below. It records only the supplied names,
addresses, phone numbers, and supplied physical-therapy/rehabilitation
categories; it does not add coordinates, doctors, hours, confirmed appointment
types, schedules, or meeting links. The MEDI-SKY listing marks its category as
unverified and does not claim specific services or specialties. The seed
preserves any coordinates or appointment configuration added later by
authorized staff.

```powershell
.\.venv\Scripts\python.exe -m scripts.seed_clinics
```

For clearly labeled fictional providers, isolated demo hours and visit modes,
and safe repeatable demo cleanup, see
[DEMO_BOOKING_SETUP.md](./DEMO_BOOKING_SETUP.md). Demo data does not alter the
clinics' real hours, appointment options, or coordinates.

Run it again safely to synchronize the supplied listing details without
duplicating clinic rows. Clinics remain searchable without coordinates, but
are omitted from distance-filtered searches and map markers until coordinates
are verified.

1. Sign up a staff account through `/auth/signup`.
2. Using the PostgreSQL administrator account, grant the designated clinic
   receptionist role:

   ```sql
   UPDATE users SET role = 'receptionist'
   WHERE email = 'the-staff-account@example.com';
   ```

3. Log in as that receptionist. In `/docs`, authorize requests with the access
   token and create a clinic with `POST /clinics`. Supply its verified address,
   coordinates, IANA timezone (for example `Asia/Manila`), actual operating
   hours, visit types, and services. Clinic creation also assigns that
   receptionist to the clinic.
4. Create each doctor's account through signup. Using the database administrator
   account, set each authorized account's `users.role` to `doctor`. The
   receptionist can then assign it with `POST /clinics/{clinic_id}/doctors`
   and publish the doctor's actual availability with
   `PUT /clinics/{clinic_id}/doctors/{doctor_id}/schedules`.
5. Add actual schedule exceptions when needed with
   `POST /clinics/{clinic_id}/doctors/{doctor_id}/exceptions`.

Only clinic staff assigned to that clinic can approve or reject its appointment
requests. Do not use example locations, credentials, schedules, or meeting
URLs as real provider data.

## Location and maps

Clinic maps and manual place search use OpenStreetMap data, with attribution
displayed in the app. Manual address searches are sent to the public Nominatim
geocoder through the API; requests are cached and throttled, and require
internet access. No map API key is required. Device location is requested only
after the user chooses to use it. If permission is denied or unavailable,
manual place search remains available. Browsers may require HTTPS or localhost
for geolocation.

## Run Flutter

```powershell
flutter pub get
flutter run -d windows
```

Use `flutter devices` to choose a target. See the physical Android instructions
above when running on a phone.

For a step-by-step physical Android setup and network troubleshooting, see
[LOCAL_ANDROID_SETUP.md](./LOCAL_ANDROID_SETUP.md).

## Validation

```powershell
.venv\Scripts\python.exe -m unittest discover -s tests -v
dart format lib test
flutter analyze
flutter test
```

Notifications are persisted in-app; push delivery is not configured. Online
consultation access is available only when staff supplies a real HTTPS meeting
URL or an actual meeting-provider URL template is configured.
