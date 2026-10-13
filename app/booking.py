from datetime import date, datetime, time, timedelta, timezone
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from fastapi import HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session

from .models import (
    Appointment,
    Clinic,
    ClinicStaff,
    DemoAppointmentType,
    DoctorProfile,
    DoctorSchedule,
    Notification,
    ScheduleException,
    User,
)
from .schemas import SlotOut

ACTIVE_APPOINTMENT_STATUSES = ("pending", "approved")


def clinic_timezone(clinic: Clinic) -> ZoneInfo:
    try:
        return ZoneInfo(clinic.timezone)
    except ZoneInfoNotFoundError:
        raise HTTPException(
            status_code=500, detail="The clinic has an invalid time zone configured"
        ) from None


def available_slots(
    db: Session,
    clinic: Clinic,
    doctor: DoctorProfile,
    appointment_date: date,
    mode: str,
) -> list[SlotOut]:
    if not clinic.is_active or not doctor.is_active or doctor.clinic_id != clinic.id:
        return []
    if mode not in ("online", "physical"):
        return []
    demo_type = db.scalar(
        select(DemoAppointmentType).where(
            DemoAppointmentType.clinic_id == clinic.id,
            DemoAppointmentType.mode == mode,
            DemoAppointmentType.simulation_only.is_(True),
        )
    )
    if doctor.is_demo:
        if demo_type is None:
            return []
    elif mode == "online":
        if not clinic.supports_online or not doctor.supports_online:
            return []
    elif not clinic.supports_physical or not doctor.supports_physical:
        return []

    timezone_ = clinic_timezone(clinic)
    weekday_name = appointment_date.strftime("%A").lower()
    hours = clinic.demo_operating_hours if doctor.is_demo else clinic.operating_hours
    opening = (hours or {}).get(weekday_name)
    if not opening:
        return []
    if isinstance(opening, dict) and opening.get("closed") is True:
        return []
    try:
        intervals = [opening] if isinstance(opening, dict) else opening
        if not isinstance(intervals, list) or not intervals:
            return []
        clinic_opens = min(time.fromisoformat(item["open"]) for item in intervals)
        clinic_closes = max(time.fromisoformat(item["close"]) for item in intervals)
    except (KeyError, TypeError, ValueError):
        raise HTTPException(
            status_code=500, detail="The clinic has invalid operating hours configured"
        ) from None
    if clinic_closes <= clinic_opens:
        return []

    schedules = db.scalars(
        select(DoctorSchedule).where(
            DoctorSchedule.doctor_id == doctor.id,
            DoctorSchedule.weekday == appointment_date.weekday(),
            DoctorSchedule.mode == mode,
            DoctorSchedule.is_demo.is_(doctor.is_demo),
            DoctorSchedule.is_active.is_(True),
        )
    ).all()
    if not schedules:
        return []

    exceptions = db.scalars(
        select(ScheduleException).where(
            ScheduleException.doctor_id == doctor.id,
            ScheduleException.exception_date == appointment_date,
        )
    ).all()
    if any(row.start_time is None for row in exceptions):
        return []
    appointments = db.scalars(
        select(Appointment).where(
            Appointment.doctor_id == doctor.id,
            Appointment.scheduled_at
            >= datetime.combine(appointment_date, time.min, tzinfo=timezone_).astimezone(timezone.utc),
            Appointment.scheduled_at
            < datetime.combine(appointment_date + timedelta(days=1), time.min, tzinfo=timezone_).astimezone(timezone.utc),
            Appointment.status.in_(ACTIVE_APPOINTMENT_STATUSES),
        )
    ).all()
    booked_starts = {
        item.scheduled_at.astimezone(timezone_).replace(tzinfo=None)
        for item in appointments
        if item.scheduled_at is not None
    }
    now = datetime.now(timezone.utc)
    slots: dict[datetime, SlotOut] = {}

    for schedule in schedules:
        start = max(schedule.start_time, clinic_opens)
        end = min(schedule.end_time, clinic_closes)
        cursor = datetime.combine(appointment_date, start)
        closing = datetime.combine(appointment_date, end)
        while cursor + timedelta(minutes=schedule.duration_minutes) <= closing:
            slot_end = cursor + timedelta(minutes=schedule.duration_minutes)
            blocked = any(
                exc.start_time is not None
                and exc.end_time is not None
                and cursor.time() < exc.end_time
                and slot_end.time() > exc.start_time
                for exc in exceptions
            )
            local_start = cursor.replace(tzinfo=timezone_)
            if (
                not blocked
                and cursor not in booked_starts
                and local_start.astimezone(timezone.utc) > now
            ):
                starts_at = local_start.astimezone(timezone.utc)
                slots[starts_at] = SlotOut(
                    starts_at=starts_at,
                    ends_at=(slot_end.replace(tzinfo=timezone_)).astimezone(timezone.utc),
                    mode=mode,
                )
            cursor += timedelta(minutes=schedule.duration_minutes)
    return [slots[slot] for slot in sorted(slots)]


def clinic_staff_ids(db: Session, clinic_id: int) -> set[int]:
    return set(
        db.scalars(
            select(ClinicStaff.user_id).where(
                ClinicStaff.clinic_id == clinic_id,
                ClinicStaff.is_active.is_(True),
            )
        ).all()
    )


def add_status_notifications(
    db: Session, appointment: Appointment, event_type: str, title: str
) -> None:
    reference = appointment.reference or f"#{appointment.id}"
    message = f"Appointment {reference} was {event_type}."
    recipients = {appointment.user_id}
    if event_type == "cancelled" and appointment.clinic_id is not None:
        recipients.update(clinic_staff_ids(db, appointment.clinic_id))

    existing = set(
        db.scalars(
            select(Notification.recipient_id).where(
                Notification.appointment_id == appointment.id,
                Notification.event_type == event_type,
            )
        ).all()
    )
    for recipient_id in recipients - existing:
        db.add(
            Notification(
                recipient_id=recipient_id,
                appointment_id=appointment.id,
                event_type=event_type,
                title=title,
                message=message,
            )
        )


def require_clinic_staff(
    db: Session, clinic_id: int, user: User, roles: tuple[str, ...]
) -> None:
    staff = db.scalar(
        select(ClinicStaff).where(
            ClinicStaff.clinic_id == clinic_id,
            ClinicStaff.user_id == user.id,
            ClinicStaff.role.in_(roles),
            ClinicStaff.is_active.is_(True),
        )
    )
    if staff is None:
        raise HTTPException(status_code=403, detail="You are not authorized for this clinic")
