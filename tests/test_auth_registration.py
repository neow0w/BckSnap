import unittest
from unittest.mock import patch

import httpx
from sqlalchemy import create_engine, func, select
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.database import Base, get_db
from app.main import app
from app.migrations import upgrade
from app.models import Screening, User
from app.security import create_access_token, verify_password


class AccountRegistrationTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.engine = create_engine(
            "sqlite://",
            connect_args={"check_same_thread": False},
            poolclass=StaticPool,
        )
        Base.metadata.create_all(self.engine)
        upgrade(self.engine)
        self.sessions = sessionmaker(self.engine, expire_on_commit=False)

        def override_get_db():
            with self.sessions() as db:
                yield db

        self.previous_override = app.dependency_overrides.get(get_db)
        app.dependency_overrides[get_db] = override_get_db
        self.client = httpx.AsyncClient(
            transport=httpx.ASGITransport(app=app, raise_app_exceptions=False),
            base_url="http://test",
        )

    async def asyncTearDown(self):
        await self.client.aclose()
        if self.previous_override is None:
            app.dependency_overrides.pop(get_db, None)
        else:
            app.dependency_overrides[get_db] = self.previous_override
        Base.metadata.drop_all(self.engine)
        self.engine.dispose()

    @staticmethod
    def payload(**overrides):
        data = {
            "first_name": "  Jane  ",
            "middle_initial": "q.",
            "last_name": "Doe",
            "birthdate": "1990-06-15",
            "address": "  12 Main   Street ",
            "gender": "prefer_not_to_say",
            "email": " Jane.Doe@Example.com ",
            "contact_number": "0917 123 4567",
            "password": "strong-pass-123",
            "confirm_password": "strong-pass-123",
        }
        data.update(overrides)
        return data

    async def test_valid_registration_normalizes_and_hashes_credentials(self):
        response = await self.client.post("/auth/signup", json=self.payload())

        self.assertEqual(response.status_code, 200, response.text)
        user_data = response.json()["user"]
        self.assertEqual(user_data["email"], "jane.doe@example.com")
        self.assertEqual(user_data["first_name"], "Jane")
        self.assertEqual(user_data["middle_initial"], "Q")
        self.assertEqual(user_data["last_name"], "Doe")
        self.assertEqual(user_data["contact_number"], "+639171234567")
        self.assertNotIn("password_hash", user_data)
        self.assertNotIn("password", user_data)

        with self.sessions() as db:
            user = db.get(User, user_data["id"])
            self.assertIsNotNone(user)
            self.assertNotEqual(user.password_hash, "strong-pass-123")
            self.assertTrue(verify_password("strong-pass-123", user.password_hash))
            self.assertEqual(user.name, "Jane Q. Doe")
            self.assertEqual(user.address, "12 Main Street")

    async def test_login_accepts_normalized_email_after_registration(self):
        await self.client.post("/auth/signup", json=self.payload())

        response = await self.client.post(
            "/auth/login",
            json={"email": " JANE.DOE@example.com ", "password": "strong-pass-123"},
        )

        self.assertEqual(response.status_code, 200, response.text)
        self.assertEqual(response.json()["user"]["email"], "jane.doe@example.com")

    async def test_guest_registration_preserves_existing_screening(self):
        with self.sessions() as db:
            guest = User(name="Guest", is_guest=True, role="user")
            db.add(guest)
            db.flush()
            screening = Screening(
                user_id=guest.id,
                angle=8.5,
                has_scoliosis=True,
                idempotency_key="guest-screening-1",
            )
            db.add(screening)
            db.commit()
            guest_id = guest.id
            screening_id = screening.id

        response = await self.client.post(
            "/auth/signup",
            json=self.payload(),
            headers={"Authorization": f"Bearer {create_access_token(guest_id)}"},
        )

        self.assertEqual(response.status_code, 200, response.text)
        self.assertEqual(response.json()["user"]["id"], guest_id)
        self.assertFalse(response.json()["user"]["is_guest"])
        with self.sessions() as db:
            self.assertIsNotNone(db.get(Screening, screening_id))
            self.assertEqual(db.get(Screening, screening_id).user_id, guest_id)

    async def test_invalid_registration_fields_are_rejected(self):
        invalid_payloads = (
            self.payload(first_name="   "),
            self.payload(middle_initial="Jane"),
            self.payload(birthdate="2999-01-01"),
            self.payload(gender="other"),
            self.payload(contact_number="123"),
            self.payload(confirm_password="different-pass"),
            self.payload(email="not-an-email"),
        )

        for payload in invalid_payloads:
            with self.subTest(payload=payload):
                response = await self.client.post("/auth/signup", json=payload)
                self.assertEqual(response.status_code, 422, response.text)

    async def test_duplicate_email_is_case_insensitive(self):
        first = await self.client.post("/auth/signup", json=self.payload())
        duplicate = await self.client.post(
            "/auth/signup",
            json=self.payload(email="JANE.DOE@example.com"),
        )

        self.assertEqual(first.status_code, 200, first.text)
        self.assertEqual(duplicate.status_code, 409, duplicate.text)
        with self.sessions() as db:
            self.assertEqual(
                db.scalar(select(func.count()).select_from(User)), 1
            )

    async def test_database_failure_does_not_return_success_or_create_user(self):
        with patch(
            "sqlalchemy.orm.Session.commit",
            side_effect=SQLAlchemyError("simulated persistence failure"),
        ):
            response = await self.client.post(
                "/auth/signup",
                json=self.payload(),
            )

        self.assertEqual(response.status_code, 500)
        with self.sessions() as db:
            self.assertEqual(db.scalar(select(func.count()).select_from(User)), 0)
