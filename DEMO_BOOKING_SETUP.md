# Development-Only Clinic Booking Demo

This guide adds fictional providers, specialties/services, demo hours, and
simulated appointment modes to the two existing clinic listings. It does not
change their real-world addresses, verified hours, actual appointment-mode
flags, or coordinates. The demo providers have reserved `.invalid` email
addresses and no passwords; they are display/booking fixtures, not usable
provider accounts. Never present the demo data as a real clinic offering.

## Start the local services

1. Start PostgreSQL using the existing local service and the database
   configured in the root `.env`. Do not share the `.env` or put its values in
   Flutter settings.
2. From the repository root, start the existing FastAPI app:

   ```powershell
   .\.venv\Scripts\python.exe -m uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
   ```

   Startup creates new tables and runs additive migration
   `004_development_demo_data`. The database and migration preserve all
   existing clinic and appointment records.
3. In a second PowerShell window, seed the two existing clinic listings first
   if they are not already present, then seed demo booking data:

   ```powershell
   .\.venv\Scripts\python.exe -m scripts.seed_clinics
   .\.venv\Scripts\python.exe -m scripts.seed_demo_bookings seed
   ```

   Run the demo seed again whenever needed; it synchronizes its own demo
   records without creating duplicates. Inspect the clinic API at
   `http://127.0.0.1:8000/clinics` or the API docs at
   `http://127.0.0.1:8000/docs`.

## What the seed creates

- Four fictional, clearly labeled provider profiles, two for each existing
  clinic.
- Development-only service categories and provider specializations. These
  names carry a `DEMO` label in API/UI output and participate in service
  filtering.
- Monday-Friday blocks from 09:00-12:00 and 13:00-17:00, with Saturday
  morning blocks for two providers and Sunday closed, in the clinic's
  `Asia/Manila` timezone. Slots are 30 minutes and use the existing
  future-time, exception, and active-booking checks. The lunch interval has no
  available slots.
- A physical/in-person demo type and an online type for each clinic. Online
  mode is explicitly **SIMULATED DEMO ONLY** and never receives a real
  consultation URL or meeting link.

Each clinic's real operating hours and real physical/online support flags
remain unchanged. Demo hours and appointment types are stored separately.
Clinic coordinates remain unset until an exact address can be reliably
verified; do not use approximate coordinates or geocode results for an
unrelated nearby place as a clinic marker.

## Try a demo appointment

1. Run the Flutter app with the API address appropriate to the device. For a
   physical Android phone, use the laptop's current reachable LAN IPv4:

   ```powershell
   flutter run -d <android-device-id> --dart-define=BCKSNAP_API_BASE_URL=http://<LAPTOP_IPV4>:8000
   ```

   `127.0.0.1` is laptop loopback and is not the phone-to-laptop address.
   See [LOCAL_ANDROID_SETUP.md](./LOCAL_ANDROID_SETUP.md) for LAN and firewall
   setup.
2. Sign up/log in as a normal patient using the app's existing account flow.
   Guest accounts cannot book. The seed does not create credentials or a
   receptionist login.
3. Open Clinic Discovery, choose a seeded clinic, then select a provider
   marked `DEMO`. Choose a visit type/date/time and submit. Demo schedules are
   selectable only for demo providers. Demo online bookings are simulated and
   cannot be joined.
4. The request is saved as a normal appointment record flagged `is_demo`.
   Existing ownership, slot-conflict, cancellation, and staff-authorization
   rules still apply. Do not try to approve/reject a request by bypassing staff
   authorization. To exercise staff review, use a properly authorized
   development receptionist through the existing authentication and clinic
   staff setup.
5. Find demo appointments in My Appointments; they show a conspicuous
   development-only warning.

## Remove the demo configuration

Run:

```powershell
.\.venv\Scripts\python.exe -m scripts.seed_demo_bookings cleanup
```

Cleanup removes only records explicitly flagged as demo (demo schedules,
provider profiles and clinic-staff memberships, demo service rows, demo visit
types, separate demo hours, and unreferenced reserved demo user accounts). It
never deletes appointments, clinics, or real clinic service rows. If any demo
account or provider is referenced by an appointment, screening, notification,
or message, cleanup stops before making changes and reports that the records
must be retained.

## Tests

From the repository root, run the targeted backend tests and Flutter checks:

```powershell
.\.venv\Scripts\python.exe -m unittest discover -s tests -p test_demo_bookings.py
flutter test test/clinic_service_test.dart
flutter analyze
```

The test fixture uses an isolated SQLite database and does not seed or alter the
configured PostgreSQL database.
