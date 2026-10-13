import unittest

import httpx
from sqlalchemy import create_engine, select
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.database import Base, get_db
from app.main import app
from app.models import Clinic, ClinicService, DoctorProfile, DoctorSchedule
from scripts.seed_clinics import seed_clinics


class ClinicDirectoryTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.engine = create_engine(
            "sqlite://",
            connect_args={"check_same_thread": False},
            poolclass=StaticPool,
        )
        Base.metadata.create_all(self.engine)
        self.sessions = sessionmaker(self.engine, expire_on_commit=False)
        with self.sessions() as db:
            self.seeded = seed_clinics(db)
            self.clinic_ids = [clinic.id for clinic in self.seeded]
            seed_clinics(db)

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

    async def test_seed_is_idempotent_and_keeps_configuration_uninvented(self):
        with self.sessions() as db:
            clinics = db.scalars(select(Clinic).order_by(Clinic.id)).all()
            self.assertEqual(len(clinics), 2)
            self.assertEqual(
                db.query(ClinicService).count(), 2
            )
            self.assertEqual(db.query(DoctorProfile).count(), 0)
            self.assertEqual(db.query(DoctorSchedule).count(), 0)
            for clinic in clinics:
                self.assertIsNone(clinic.latitude)
                self.assertIsNone(clinic.longitude)
                self.assertIsNone(clinic.operating_hours)
                self.assertFalse(clinic.supports_online)
                self.assertFalse(clinic.supports_physical)

    async def test_name_and_address_search_find_clinics_without_coordinates(self):
        physio_by_name = await self.client.get(
            "/clinics", params={"q": "Physio Point"}
        )
        self.assertEqual(physio_by_name.status_code, 200)
        self.assertEqual([row["id"] for row in physio_by_name.json()], [self.clinic_ids[0]])

        physio_by_address = await self.client.get(
            "/clinics", params={"q": "F. Reyes Street"}
        )
        self.assertEqual([row["id"] for row in physio_by_address.json()], [self.clinic_ids[0]])

        medi_sky = await self.client.get("/clinics", params={"q": "MEDI-SKY"})
        self.assertEqual([row["id"] for row in medi_sky.json()], [self.clinic_ids[1]])

        all_clinics = await self.client.get("/clinics")
        self.assertEqual(len(all_clinics.json()), 2)
        self.assertTrue(
            all(row["latitude"] is None and row["longitude"] is None for row in all_clinics.json())
        )

    async def test_details_show_supplied_info_and_unverified_booking_state(self):
        details = await self.client.get(f"/clinics/{self.clinic_ids[1]}")

        self.assertEqual(details.status_code, 200)
        self.assertEqual(details.json()["phone"], "0950 282 5622")
        self.assertIn("not been verified", details.json()["description"])
        self.assertEqual(details.json()["doctors"], [])
        self.assertFalse(details.json()["supports_online"])
        self.assertFalse(details.json()["supports_physical"])

    async def test_radius_search_excludes_records_without_coordinates(self):
        response = await self.client.get(
            "/clinics",
            params={"latitude": 14.3, "longitude": 121.1, "radius_km": 25},
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json(), [])

    async def test_service_search_uses_only_listed_services(self):
        response = await self.client.get(
            "/clinics", params={"service": "Physical therapy"}
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual([clinic["id"] for clinic in response.json()], [self.clinic_ids[0]])

    async def test_reseeding_preserves_staff_configuration(self):
        with self.sessions() as db:
            clinic = db.get(Clinic, self.clinic_ids[0])
            clinic.latitude = 14.3
            clinic.longitude = 121.1
            clinic.supports_physical = True
            db.commit()

            seed_clinics(db)
            refreshed = db.get(Clinic, self.clinic_ids[0])
            self.assertEqual(refreshed.latitude, 14.3)
            self.assertEqual(refreshed.longitude, 121.1)
            self.assertTrue(refreshed.supports_physical)
            self.assertEqual(
                db.query(ClinicService)
                .filter(ClinicService.clinic_id == self.clinic_ids[0])
                .count(),
                2,
            )


if __name__ == "__main__":
    unittest.main()
