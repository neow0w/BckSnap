import unittest
from datetime import date, datetime, time, timedelta, timezone

import httpx
from sqlalchemy import create_engine, func, select
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.booking import available_slots
from app.database import Base, get_db
from app.main import app
from app.models import (
    Appointment,
    Clinic,
    ClinicService,
    DemoAppointmentType,
    DoctorProfile,
    DoctorSchedule,
    User,
)
from scripts.seed_demo_bookings import (
    DEMO_CLINIC_NAMES,
    cleanup_demo_bookings,
    seed_demo_bookings,
)
from app.security import create_access_token


class DemoBookingSeedTests(unittest.TestCase):
    def setUp(self):
        self.engine = create_engine("sqlite://")
        Base.metadata.create_all(self.engine)
        self.sessions = sessionmaker(self.engine, expire_on_commit=False)
        with self.sessions() as db:
            db.add_all(
                [
                    Clinic(
                        name=name,
                        address="Demo test address",
                        timezone="Asia/Manila",
                        operating_hours=None,
                        supports_online=False,
                        supports_physical=False,
                    )
                    for name in DEMO_CLINIC_NAMES
                ]
            )
            db.commit()

    def tearDown(self):
        Base.metadata.drop_all(self.engine)
        self.engine.dispose()

    def test_seed_is_repeatable_and_cleanup_removes_only_demo_configuration(self):
        with self.sessions() as db:
            seed_demo_bookings(db)
            seed_demo_bookings(db)
            self.assertEqual(
                db.scalar(select(func.count()).select_from(DoctorProfile)), 4
            )
            self.assertEqual(
                db.scalar(select(func.count()).select_from(DoctorSchedule)), 84
            )
            self.assertEqual(
                db.scalar(select(func.count()).select_from(DemoAppointmentType)), 4
            )
            self.assertEqual(
                db.scalar(
                    select(func.count()).select_from(ClinicService).where(
                        ClinicService.is_demo.is_(True)
                    )
                ),
                4,
            )
            for clinic in db.scalars(select(Clinic)).all():
                self.assertIsNone(clinic.operating_hours)
                self.assertFalse(clinic.supports_online)
                self.assertFalse(clinic.supports_physical)
                self.assertEqual(
                    clinic.demo_operating_hours["monday"],
                    [
                        {"open": "09:00", "close": "12:00"},
                        {"open": "13:00", "close": "17:00"},
                    ],
                )
                self.assertEqual(clinic.demo_operating_hours["sunday"], [])

            doctor = db.scalar(select(DoctorProfile).where(DoctorProfile.is_demo.is_(True)))
            clinic = db.get(Clinic, doctor.clinic_id)
            booking_day = date.today() + timedelta(days=8)
            while booking_day.weekday() > 4:
                booking_day += timedelta(days=1)
            slots = available_slots(db, clinic, doctor, booking_day, "online")
            self.assertTrue(slots)
            for slot in slots:
                local_time = slot.starts_at.astimezone(
                    timezone(timedelta(hours=8))
                ).time()
                self.assertFalse(time(12) <= local_time < time(13))

            cleanup_demo_bookings(db)
            self.assertEqual(
                db.scalar(select(func.count()).select_from(DoctorProfile)), 0
            )
            self.assertEqual(
                db.scalar(
                    select(func.count()).select_from(User).where(User.is_demo.is_(True))
                ),
                0,
            )
            self.assertEqual(
                db.scalar(select(func.count()).select_from(DoctorSchedule)), 0
            )
            self.assertEqual(
                db.scalar(select(func.count()).select_from(DemoAppointmentType)), 0
            )
            self.assertEqual(
                db.scalar(
                    select(func.count()).select_from(ClinicService).where(
                        ClinicService.is_demo.is_(True)
                    )
                ),
                0,
            )
            self.assertTrue(
                all(
                    clinic.demo_operating_hours is None
                    for clinic in db.scalars(select(Clinic)).all()
                )
            )

    def test_cleanup_refuses_to_remove_demo_providers_referenced_by_appointments(self):
        with self.sessions() as db:
            doctors = seed_demo_bookings(db)
            demo_doctor = doctors[0]
            appointment = Appointment(
                user_id=demo_doctor.user_id,
                clinic_id=demo_doctor.clinic_id,
                doctor_id=demo_doctor.id,
                reference="BS-DEMO1",
                status="pending",
                mode="physical",
                scheduled_at=datetime.now(timezone.utc) + timedelta(days=10),
                is_demo=True,
            )
            db.add(appointment)
            db.commit()

            with self.assertRaisesRegex(RuntimeError, "never deletes"):
                cleanup_demo_bookings(db)

            self.assertIsNotNone(db.get(Appointment, appointment.id))
            self.assertTrue(db.get(DoctorProfile, demo_doctor.id).is_demo)


class DemoBookingApiTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.engine = create_engine(
            "sqlite://",
            connect_args={"check_same_thread": False},
            poolclass=StaticPool,
        )
        Base.metadata.create_all(self.engine)
        self.sessions = sessionmaker(self.engine, expire_on_commit=False)
        with self.sessions() as db:
            db.add_all(
                [
                    Clinic(
                        name=name,
                        address="Demo test address",
                        timezone="Asia/Manila",
                        operating_hours=None,
                        supports_online=False,
                        supports_physical=False,
                    )
                    for name in DEMO_CLINIC_NAMES
                ]
            )
            db.flush()
            self.doctor = seed_demo_bookings(db)[0]
            self.clinic_id = self.doctor.clinic_id
            self.doctor_id = self.doctor.id
            patient = User(
                name="Test Patient",
                email="patient@example.invalid",
                role="user",
                is_guest=False,
            )
            db.add(patient)
            db.commit()
            self.patient_id = patient.id

        def override_get_db():
            with self.sessions() as db:
                yield db

        self.previous_override = app.dependency_overrides.get(get_db)
        app.dependency_overrides[get_db] = override_get_db
        self.client = httpx.AsyncClient(
            transport=httpx.ASGITransport(app=app), base_url="http://test"
        )
        self.headers = {
            "Authorization": f"Bearer {create_access_token(self.patient_id)}"
        }
        self.booking_day = date.today() + timedelta(days=8)
        while self.booking_day.weekday() > 4:
            self.booking_day += timedelta(days=1)

    async def asyncTearDown(self):
        await self.client.aclose()
        if self.previous_override is None:
            app.dependency_overrides.pop(get_db, None)
        else:
            app.dependency_overrides[get_db] = self.previous_override
        Base.metadata.drop_all(self.engine)
        self.engine.dispose()

    async def test_demo_services_filter_and_appointment_booking_are_marked(self):
        clinics = await self.client.get(
            "/clinics", params={"service": "Orthopedics", "mode": "online"}
        )
        self.assertEqual(clinics.status_code, 200, clinics.text)
        self.assertEqual(len(clinics.json()), 1)
        clinic = clinics.json()[0]
        self.assertTrue(clinic["demo_appointment_types"][0]["simulation_only"])
        self.assertFalse(clinic["supports_online"])

        slots_response = await self.client.get(
            f"/clinics/{self.clinic_id}/slots",
            params={
                "doctor_id": self.doctor_id,
                "on": self.booking_day.isoformat(),
                "mode": "online",
            },
        )
        self.assertEqual(slots_response.status_code, 200, slots_response.text)
        slots = slots_response.json()
        self.assertTrue(slots)
        local_times = [
            datetime.fromisoformat(slot["starts_at"])
            .astimezone(timezone(timedelta(hours=8)))
            .time()
            for slot in slots
        ]
        self.assertTrue(all(not time(12) <= slot < time(13) for slot in local_times))

        first_slot = slots[0]
        booking = await self.client.post(
            "/appointments",
            headers=self.headers,
            json={
                "clinic_id": self.clinic_id,
                "doctor_id": self.doctor_id,
                "mode": "online",
                "scheduled_at": first_slot["starts_at"],
            },
        )
        self.assertEqual(booking.status_code, 201, booking.text)
        self.assertTrue(booking.json()["is_demo"])

        duplicate = await self.client.post(
            "/appointments",
            headers=self.headers,
            json={
                "clinic_id": self.clinic_id,
                "doctor_id": self.doctor_id,
                "mode": "online",
                "scheduled_at": first_slot["starts_at"],
            },
        )
        self.assertEqual(duplicate.status_code, 409, duplicate.text)

    async def test_real_provider_cannot_use_demo_hours_or_demo_visit_types(self):
        with self.sessions() as db:
            real_user = User(
                name="Real Test Provider",
                email="real.provider@example.invalid",
                role="doctor",
                is_guest=False,
            )
            db.add(real_user)
            db.flush()
            real_doctor = DoctorProfile(
                clinic_id=self.clinic_id,
                user_id=real_user.id,
                supports_online=False,
                supports_physical=False,
                is_demo=False,
            )
            db.add(real_doctor)
            db.commit()
            real_doctor_id = real_doctor.id

        response = await self.client.get(
            f"/clinics/{self.clinic_id}/slots",
            params={
                "doctor_id": real_doctor_id,
                "on": self.booking_day.isoformat(),
                "mode": "online",
            },
        )
        self.assertEqual(response.status_code, 200, response.text)
        self.assertEqual(response.json(), [])


if __name__ == "__main__":
    unittest.main()
