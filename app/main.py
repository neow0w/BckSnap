from contextlib import asynccontextmanager

from fastapi import Depends, FastAPI
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import text
from sqlalchemy.orm import Session

from . import models  # noqa: F401  (registers the tables)
from .database import Base, engine, get_db
from .migrations import upgrade
from .routers import appointments, auth, clinics, messages, patients, screenings


@asynccontextmanager
async def lifespan(app: FastAPI):
    Base.metadata.create_all(bind=engine)
    upgrade(engine)
    yield


app = FastAPI(title="BckSnap API", lifespan=lifespan)
app.include_router(auth.router)
app.include_router(clinics.router)
app.include_router(screenings.router)
app.include_router(appointments.router)
app.include_router(patients.router)
app.include_router(messages.router)

# Lets the Flutter web app call the API from the browser.
# Development setting: we will tighten this before deploying.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/")
def root():
    return {"message": "BckSnap API is running"}


@app.get("/health")
def health(db: Session = Depends(get_db)):
    db.execute(text("SELECT 1"))
    return {"status": "ok", "database": "connected"}