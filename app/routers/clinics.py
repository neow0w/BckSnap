import math
import threading
import time as clock
from functools import lru_cache
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

import httpx
from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import or_, select
from sqlalchemy.orm import Session

from ..booking import available_slots, require_clinic_staff
from ..config import settings
from ..database import get_db
from ..models import (
    Clinic,
    ClinicService,
    ClinicStaff,
    DemoAppointmentType,
    DoctorProfile,
    DoctorSchedule,
    ScheduleException,
    User,
)
from ..schemas import (
    ClinicCreate,
    ClinicOut,
    DoctorCreate,
    DoctorOut,
    GeocodeResult,
    ScheduleCreate,
    ScheduleExceptionCreate,
    SlotOut,
)
from ..security import get_current_user, require_roles

router = APIRouter(prefix="/clinics", tags=["clinics"])
_geocode_lock = threading.Lock()
_last_geocode_at = 0.0


def _doctor_out(db: Session, doctor: DoctorProfile) -> DoctorOut:
    user = db.get(User, doctor.user_id)
    return DoctorOut(
        id=doctor.id,
        user_id=doctor.user_id,
        name=user.name if user else None,
        specializations=doctor.specializations or [],
        professional_info=doctor.professional_info,
        supports_online=doctor.supports_online,
        supports_physical=doctor.supports_physical,
        is_demo=doctor.is_demo,
    )


def _clinic_out(
    db: Session,
    clinic: Clinic,
    latitude: float | None = None,
    longitude: float | None = None,
) -> ClinicOut:
    services = db.scalars(
        select(ClinicService)
        .where(ClinicService.clinic_id == clinic.id)
        .order_by(ClinicService.name)
    ).all()
    doctors = db.scalars(
        select(DoctorProfile)
        .where(
            DoctorProfile.clinic_id == clinic.id,
            DoctorProfile.is_active.is_(True),
        )
        .order_by(DoctorProfile.id)
    ).all()
    demo_types = db.scalars(
        select(DemoAppointmentType)
        .where(
            DemoAppointmentType.clinic_id == clinic.id,
            DemoAppointmentType.simulation_only.is_(True),
        )
        .order_by(DemoAppointmentType.mode)
    ).all()
    distance = None
    if (
        latitude is not None
        and longitude is not None
        and clinic.latitude is not None
        and clinic.longitude is not None
    ):
        lat1, lat2 = math.radians(latitude), math.radians(clinic.latitude)
        delta_lat = lat2 - lat1
        delta_lon = math.radians(clinic.longitude - longitude)
        haversine = (
            math.sin(delta_lat / 2) ** 2
            + math.cos(lat1) * math.cos(lat2) * math.sin(delta_lon / 2) ** 2
        )
        haversine = min(1, max(0, haversine))
        distance = 6371 * 2 * math.atan2(math.sqrt(haversine), math.sqrt(1 - haversine))
    return ClinicOut(
        id=clinic.id,
        name=clinic.name,
        description=clinic.description,
        address=clinic.address,
        latitude=clinic.latitude,
        longitude=clinic.longitude,
        phone=clinic.phone,
        email=clinic.email,
        timezone=clinic.timezone,
        operating_hours=clinic.operating_hours,
        supports_online=clinic.supports_online,
        supports_physical=clinic.supports_physical,
        demo_operating_hours=clinic.demo_operating_hours,
        demo_appointment_types=demo_types,
        services=services,
        doctors=[_doctor_out(db, doctor) for doctor in doctors],
        distance_km=distance,
    )


@lru_cache(maxsize=128)
def _geocode(query: str) -> list[GeocodeResult]:
    global _last_geocode_at
    with _geocode_lock:
        delay = 1.0 - (clock.monotonic() - _last_geocode_at)
        if delay > 0:
            clock.sleep(delay)
        try:
            response = httpx.get(
                "https://nominatim.openstreetmap.org/search",
                params={"q": query, "format": "jsonv2", "limit": 5},
                headers={"User-Agent": settings.geocoding_user_agent},
                timeout=8,
            )
            response.raise_for_status()
        except httpx.HTTPStatusError as exc:
            if exc.response.status_code == 429:
                raise HTTPException(
                    status_code=503, detail="Location search is busy. Try again shortly."
                ) from None
            raise HTTPException(
                status_code=502, detail="Location search is temporarily unavailable."
            ) from None
        except httpx.HTTPError:
            raise HTTPException(
                status_code=502, detail="Location search is temporarily unavailable."
            ) from None
        finally:
            _last_geocode_at = clock.monotonic()
    results = []
    try:
        for item in response.json():
            results.append(
                GeocodeResult(
                    label=item["display_name"],
                    latitude=float(item["lat"]),
                    longitude=float(item["lon"]),
                )
            )
    except (TypeError, KeyError, ValueError):
        raise HTTPException(
            status_code=502, detail="Location search returned an invalid response."
        ) from None
    return results


@router.get("/geocode", response_model=list[GeocodeResult])
def geocode_location(
    q: str = Query(min_length=3, max_length=180),
):
    return _geocode(q.strip())


@router.get("", response_model=list[ClinicOut])
def search_clinics(
    q: str | None = Query(default=None, max_length=120),
    latitude: float | None = Query(default=None, ge=-90, le=90),
    longitude: float | None = Query(default=None, ge=-180, le=180),
    radius_km: float = Query(default=50, gt=0, le=500),
    service: str | None = Query(default=None, max_length=120),
    mode: str | None = Query(default=None, pattern="^(online|physical)$"),
    db: Session = Depends(get_db),
):
    if (latitude is None) != (longitude is None):
        raise HTTPException(
            status_code=422, detail="Latitude and longitude must be provided together"
        )
    query = select(Clinic).where(Clinic.is_active.is_(True))
    if q and q.strip():
        search_term = f"%{q.strip()}%"
        query = query.where(
            or_(
                Clinic.name.ilike(search_term),
                Clinic.address.ilike(search_term),
            )
        )
    if mode == "online":
        query = query.where(
            or_(
                Clinic.supports_online.is_(True),
                Clinic.id.in_(
                    select(DemoAppointmentType.clinic_id).where(
                        DemoAppointmentType.mode == "online",
                        DemoAppointmentType.simulation_only.is_(True),
                    )
                ),
            )
        )
    elif mode == "physical":
        query = query.where(
            or_(
                Clinic.supports_physical.is_(True),
                Clinic.id.in_(
                    select(DemoAppointmentType.clinic_id).where(
                        DemoAppointmentType.mode == "physical",
                        DemoAppointmentType.simulation_only.is_(True),
                    )
                ),
            )
        )
    if service and service.strip():
        query = query.where(
            Clinic.id.in_(
                select(ClinicService.clinic_id).where(
                    ClinicService.name.ilike(f"%{service.strip()}%")
                )
            )
        )
    clinics = db.scalars(query.order_by(Clinic.name)).all()
    results = []
    for clinic in clinics:
        item = _clinic_out(db, clinic, latitude, longitude)
        if latitude is not None and item.distance_km is None:
            continue
        if item.distance_km is not None and item.distance_km > radius_km:
            continue
        results.append(item)
    if latitude is not None:
        results.sort(key=lambda item: item.distance_km or 0)
    return results


@router.get("/{clinic_id}", response_model=ClinicOut)
def clinic_details(clinic_id: int, db: Session = Depends(get_db)):
    clinic = db.get(Clinic, clinic_id)
    if clinic is None or not clinic.is_active:
        raise HTTPException(status_code=404, detail="Clinic not found")
    return _clinic_out(db, clinic)


@router.get("/{clinic_id}/doctors", response_model=list[DoctorOut])
def clinic_doctors(clinic_id: int, db: Session = Depends(get_db)):
    clinic = db.get(Clinic, clinic_id)
    if clinic is None or not clinic.is_active:
        raise HTTPException(status_code=404, detail="Clinic not found")
    doctors = db.scalars(
        select(DoctorProfile)
        .where(
            DoctorProfile.clinic_id == clinic_id,
            DoctorProfile.is_active.is_(True),
        )
        .order_by(DoctorProfile.id)
    ).all()
    return [_doctor_out(db, doctor) for doctor in doctors]


@router.get("/{clinic_id}/slots", response_model=list[SlotOut])
def clinic_slots(
    clinic_id: int,
    doctor_id: int = Query(gt=0),
    on: str = Query(pattern=r"^\d{4}-\d{2}-\d{2}$"),
    mode: str = Query(pattern="^(online|physical)$"),
    db: Session = Depends(get_db),
):
    from datetime import date

    try:
        appointment_date = date.fromisoformat(on)
    except ValueError:
        raise HTTPException(status_code=422, detail="Use a valid appointment date") from None
    clinic = db.get(Clinic, clinic_id)
    if clinic is None or not clinic.is_active:
        raise HTTPException(status_code=404, detail="Clinic not found")
    doctor = db.get(DoctorProfile, doctor_id)
    if doctor is None or doctor.clinic_id != clinic_id or not doctor.is_active:
        raise HTTPException(status_code=404, detail="Doctor not found")
    return available_slots(db, clinic, doctor, appointment_date, mode)


@router.post("", response_model=ClinicOut, status_code=status.HTTP_201_CREATED)
def create_clinic(
    data: ClinicCreate,
    db: Session = Depends(get_db),
    user: User = Depends(require_roles("receptionist")),
):
    try:
        ZoneInfo(data.timezone)
    except ZoneInfoNotFoundError:
        raise HTTPException(status_code=422, detail="Unknown clinic time zone") from None
    clinic = Clinic(
        name=data.name.strip(),
        description=data.description,
        address=data.address.strip(),
        latitude=data.latitude,
        longitude=data.longitude,
        phone=data.phone,
        email=data.email,
        timezone=data.timezone,
        operating_hours=data.operating_hours,
        supports_online=data.supports_online,
        supports_physical=data.supports_physical,
    )
    db.add(clinic)
    db.flush()
    db.add(ClinicStaff(clinic_id=clinic.id, user_id=user.id, role="receptionist"))
    for name in dict.fromkeys(service.strip() for service in data.services if service.strip()):
        db.add(ClinicService(clinic_id=clinic.id, name=name))
    db.commit()
    db.refresh(clinic)
    return _clinic_out(db, clinic)


@router.post(
    "/{clinic_id}/doctors",
    response_model=DoctorOut,
    status_code=status.HTTP_201_CREATED,
)
def add_doctor(
    clinic_id: int,
    data: DoctorCreate,
    db: Session = Depends(get_db),
    user: User = Depends(require_roles("receptionist")),
):
    require_clinic_staff(db, clinic_id, user, ("receptionist",))
    clinic = db.get(Clinic, clinic_id)
    doctor_user = db.get(User, data.user_id)
    if clinic is None or not clinic.is_active:
        raise HTTPException(status_code=404, detail="Clinic not found")
    if doctor_user is None or doctor_user.role != "doctor" or doctor_user.is_guest:
        raise HTTPException(status_code=404, detail="Doctor account not found")
    existing = db.scalar(
        select(DoctorProfile).where(
            DoctorProfile.clinic_id == clinic_id,
            DoctorProfile.user_id == doctor_user.id,
        )
    )
    if existing is not None:
        raise HTTPException(status_code=409, detail="Doctor is already assigned to this clinic")
    doctor = DoctorProfile(
        clinic_id=clinic_id,
        user_id=doctor_user.id,
        specializations=list(dict.fromkeys(s.strip() for s in data.specializations if s.strip())),
        professional_info=data.professional_info,
        supports_online=data.supports_online,
        supports_physical=data.supports_physical,
    )
    db.add(doctor)
    db.flush()
    db.add(ClinicStaff(clinic_id=clinic_id, user_id=doctor_user.id, role="doctor"))
    db.commit()
    db.refresh(doctor)
    return _doctor_out(db, doctor)


@router.put("/{clinic_id}/doctors/{doctor_id}/schedules", status_code=status.HTTP_204_NO_CONTENT)
def replace_doctor_schedules(
    clinic_id: int,
    doctor_id: int,
    schedules: list[ScheduleCreate],
    db: Session = Depends(get_db),
    user: User = Depends(require_roles("receptionist")),
):
    require_clinic_staff(db, clinic_id, user, ("receptionist",))
    doctor = db.get(DoctorProfile, doctor_id)
    if doctor is None or doctor.clinic_id != clinic_id:
        raise HTTPException(status_code=404, detail="Doctor not found")
    if doctor.is_demo:
        raise HTTPException(
            status_code=409,
            detail="Demo schedules are managed by the development demo seeder.",
        )
    clinic = db.get(Clinic, clinic_id)
    modes = {schedule.mode for schedule in schedules}
    if "online" in modes and not clinic.supports_online:
        raise HTTPException(status_code=422, detail="The clinic does not support online visits")
    if "physical" in modes and not clinic.supports_physical:
        raise HTTPException(status_code=422, detail="The clinic does not support physical visits")
    db.query(DoctorSchedule).filter(DoctorSchedule.doctor_id == doctor_id).delete()
    for schedule in schedules:
        db.add(DoctorSchedule(doctor_id=doctor_id, **schedule.model_dump()))
    doctor.supports_online = "online" in modes
    doctor.supports_physical = "physical" in modes
    db.commit()


@router.post(
    "/{clinic_id}/doctors/{doctor_id}/exceptions",
    status_code=status.HTTP_201_CREATED,
)
def add_schedule_exception(
    clinic_id: int,
    doctor_id: int,
    data: ScheduleExceptionCreate,
    db: Session = Depends(get_db),
    user: User = Depends(require_roles("receptionist")),
):
    require_clinic_staff(db, clinic_id, user, ("receptionist",))
    doctor = db.get(DoctorProfile, doctor_id)
    if doctor is None or doctor.clinic_id != clinic_id:
        raise HTTPException(status_code=404, detail="Doctor not found")
    exception = ScheduleException(doctor_id=doctor_id, **data.model_dump())
    db.add(exception)
    db.commit()
    db.refresh(exception)
    return {"id": exception.id}


@router.delete("/{clinic_id}/doctors/{doctor_id}/exceptions/{exception_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_schedule_exception(
    clinic_id: int,
    doctor_id: int,
    exception_id: int,
    db: Session = Depends(get_db),
    user: User = Depends(require_roles("receptionist")),
):
    require_clinic_staff(db, clinic_id, user, ("receptionist",))
    exception = db.get(ScheduleException, exception_id)
    if exception is None or exception.doctor_id != doctor_id:
        raise HTTPException(status_code=404, detail="Schedule exception not found")
    doctor = db.get(DoctorProfile, doctor_id)
    if doctor is None or doctor.clinic_id != clinic_id:
        raise HTTPException(status_code=404, detail="Doctor not found")
    db.delete(exception)
    db.commit()
