import secrets
from datetime import datetime, timedelta, timezone
from urllib.parse import quote, urlsplit

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from ..booking import (
    add_status_notifications,
    available_slots,
    clinic_timezone,
    require_clinic_staff,
)
from ..config import settings
from ..database import get_db
from ..models import (
    Appointment,
    Clinic,
    ClinicStaff,
    DoctorProfile,
    Notification,
    Screening,
    User,
)
from ..schemas import (
    AppointmentApprove,
    AppointmentCancel,
    AppointmentCreate,
    AppointmentOut,
    ConsultationOut,
    NotificationOut,
    RoomOut,
)
from ..security import get_current_user, require_roles

router = APIRouter(prefix="/appointments", tags=["appointments"])
STAFF_ROLES = ("receptionist", "doctor")
ACTIVE_STATUSES = ("pending", "approved")


def _to_out(appointment: Appointment, db: Session) -> AppointmentOut:
    patient = db.get(User, appointment.user_id)
    clinic = db.get(Clinic, appointment.clinic_id) if appointment.clinic_id else None
    doctor = (
        db.get(DoctorProfile, appointment.doctor_id) if appointment.doctor_id else None
    )
    doctor_user = db.get(User, doctor.user_id) if doctor else None
    scheduled_at = appointment.scheduled_at
    if scheduled_at is not None and scheduled_at.tzinfo is None:
        scheduled_at = scheduled_at.replace(tzinfo=timezone.utc)
    cancelled_at = appointment.cancelled_at
    if cancelled_at is not None and cancelled_at.tzinfo is None:
        cancelled_at = cancelled_at.replace(tzinfo=timezone.utc)
    return AppointmentOut(
        id=appointment.id,
        user_id=appointment.user_id,
        patient_name=patient.name if patient else None,
        screening_id=appointment.screening_id,
        status=appointment.status,
        mode=appointment.mode,
        scheduled_at=scheduled_at,
        room_name=appointment.room_name,
        created_at=appointment.created_at,
        updated_at=appointment.updated_at,
        clinic_id=appointment.clinic_id,
        clinic_name=clinic.name if clinic else None,
        clinic_address=clinic.address if clinic else None,
        doctor_id=appointment.doctor_id,
        doctor_name=doctor_user.name if doctor_user else None,
        reference=appointment.reference,
        cancellation_reason=appointment.cancellation_reason,
        cancelled_at=cancelled_at,
        is_demo=appointment.is_demo,
    )


def _get_or_404(
    appointment_id: int, db: Session, *, lock: bool = False
) -> Appointment:
    query = select(Appointment).where(Appointment.id == appointment_id)
    if lock:
        query = query.with_for_update()
    appointment = db.scalar(query)
    if appointment is None:
        raise HTTPException(status_code=404, detail="Appointment not found")
    return appointment


def _require_appointment_access(
    appointment: Appointment, db: Session, user: User
) -> None:
    if appointment.user_id == user.id:
        return
    if (
        appointment.clinic_id is not None
        and user.role in STAFF_ROLES
        and db.scalar(
            select(ClinicStaff.id).where(
                ClinicStaff.clinic_id == appointment.clinic_id,
                ClinicStaff.user_id == user.id,
                ClinicStaff.is_active.is_(True),
            )
        )
        is not None
    ):
        return
    raise HTTPException(status_code=404, detail="Appointment not found")


@router.post("", response_model=AppointmentOut, status_code=status.HTTP_201_CREATED)
def book(
    data: AppointmentCreate,
    db: Session = Depends(get_db),
    user: User = Depends(require_roles("user")),
):
    if user.is_guest:
        raise HTTPException(
            status_code=403, detail="Please sign up before booking an appointment"
        )
    if data.screening_id is not None:
        screening = db.get(Screening, data.screening_id)
        if screening is None or screening.user_id != user.id:
            raise HTTPException(status_code=404, detail="Screening not found")

    supplied = (
        data.clinic_id is not None,
        data.doctor_id is not None,
        data.mode is not None,
        data.scheduled_at is not None,
    )
    if not all(supplied):
        raise HTTPException(
            status_code=422,
            detail="Clinic, doctor, consultation type, and appointment time are required",
        )

    appointment_values = {
        "user_id": user.id,
        "screening_id": data.screening_id,
        "status": "pending",
    }
    if all(supplied):
        clinic = db.get(Clinic, data.clinic_id)
        doctor = db.get(DoctorProfile, data.doctor_id)
        if clinic is None or not clinic.is_active:
            raise HTTPException(status_code=404, detail="Clinic not found")
        if (
            doctor is None
            or doctor.clinic_id != clinic.id
            or not doctor.is_active
        ):
            raise HTTPException(status_code=404, detail="Doctor not found")
        scheduled_at = data.scheduled_at
        if scheduled_at is None or scheduled_at.tzinfo is None:
            raise HTTPException(
                status_code=422, detail="Appointment time must include a time zone"
            )
        scheduled_at = scheduled_at.astimezone(timezone.utc)
        local_date = scheduled_at.astimezone(clinic_timezone(clinic)).date()
        offered_slots = available_slots(
            db, clinic, doctor, local_date, data.mode or ""
        )
        if not any(slot.starts_at == scheduled_at for slot in offered_slots):
            raise HTTPException(
                status_code=409,
                detail="That appointment slot is no longer available. Please choose another time.",
            )
        appointment_values.update(
            clinic_id=clinic.id,
            doctor_id=doctor.id,
            mode=data.mode,
            scheduled_at=scheduled_at,
            reference=f"BS-{secrets.token_hex(6).upper()}",
            is_demo=doctor.is_demo,
        )

    appointment = Appointment(**appointment_values)
    db.add(appointment)
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise HTTPException(
            status_code=409,
            detail="That appointment slot was just booked. Please choose another time.",
        ) from None
    db.refresh(appointment)
    return _to_out(appointment, db)


@router.get("/mine", response_model=list[AppointmentOut])
def my_appointments(
    state: str | None = Query(
        default=None, pattern="^(upcoming|pending|past|cancelled)$"
    ),
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    query = (
        select(Appointment)
        .where(Appointment.user_id == user.id)
        .order_by(Appointment.scheduled_at.desc().nullslast(), Appointment.created_at.desc())
    )
    now = datetime.now(timezone.utc)
    if state == "pending":
        query = query.where(Appointment.status == "pending")
    elif state == "cancelled":
        query = query.where(Appointment.status == "cancelled")
    elif state == "upcoming":
        query = query.where(
            Appointment.scheduled_at >= now,
            Appointment.status.in_(ACTIVE_STATUSES),
        )
    elif state == "past":
        query = query.where(
            (Appointment.scheduled_at < now)
            | Appointment.status.in_(("rejected", "cancelled", "completed"))
        )
    return [_to_out(item, db) for item in db.scalars(query).all()]


@router.get("/notifications/mine", response_model=list[NotificationOut])
def my_notifications(
    unread_only: bool = False,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    query = (
        select(Notification)
        .where(Notification.recipient_id == user.id)
        .order_by(Notification.created_at.desc())
    )
    if unread_only:
        query = query.where(Notification.read_at.is_(None))
    return db.scalars(query).all()


@router.patch("/notifications/{notification_id}/read", response_model=NotificationOut)
def mark_notification_read(
    notification_id: int,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    notification = db.get(Notification, notification_id)
    if notification is None or notification.recipient_id != user.id:
        raise HTTPException(status_code=404, detail="Notification not found")
    if notification.read_at is None:
        notification.read_at = datetime.now(timezone.utc)
        db.commit()
        db.refresh(notification)
    return notification


@router.get("/{appointment_id}", response_model=AppointmentOut)
def appointment_details(
    appointment_id: int,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    appointment = _get_or_404(appointment_id, db)
    _require_appointment_access(appointment, db, user)
    return _to_out(appointment, db)


@router.post("/{appointment_id}/cancel", response_model=AppointmentOut)
def cancel_appointment(
    appointment_id: int,
    data: AppointmentCancel,
    db: Session = Depends(get_db),
    user: User = Depends(require_roles("user")),
):
    appointment = _get_or_404(appointment_id, db, lock=True)
    if appointment.user_id != user.id:
        raise HTTPException(status_code=404, detail="Appointment not found")
    if appointment.status not in ACTIVE_STATUSES:
        raise HTTPException(
            status_code=409, detail="This appointment can no longer be cancelled"
        )
    if appointment.scheduled_at is None:
        raise HTTPException(
            status_code=409, detail="This appointment has no scheduled time"
        )
    scheduled_at = appointment.scheduled_at
    if scheduled_at.tzinfo is None:
        scheduled_at = scheduled_at.replace(tzinfo=timezone.utc)
    if scheduled_at.astimezone(timezone.utc) - datetime.now(timezone.utc) < timedelta(
        hours=24
    ):
        raise HTTPException(
            status_code=409,
            detail="Appointments can only be cancelled at least 24 hours in advance",
        )
    appointment.status = "cancelled"
    appointment.cancellation_reason = data.reason
    appointment.cancelled_at = datetime.now(timezone.utc)
    appointment.cancelled_by = user.id
    add_status_notifications(db, appointment, "cancelled", "Appointment cancelled")
    db.commit()
    db.refresh(appointment)
    return _to_out(appointment, db)


@router.get("", response_model=list[AppointmentOut])
def list_appointments(
    state: str | None = Query(default=None, pattern="^(pending|approved|rejected|cancelled|completed)$"),
    db: Session = Depends(get_db),
    staff: User = Depends(require_roles(*STAFF_ROLES)),
):
    query = select(Appointment).order_by(Appointment.created_at.desc())
    if staff.role == "doctor":
        doctor = db.scalar(
            select(DoctorProfile).where(DoctorProfile.user_id == staff.id)
        )
        if doctor is None:
            return []
        query = query.where(Appointment.doctor_id == doctor.id)
    else:
        clinics = select(ClinicStaff.clinic_id).where(
            ClinicStaff.user_id == staff.id,
            ClinicStaff.role == "receptionist",
            ClinicStaff.is_active.is_(True),
        )
        query = query.where(
            (Appointment.clinic_id.in_(clinics))
            | (
                Appointment.clinic_id.is_(None)
                if state is None
                else Appointment.clinic_id.is_(None)
            )
        )
    if state:
        query = query.where(Appointment.status == state)
    return [_to_out(item, db) for item in db.scalars(query).all()]


@router.patch("/{appointment_id}/approve", response_model=AppointmentOut)
def approve(
    appointment_id: int,
    data: AppointmentApprove | None = None,
    db: Session = Depends(get_db),
    staff: User = Depends(require_roles("receptionist")),
):
    appointment = _get_or_404(appointment_id, db, lock=True)
    if appointment.clinic_id is not None:
        require_clinic_staff(db, appointment.clinic_id, staff, ("receptionist",))
    if appointment.status != "pending":
        raise HTTPException(
            status_code=409, detail="Only pending appointments can be approved"
        )
    if data is not None:
        if appointment.clinic_id is None and data.mode is not None:
            appointment.mode = data.mode
        if appointment.clinic_id is None and data.scheduled_at is not None:
            if data.scheduled_at.tzinfo is None:
                raise HTTPException(
                    status_code=422, detail="Appointment time must include a time zone"
                )
            appointment.scheduled_at = data.scheduled_at.astimezone(timezone.utc)
        if data.consultation_url is not None:
            if appointment.is_demo:
                raise HTTPException(
                    status_code=409,
                    detail="Demo appointments cannot be assigned a real consultation link.",
                )
            _validate_consultation_url(data.consultation_url)
            appointment.consultation_url = data.consultation_url
    appointment.status = "approved"
    add_status_notifications(db, appointment, "approved", "Appointment approved")
    db.commit()
    db.refresh(appointment)
    return _to_out(appointment, db)


@router.patch("/{appointment_id}/decline", response_model=AppointmentOut)
def reject(
    appointment_id: int,
    db: Session = Depends(get_db),
    staff: User = Depends(require_roles("receptionist")),
):
    appointment = _get_or_404(appointment_id, db, lock=True)
    if appointment.clinic_id is not None:
        require_clinic_staff(db, appointment.clinic_id, staff, ("receptionist",))
    if appointment.status != "pending":
        raise HTTPException(
            status_code=409, detail="Only pending appointments can be rejected"
        )
    appointment.status = "rejected"
    add_status_notifications(db, appointment, "rejected", "Appointment rejected")
    db.commit()
    db.refresh(appointment)
    return _to_out(appointment, db)


def _validate_consultation_url(value: str) -> None:
    parsed = urlsplit(value)
    if parsed.scheme != "https" or not parsed.netloc or parsed.username or parsed.password:
        raise HTTPException(
            status_code=422,
            detail="Consultation links must be valid HTTPS URLs",
        )


@router.get("/{appointment_id}/consultation", response_model=ConsultationOut)
def get_consultation(
    appointment_id: int,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    appointment = _get_or_404(appointment_id, db)
    _require_appointment_access(appointment, db, user)
    if appointment.status != "approved" or appointment.mode != "online":
        raise HTTPException(
            status_code=409,
            detail="Consultation access is available only for approved online appointments",
        )
    if appointment.is_demo:
        raise HTTPException(
            status_code=409,
            detail="Online consultation is simulated for demo appointments and has no meeting link.",
        )
    url = appointment.consultation_url
    if url is None and settings.consultation_url_template:
        url = settings.consultation_url_template.format(
            reference=quote(appointment.reference or str(appointment.id), safe="")
        )
    if url is None:
        raise HTTPException(
            status_code=503,
            detail="Online consultation is not configured for this appointment",
        )
    _validate_consultation_url(url)
    return ConsultationOut(consultation_url=url)


@router.get("/{appointment_id}/room", response_model=RoomOut)
def get_room(
    appointment_id: int,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    appointment = _get_or_404(appointment_id, db)
    _require_appointment_access(appointment, db, user)
    if appointment.status != "approved" or appointment.mode != "online":
        raise HTTPException(
            status_code=409, detail="This appointment has no approved online room"
        )
    if appointment.room_name is None:
        raise HTTPException(status_code=503, detail="Online consultation is not configured")
    return RoomOut(room_name=appointment.room_name)
