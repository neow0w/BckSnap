import unittest
from unittest.mock import patch

import httpx
from sqlalchemy import create_engine, func, select
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session, sessionmaker
from sqlalchemy.pool import StaticPool

from app.database import Base, get_db
from app.main import app
from app.migrations import upgrade
from app.models import Screening, User
from app.security import create_access_token


class ScreeningPersistenceTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.engine = create_engine(
            "sqlite://",
            connect_args={"check_same_thread": False},
            poolclass=StaticPool,
        )
        Base.metadata.create_all(self.engine)
        upgrade(self.engine)
        upgrade(self.engine)
        self.sessions = sessionmaker(self.engine, expire_on_commit=False)
        with self.sessions() as db:
            user = User(name="Test Patient", role="user", is_guest=True)
            db.add(user)
            db.commit()
            self.user_id = user.id

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

    @property
    def headers(self):
        return {
            "Authorization": f"Bearer {create_access_token(self.user_id)}",
            "Idempotency-Key": "screening-attempt-01",
        }

    async def save(self, angle="8.5", headers=None):
        return await self.client.post(
            "/screenings",
            headers=headers if headers is not None else self.headers,
            data={"angle": angle},
        )

    async def screening_count(self):
        with self.sessions() as db:
            return db.scalar(select(func.count()).select_from(Screening))

    async def test_authenticated_result_is_persisted_and_returned(self):
        response = await self.save()

        self.assertEqual(response.status_code, 200, response.text)
        result = response.json()
        self.assertEqual(result["angle"], 8.5)
        self.assertEqual(result["user_id"], self.user_id)
        self.assertTrue(result["has_scoliosis"])
        self.assertEqual(await self.screening_count(), 1)

    async def test_invalid_angle_is_rejected_without_persistence(self):
        response = await self.save(angle="91")

        self.assertEqual(response.status_code, 422)
        self.assertEqual(await self.screening_count(), 0)

    async def test_repeated_submission_returns_the_same_screening(self):
        first = await self.save()
        retry = await self.save()

        self.assertEqual(first.status_code, 200, first.text)
        self.assertEqual(retry.status_code, 200, retry.text)
        self.assertEqual(first.json()["id"], retry.json()["id"])
        self.assertEqual(await self.screening_count(), 1)

    async def test_idempotency_key_cannot_be_reused_for_another_angle(self):
        await self.save()
        response = await self.save(angle="9.0")

        self.assertEqual(response.status_code, 409)
        self.assertEqual(await self.screening_count(), 1)

    async def test_screening_requires_authentication(self):
        response = await self.client.post("/screenings", data={"angle": "8.5"})

        self.assertEqual(response.status_code, 401)
        self.assertEqual(await self.screening_count(), 0)

    async def test_database_failure_does_not_return_a_success_response(self):
        with patch.object(Session, "commit", side_effect=SQLAlchemyError("db error")):
            response = await self.save()

        self.assertEqual(response.status_code, 500)
        self.assertEqual(await self.screening_count(), 0)


if __name__ == "__main__":
    unittest.main()
