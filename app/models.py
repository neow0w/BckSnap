from datetime import date, datetime, time, timezone

from sqlalchemy import (
    Boolean,
    CheckConstraint,
    Date,
    DateTime,
    Float,
    ForeignKey,
    Index,
    Integer,
    JSON,
    String,
    Text,
    Time,
    UniqueConstraint,
    text,
)
from sqlalchemy.orm import Mapped, mapped_column

from .database import Base


def utcnow():
    return datetime.now(timezone.utc)


class User(Base):
    __tablename__ = "users"

    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str | None] = mapped_column(String(120))
    first_name: Mapped[str | None] = mapped_column(String(100))
    middle_initial: Mapped[str | None] = mapped_column(String(2))
    last_name: Mapped[str | None] = mapped_column(String(100))
    birthdate: Mapped[date | None] = mapped_column(Date)
    address: Mapped[str | None] = mapped_column(String(500))
    gender: Mapped[str | None] = mapped_column(String(30))
    contact_number: Mapped[str | None] = mapped_column(String(16))
    email: Mapped[str | None] = mapped_column(String(255), unique=True, index=True)
    password_hash: Mapped[str | None] = mapped_column(String(255))
    role: Mapped[str] = mapped_column(String(20), default="user")  # user / receptionist / doctor
    is_guest: Mapped[bool] = mapped_column(Boolean, default=True)
    is_demo: Mapped[bool] = mapped_column(Boolean, default=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


class Screening(Base):
    __tablename__ = "screenings"

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    angle: Mapped[float] = mapped_column(Float)
    has_scoliosis: Mapped[bool] = mapped_column(Boolean)
    photo_path: Mapped[str | None] = mapped_column(String(255))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    idempotency_key: Mapped[str | None] = mapped_column(String(64))


class Appointment(Base):
    __tablename__ = "appointments"
    __table_args__ = (
        CheckConstraint(
            "status IN ('pending', 'approved', 'rejected', 'cancelled', 'completed', 'declined')",
            name="ck_appointments_status",
        ),
        Index(
            "uq_appointments_doctor_time_active",
            "doctor_id",
            "scheduled_at",
            unique=True,
            postgresql_where=text(
                "doctor_id IS NOT NULL AND scheduled_at IS NOT NULL "
                "AND status IN ('pending', 'approved')"
            ),
            sqlite_where=text(
                "doctor_id IS NOT NULL AND scheduled_at IS NOT NULL "
                "AND status IN ('pending', 'approved')"
            ),
        ),
        Index("ix_appointments_clinic_status", "clinic_id", "status"),
        Index(
            "uq_appointments_reference",
            "reference",
            unique=True,
            postgresql_where=text("reference IS NOT NULL"),
            sqlite_where=text("reference IS NOT NULL"),
        ),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    screening_id: Mapped[int | None] = mapped_column(ForeignKey("screenings.id"))
    clinic_id: Mapped[int | None] = mapped_column(ForeignKey("clinics.id"))
    doctor_id: Mapped[int | None] = mapped_column(ForeignKey("doctor_profiles.id"))
    reference: Mapped[str | None] = mapped_column(String(24))
    status: Mapped[str] = mapped_column(String(20), default="pending")
    mode: Mapped[str | None] = mapped_column(String(20))
    scheduled_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    cancellation_reason: Mapped[str | None] = mapped_column(Text)
    cancelled_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    cancelled_by: Mapped[int | None] = mapped_column(ForeignKey("users.id"))
    room_name: Mapped[str | None] = mapped_column(String(120))
    consultation_url: Mapped[str | None] = mapped_column(String(2048))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=utcnow, onupdate=utcnow
    )
    is_demo: Mapped[bool] = mapped_column(Boolean, default=False)


class Clinic(Base):
    __tablename__ = "clinics"

    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(String(160), index=True)
    description: Mapped[str | None] = mapped_column(Text)
    address: Mapped[str] = mapped_column(String(500))
    latitude: Mapped[float | None] = mapped_column(Float)
    longitude: Mapped[float | None] = mapped_column(Float)
    phone: Mapped[str | None] = mapped_column(String(40))
    email: Mapped[str | None] = mapped_column(String(255))
    timezone: Mapped[str] = mapped_column(String(64), default="UTC")
    operating_hours: Mapped[dict | None] = mapped_column(JSON)
    supports_online: Mapped[bool] = mapped_column(Boolean, default=False)
    supports_physical: Mapped[bool] = mapped_column(Boolean, default=True)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    demo_operating_hours: Mapped[dict | None] = mapped_column(JSON)


class ClinicService(Base):
    __tablename__ = "clinic_services"
    __table_args__ = (UniqueConstraint("clinic_id", "name"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    clinic_id: Mapped[int] = mapped_column(ForeignKey("clinics.id", ondelete="CASCADE"), index=True)
    name: Mapped[str] = mapped_column(String(120))
    specialization: Mapped[str | None] = mapped_column(String(120))
    is_demo: Mapped[bool] = mapped_column(Boolean, default=False)


class ClinicStaff(Base):
    __tablename__ = "clinic_staff"
    __table_args__ = (
        UniqueConstraint("clinic_id", "user_id"),
        CheckConstraint("role IN ('receptionist', 'doctor')", name="ck_clinic_staff_role"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    clinic_id: Mapped[int] = mapped_column(ForeignKey("clinics.id", ondelete="CASCADE"), index=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    role: Mapped[str] = mapped_column(String(20))
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    is_demo: Mapped[bool] = mapped_column(Boolean, default=False)


class DoctorProfile(Base):
    __tablename__ = "doctor_profiles"
    __table_args__ = (UniqueConstraint("clinic_id", "user_id"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    clinic_id: Mapped[int] = mapped_column(ForeignKey("clinics.id", ondelete="CASCADE"), index=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    specializations: Mapped[list] = mapped_column(JSON, default=list)
    professional_info: Mapped[str | None] = mapped_column(Text)
    supports_online: Mapped[bool] = mapped_column(Boolean, default=False)
    supports_physical: Mapped[bool] = mapped_column(Boolean, default=True)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, index=True)
    is_demo: Mapped[bool] = mapped_column(Boolean, default=False)


class DoctorSchedule(Base):
    __tablename__ = "doctor_schedules"
    __table_args__ = (
        CheckConstraint("weekday BETWEEN 0 AND 6", name="ck_doctor_schedules_weekday"),
        CheckConstraint("duration_minutes BETWEEN 5 AND 240", name="ck_doctor_schedules_duration"),
        CheckConstraint("mode IN ('online', 'physical')", name="ck_doctor_schedules_mode"),
        UniqueConstraint("doctor_id", "weekday", "mode", "start_time", "end_time"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    doctor_id: Mapped[int] = mapped_column(ForeignKey("doctor_profiles.id", ondelete="CASCADE"), index=True)
    weekday: Mapped[int] = mapped_column(Integer)
    start_time: Mapped[time] = mapped_column(Time)
    end_time: Mapped[time] = mapped_column(Time)
    duration_minutes: Mapped[int] = mapped_column(Integer, default=30)
    mode: Mapped[str] = mapped_column(String(20))
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    is_demo: Mapped[bool] = mapped_column(Boolean, default=False)


class DemoAppointmentType(Base):
    __tablename__ = "demo_appointment_types"
    __table_args__ = (
        CheckConstraint("mode IN ('online', 'physical')", name="ck_demo_appointment_types_mode"),
        UniqueConstraint("clinic_id", "mode", name="uq_demo_appointment_type_clinic_mode"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    clinic_id: Mapped[int] = mapped_column(
        ForeignKey("clinics.id", ondelete="CASCADE"), index=True
    )
    mode: Mapped[str] = mapped_column(String(20))
    name: Mapped[str] = mapped_column(String(120))
    simulation_only: Mapped[bool] = mapped_column(Boolean, default=True)


class ScheduleException(Base):
    __tablename__ = "schedule_exceptions"
    __table_args__ = (
        CheckConstraint(
            "(start_time IS NULL AND end_time IS NULL) OR "
            "(start_time IS NOT NULL AND end_time IS NOT NULL AND start_time < end_time)",
            name="ck_schedule_exceptions_time_range",
        ),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    doctor_id: Mapped[int] = mapped_column(ForeignKey("doctor_profiles.id", ondelete="CASCADE"), index=True)
    exception_date: Mapped[date] = mapped_column(Date, index=True)
    start_time: Mapped[time | None] = mapped_column(Time)
    end_time: Mapped[time | None] = mapped_column(Time)
    reason: Mapped[str | None] = mapped_column(String(250))


class Notification(Base):
    __tablename__ = "notifications"
    __table_args__ = (
        UniqueConstraint(
            "recipient_id", "appointment_id", "event_type",
            name="uq_notifications_recipient_appointment_event",
        ),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    recipient_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    appointment_id: Mapped[int] = mapped_column(ForeignKey("appointments.id", ondelete="CASCADE"), index=True)
    event_type: Mapped[str] = mapped_column(String(30))
    title: Mapped[str] = mapped_column(String(160))
    message: Mapped[str] = mapped_column(String(500))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    read_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class Message(Base):
    __tablename__ = "messages"

    id: Mapped[int] = mapped_column(primary_key=True)
    patient_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    sender_id: Mapped[int] = mapped_column(ForeignKey("users.id"))
    body: Mapped[str] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)