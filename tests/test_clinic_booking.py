import unittest
from datetime import date, datetime, time, timedelta, timezone

import httpx
from sqlalchemy import create_engine, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, sessionmaker
from sqlalchemy.pool import StaticPool

from app.database import Base, get_db
from app.main import app
from app.models import (
    Appointment,
    Clinic,
    ClinicService,
    ClinicStaff,
    DoctorProfile,
    DoctorSchedule,
    Notification,
    ScheduleException,
    User,
)
from app.security import create_access_token


class ClinicBookingTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.engine = create_engine(
            "sqlite://",
            connect_args={"check_same_thread": False},
            poolclass=StaticPool,
        )
        Base.metadata.create_all(self.engine)
        self.sessions = sessionmaker(self.engine, expire_on_commit=False)

        with self.sessions() as db:
            self.patient = User(
                name="Test Patient",
                email="patient@example.invalid",
                role="user",
                is_guest=False,
            )
            self.other_patient = User(
                name="Other Patient",
                email="other@example.invalid",
                role="user",
                is_guest=False,
            )
            self.receptionist = User(
                name="Test Receptionist",
                email="reception@example.invalid",
                role="receptionist",
                is_guest=False,
            )
            self.doctor_user = User(
                name="Test Doctor",
                email="doctor@example.invalid",
                role="doctor",
                is_guest=False,
            )
            db.add_all(
                [self.patient, self.other_patient, self.receptionist, self.doctor_user]
            )
            db.flush()
            self.clinic = Clinic(
                name="Verified Test Clinic",
                address="10 Test Street",
                latitude=14.5995,
                longitude=120.9842,
                timezone="UTC",
                operating_hours={
                    day: {"open": "00:00", "close": "23:59"}
                    for day in (
                        "monday",
                        "tuesday",
                        "wednesday",
                        "thursday",
                        "friday",
                        "saturday",
                        "sunday",
                    )
                },
                supports_online=True,
                supports_physical=True,
            )
            db.add(self.clinic)
            db.flush()
            self.doctor = DoctorProfile(
                clinic_id=self.clinic.id,
                user_id=self.doctor_user.id,
                specializations=["orthopedics"],
                supports_online=True,
                supports_physical=True,
            )
            db.add_all(
                [
                    ClinicService(
                        clinic_id=self.clinic.id,
                        name="Spine care",
                        specialization="orthopedics",
                    ),
                    ClinicStaff(
                        clinic_id=self.clinic.id,
                        user_id=self.receptionist.id,
                        role="receptionist",
                    ),
                ]
            )
            db.add(self.doctor)
            db.flush()
            self.doctor_id = self.doctor.id
            self.clinic_id = self.clinic.id
            self.patient_id = self.patient.id
            self.other_patient_id = self.other_patient.id
            self.receptionist_id = self.receptionist.id
            on = date.today() + timedelta(days=3)
            db.add(
                DoctorSchedule(
                    doctor_id=self.doctor.id,
                    weekday=on.weekday(),
                    start_time=time(9),
                    end_time=time(12),
                    duration_minutes=30,
                    mode="online",
                )
            )
            db.add(
                DoctorSchedule(
                    doctor_id=self.doctor.id,
                    weekday=on.weekday(),
                    start_time=time(9),
                    end_time=time(12),
                    duration_minutes=30,
                    mode="physical",
                )
            )
            db.commit()

        def override_get_db():
            with self.sessions() as db:
                yield db

        self.previous_override = app.dependency_overrides.get(get_db)
        app.dependency_overrides[get_db] = override_get_db
        self.client = httpx.AsyncClient(
            transport=httpx.ASGITransport(app=app), base_url="http://test"
        )

    async def asyncTearDown(self):
        await self.client.aclose()
        if self.previous_override is None:
            app.dependency_overrides.pop(get_db, None)
        else:
            app.dependency_overrides[get_db] = self.previous_override
        Base.metadata.drop_all(self.engine)
        self.engine.dispose()

    def auth(self, user_id: int) -> dict[str, str]:
        return {"Authorization": f"Bearer {create_access_token(user_id)}"}

    async def slots(self, mode: str = "online") -> list[dict]:
        on = (date.today() + timedelta(days=3)).isoformat()
        response = await self.client.get(
            f"/clinics/{self.clinic_id}/slots",
            params={"doctor_id": self.doctor_id, "on": on, "mode": mode},
        )
        self.assertEqual(response.status_code, 200, response.text)
        return response.json()

    async def book(self, headers: dict[str, str], slot: dict | None = None):
        if slot is None:
            slot = (await self.slots())[0]
        return await self.client.post(
            "/appointments",
            headers=headers,
            json={
                "clinic_id": self.clinic_id,
                "doctor_id": self.doctor_id,
                "mode": slot["mode"],
                "scheduled_at": slot["starts_at"],
            },
        )

    async def test_search_details_and_actual_schedule_slots(self):
        clinics = await self.client.get(
            "/clinics",
            params={
                "q": "Verified",
                "service": "spine",
                "mode": "online",
                "latitude": 14.59,
                "longitude": 120.98,
            },
        )
        self.assertEqual(clinics.status_code, 200, clinics.text)
        self.assertEqual([clinic["id"] for clinic in clinics.json()], [self.clinic_id])
        self.assertGreater(clinics.json()[0]["distance_km"], 0)
        details = await self.client.get(f"/clinics/{self.clinic_id}")
        self.assertEqual(details.status_code, 200)
        self.assertEqual(details.json()["doctors"][0]["name"], "Test Doctor")
        self.assertTrue(await self.slots())

    async def test_partial_schedule_exception_blocks_overlapping_slot(self):
        on = date.today() + timedelta(days=3)
        with self.sessions() as db:
            db.add(
                ScheduleException(
                    doctor_id=self.doctor_id,
                    exception_date=on,
                    start_time=time(9),
                    end_time=time(9, 30),
                    reason="Unavailable",
                )
            )
            db.commit()

        slots = await self.slots()
        starts = {
            datetime.fromisoformat(slot["starts_at"]).time().replace(tzinfo=None)
            for slot in slots
        }
        self.assertNotIn(time(9), starts)
        self.assertIn(time(9, 30), starts)

    async def test_full_day_schedule_exception_removes_all_slots(self):
        on = date.today() + timedelta(days=3)
        with self.sessions() as db:
            db.add(
                ScheduleException(
                    doctor_id=self.doctor_id,
                    exception_date=on,
                    reason="Clinic closed",
                )
            )
            db.commit()

        self.assertEqual(await self.slots(), [])

    async def test_booking_is_pending_persisted_and_not_double_booked(self):
        headers = self.auth(self.patient_id)
        slot = (await self.slots())[0]
        booked = await self.book(headers, slot)
        self.assertEqual(booked.status_code, 201, booked.text)
        self.assertEqual(booked.json()["status"], "pending")
        self.assertTrue(booked.json()["reference"].startswith("BS-"))
        self.assertIsNotNone(booked.json()["created_at"])
        self.assertIsNotNone(booked.json()["updated_at"])
        self.assertEqual(len((await self.client.get("/appointments/mine", headers=headers)).json()), 1)

        duplicate = await self.book(headers, slot)
        self.assertEqual(duplicate.status_code, 409, duplicate.text)

        other = await self.client.get(
            f"/appointments/{booked.json()['id']}",
            headers=self.auth(self.other_patient_id),
        )
        self.assertEqual(other.status_code, 404)

    async def test_unique_database_constraint_rejects_parallel_slot_reservation(self):
        headers = self.auth(self.patient_id)
        result = await self.book(headers)
        self.assertEqual(result.status_code, 201, result.text)
        values = result.json()
        with self.sessions() as db:
            duplicate = Appointment(
                user_id=self.patient_id,
                clinic_id=self.clinic_id,
                doctor_id=self.doctor_id,
                reference="BS-SECOND-BOOKING",
                mode=values["mode"],
                scheduled_at=datetime.fromisoformat(values["scheduled_at"]),
                status="pending",
            )
            db.add(duplicate)
            with self.assertRaises(IntegrityError):
                db.commit()
            db.rollback()

    async def test_cancellation_requires_reason_and_24_hours_then_notifies_staff(self):
        headers = self.auth(self.patient_id)
        booked = await self.book(headers)
        self.assertEqual(booked.status_code, 201, booked.text)

        no_reason = await self.client.post(
            f"/appointments/{booked.json()['id']}/cancel",
            headers=headers,
            json={"reason": "   "},
        )
        self.assertEqual(no_reason.status_code, 422)

        cancelled = await self.client.post(
            f"/appointments/{booked.json()['id']}/cancel",
            headers=headers,
            json={"reason": "Schedule conflict"},
        )
        self.assertEqual(cancelled.status_code, 200, cancelled.text)
        self.assertEqual(cancelled.json()["status"], "cancelled")
        self.assertEqual(cancelled.json()["cancellation_reason"], "Schedule conflict")

        staff_notifications = await self.client.get(
            "/appointments/notifications/mine",
            headers=self.auth(self.receptionist_id),
        )
        self.assertEqual(staff_notifications.status_code, 200)
        self.assertEqual(staff_notifications.json()[0]["event_type"], "cancelled")
        released = await self.slots()
        self.assertGreater(len(released), 0)

    async def test_approval_notification_and_consultation_access_control(self):
        booked = await self.book(self.auth(self.patient_id))
        self.assertEqual(booked.status_code, 201, booked.text)
        appointment_id = booked.json()["id"]

        approved = await self.client.patch(
            f"/appointments/{appointment_id}/approve",
            headers=self.auth(self.receptionist_id),
            json={"consultation_url": "https://meet.example.invalid/real-room"},
        )
        self.assertEqual(approved.status_code, 200, approved.text)
        self.assertEqual(approved.json()["status"], "approved")

        consultation = await self.client.get(
            f"/appointments/{appointment_id}/consultation",
            headers=self.auth(self.patient_id),
        )
        self.assertEqual(consultation.status_code, 200, consultation.text)
        self.assertEqual(
            consultation.json()["consultation_url"],
            "https://meet.example.invalid/real-room",
        )
        denied = await self.client.get(
            f"/appointments/{appointment_id}/consultation",
            headers=self.auth(self.other_patient_id),
        )
        self.assertEqual(denied.status_code, 404)

        notifications = await self.client.get(
            "/appointments/notifications/mine",
            headers=self.auth(self.patient_id),
        )
        self.assertEqual(notifications.status_code, 200)
        self.assertEqual(notifications.json()[0]["event_type"], "approved")

    async def test_notification_read_is_private_to_recipient(self):
        booked = await self.book(self.auth(self.patient_id))
        self.assertEqual(booked.status_code, 201)
        appointment_id = booked.json()["id"]
        await self.client.patch(
            f"/appointments/{appointment_id}/decline",
            headers=self.auth(self.receptionist_id),
        )
        notification = (
            await self.client.get(
                "/appointments/notifications/mine",
                headers=self.auth(self.patient_id),
            )
        ).json()[0]
        response = await self.client.patch(
            f"/appointments/notifications/{notification['id']}/read",
            headers=self.auth(self.other_patient_id),
        )
        self.assertEqual(response.status_code, 404)
        response = await self.client.patch(
            f"/appointments/notifications/{notification['id']}/read",
            headers=self.auth(self.patient_id),
        )
        self.assertEqual(response.status_code, 200, response.text)
        self.assertIsNotNone(response.json()["read_at"])

    async def test_cancellation_with_less_than_24_hours_remaining_is_rejected(self):
        with self.sessions() as db:
            appointment = Appointment(
                user_id=self.patient_id,
                clinic_id=self.clinic_id,
                doctor_id=self.doctor_id,
                reference="BS-LESS-THAN-24",
                mode="physical",
                scheduled_at=datetime.now(timezone.utc)
                + timedelta(hours=23, minutes=59),
                status="pending",
            )
            db.add(appointment)
            db.commit()
            appointment_id = appointment.id

        response = await self.client.post(
            f"/appointments/{appointment_id}/cancel",
            headers=self.auth(self.patient_id),
            json={"reason": "Schedule conflict"},
        )
        self.assertEqual(response.status_code, 409, response.text)
        with self.sessions() as db:
            current = db.get(Appointment, appointment_id)
            self.assertEqual(current.status, "pending")

    async def test_invalid_doctor_and_unauthenticated_booking_are_rejected(self):
        slots = await self.slots()
        response = await self.client.post(
            "/appointments",
            headers=self.auth(self.patient_id),
            json={
                "clinic_id": self.clinic_id,
                "doctor_id": 987654,
                "mode": "online",
                "scheduled_at": slots[0]["starts_at"],
            },
        )
        self.assertEqual(response.status_code, 404, response.text)

        response = await self.client.post(
            "/appointments",
            json={
                "clinic_id": self.clinic_id,
                "doctor_id": self.doctor_id,
                "mode": "online",
                "scheduled_at": slots[0]["starts_at"],
            },
        )
        self.assertEqual(response.status_code, 401, response.text)

    async def test_booking_without_clinic_configuration_is_rejected(self):
        response = await self.client.post(
            "/appointments",
            headers=self.auth(self.patient_id),
            json={},
        )

        self.assertEqual(response.status_code, 422, response.text)
        with self.sessions() as db:
            self.assertEqual(db.query(Appointment).count(), 0)


if __name__ == "__main__":
    unittest.main()
