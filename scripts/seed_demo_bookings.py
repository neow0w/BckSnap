from __future__ import annotations

import argparse
from datetime import time

from sqlalchemy import or_, select
from sqlalchemy.orm import Session

from app.database import SessionLocal
from app.models import (
    Appointment,
    Clinic,
    ClinicService,
    ClinicStaff,
    DemoAppointmentType,
    DoctorProfile,
    DoctorSchedule,
    Message,
    Notification,
    Screening,
    User,
)

DEMO_CLINIC_NAMES = (
    "Physio Point Physical Therapy and Rehab Medicine Clinic Sta. Rosa",
    "MEDI-SKY Diagnostic Center and Multi-Specialty Clinic",
)
DEMO_HOURS = {
    day: [{"open": "09:00", "close": "12:00"}, {"open": "13:00", "close": "17:00"}]
    for day in ("monday", "tuesday", "wednesday", "thursday", "friday")
}
DEMO_HOURS["saturday"] = [{"open": "09:00", "close": "12:00"}]
DEMO_HOURS["sunday"] = []
DEMO_MODES = {
    "physical": "Physical / in-person appointment (DEMO)",
    "online": "Online appointment — SIMULATED DEMO ONLY",
}
PROVIDERS = (
    {
        "email": "demo.physio.maya@bcksnap.invalid",
        "name": "DEMO — Dr. Maya Santos (fictional)",
        "clinic": DEMO_CLINIC_NAMES[0],
        "specializations": ["Physical Therapy", "Rehabilitation Medicine"],
        "professional_info": "Fictional provider and profile for development demonstration only.",
        "saturday": True,
    },
    {
        "email": "demo.physio.luis@bcksnap.invalid",
        "name": "DEMO — Dr. Luis Reyes (fictional)",
        "clinic": DEMO_CLINIC_NAMES[0],
        "specializations": ["Physical Therapy"],
        "professional_info": "Fictional provider and profile for development demonstration only.",
        "saturday": False,
    },
    {
        "email": "demo.medisky.bianca@bcksnap.invalid",
        "name": "DEMO — Dr. Bianca Cruz (fictional)",
        "clinic": DEMO_CLINIC_NAMES[1],
        "specializations": ["Orthopedics"],
        "professional_info": "Fictional provider and profile for development demonstration only.",
        "saturday": True,
    },
    {
        "email": "demo.medisky.paolo@bcksnap.invalid",
        "name": "DEMO — Dr. Paolo Dela Rosa (fictional)",
        "clinic": DEMO_CLINIC_NAMES[1],
        "specializations": ["Rehabilitation Medicine"],
        "professional_info": "Fictional provider and profile for development demonstration only.",
        "saturday": False,
    },
)


def _get_clinics(db: Session) -> dict[str, Clinic]:
    clinics = db.scalars(
        select(Clinic).where(Clinic.name.in_(DEMO_CLINIC_NAMES))
    ).all()
    by_name = {clinic.name: clinic for clinic in clinics}
    missing = set(DEMO_CLINIC_NAMES) - by_name.keys()
    if missing:
        raise RuntimeError(
            "Seed the supplied clinic directory first; missing clinic listing(s): "
            + ", ".join(sorted(missing))
        )
    return by_name


def seed_demo_bookings(db: Session) -> list[DoctorProfile]:
    clinics = _get_clinics(db)
    for clinic in clinics.values():
        clinic.demo_operating_hours = DEMO_HOURS
        for mode, name in DEMO_MODES.items():
            appointment_type = db.scalar(
                select(DemoAppointmentType).where(
                    DemoAppointmentType.clinic_id == clinic.id,
                    DemoAppointmentType.mode == mode,
                )
            )
            if appointment_type is None:
                db.add(
                    DemoAppointmentType(
                        clinic_id=clinic.id,
                        mode=mode,
                        name=name,
                        simulation_only=True,
                    )
                )
            else:
                appointment_type.name = name
                appointment_type.simulation_only = True
    demo_services = {
        DEMO_CLINIC_NAMES[0]: (
            "DEMO — Physical Therapy",
            "DEMO — Rehabilitation Medicine",
        ),
        DEMO_CLINIC_NAMES[1]: (
            "DEMO — Orthopedics",
            "DEMO — Rehabilitation Medicine",
        ),
    }
    for clinic_name, service_names in demo_services.items():
        clinic = clinics[clinic_name]
        for name in service_names:
            service = db.scalar(
                select(ClinicService).where(
                    ClinicService.clinic_id == clinic.id,
                    ClinicService.name == name,
                )
            )
            if service is None:
                db.add(
                    ClinicService(
                        clinic_id=clinic.id,
                        name=name,
                        specialization=name.removeprefix("DEMO — "),
                        is_demo=True,
                    )
                )
            elif not service.is_demo:
                raise RuntimeError(
                    f"Refusing to mark non-demo clinic service {name!r} as demo."
                )
    db.flush()

    seeded: list[DoctorProfile] = []
    for provider in PROVIDERS:
        clinic = clinics[provider["clinic"]]
        user = db.scalar(select(User).where(User.email == provider["email"]))
        if user is None:
            user = User(
                name=provider["name"],
                email=provider["email"],
                password_hash=None,
                role="doctor",
                is_guest=False,
                is_demo=True,
            )
            db.add(user)
            db.flush()
        elif not user.is_demo:
            raise RuntimeError(
                f"The reserved demo email {provider['email']} belongs to a non-demo user."
            )
        else:
            user.name = provider["name"]

        doctor = db.scalar(
            select(DoctorProfile).where(
                DoctorProfile.clinic_id == clinic.id,
                DoctorProfile.user_id == user.id,
            )
        )
        if doctor is None:
            doctor = DoctorProfile(
                clinic_id=clinic.id,
                user_id=user.id,
                specializations=list(provider["specializations"]),
                professional_info=provider["professional_info"],
                supports_online=False,
                supports_physical=False,
                is_active=True,
                is_demo=True,
            )
            db.add(doctor)
            db.flush()
        elif not doctor.is_demo:
            raise RuntimeError(
                f"Existing profile for {provider['email']} is not marked as demo."
            )
        else:
            doctor.specializations = list(provider["specializations"])
            doctor.professional_info = provider["professional_info"]
            doctor.is_active = True

        staff = db.scalar(
            select(ClinicStaff).where(
                ClinicStaff.clinic_id == clinic.id,
                ClinicStaff.user_id == user.id,
            )
        )
        if staff is None:
            db.add(
                ClinicStaff(
                    clinic_id=clinic.id,
                    user_id=user.id,
                    role="doctor",
                    is_active=True,
                    is_demo=True,
                )
            )
        elif not staff.is_demo:
            raise RuntimeError(
                f"Existing clinic staff membership for {provider['email']} is not demo data."
            )

        weekdays = list(range(5)) + ([5] if provider["saturday"] else [])
        for weekday in weekdays:
            blocks = (
                ((9, 12), (13, 17))
                if weekday < 5
                else ((9, 12),)
            )
            for mode in DEMO_MODES:
                for starts, ends in blocks:
                    start_time = time(starts)
                    end_time = time(ends)
                    schedule = db.scalar(
                        select(DoctorSchedule).where(
                            DoctorSchedule.doctor_id == doctor.id,
                            DoctorSchedule.weekday == weekday,
                            DoctorSchedule.mode == mode,
                            DoctorSchedule.start_time == start_time,
                            DoctorSchedule.end_time == end_time,
                        )
                    )
                    if schedule is None:
                        db.add(
                            DoctorSchedule(
                                doctor_id=doctor.id,
                                weekday=weekday,
                                start_time=start_time,
                                end_time=end_time,
                                duration_minutes=30,
                                mode=mode,
                                is_active=True,
                                is_demo=True,
                            )
                        )
                    elif not schedule.is_demo:
                        raise RuntimeError(
                            f"Refusing to replace a non-demo schedule for {provider['name']}."
                        )
                    else:
                        schedule.is_active = True
        seeded.append(doctor)

    db.commit()
    return seeded


def cleanup_demo_bookings(db: Session) -> None:
    clinics = _get_clinics(db)
    doctors = db.scalars(
        select(DoctorProfile).where(
            DoctorProfile.clinic_id.in_([clinic.id for clinic in clinics.values()]),
            DoctorProfile.is_demo.is_(True),
        )
    ).all()
    doctor_ids = [doctor.id for doctor in doctors]
    user_ids = [doctor.user_id for doctor in doctors]
    appointment_reference = (
        or_(
            Appointment.doctor_id.in_(doctor_ids),
            Appointment.user_id.in_(user_ids),
            Appointment.cancelled_by.in_(user_ids),
        )
        if user_ids
        else None
    )
    has_related_records = bool(
        appointment_reference is not None
        and db.scalar(
            select(Appointment.id).where(appointment_reference).limit(1)
        )
    )
    has_related_records |= bool(
        user_ids
        and db.scalar(select(Screening.id).where(Screening.user_id.in_(user_ids)).limit(1))
    )
    has_related_records |= bool(
        user_ids
        and db.scalar(
            select(Notification.id)
            .where(Notification.recipient_id.in_(user_ids))
            .limit(1)
        )
    )
    has_related_records |= bool(
        user_ids
        and db.scalar(
            select(Message.id)
            .where(
                or_(
                    Message.patient_id.in_(user_ids),
                    Message.sender_id.in_(user_ids),
                )
            )
            .limit(1)
        )
    )
    if has_related_records:
        raise RuntimeError(
            "Cleanup refused: demo accounts or providers are referenced by "
            "appointments, screenings, notifications, or messages. "
            "Cleanup never deletes or detaches user records."
        )

    for doctor in doctors:
        db.query(DoctorSchedule).filter(
            DoctorSchedule.doctor_id == doctor.id,
            DoctorSchedule.is_demo.is_(True),
        ).delete(synchronize_session=False)
        db.query(ClinicStaff).filter(
            ClinicStaff.user_id == doctor.user_id,
            ClinicStaff.clinic_id == doctor.clinic_id,
            ClinicStaff.is_demo.is_(True),
        ).delete(synchronize_session=False)
        db.delete(doctor)
    for clinic in clinics.values():
        clinic.demo_operating_hours = None
        db.query(ClinicService).filter(
            ClinicService.clinic_id == clinic.id,
            ClinicService.is_demo.is_(True),
        ).delete(synchronize_session=False)
        db.query(DemoAppointmentType).filter(
            DemoAppointmentType.clinic_id == clinic.id
        ).delete(synchronize_session=False)
    db.flush()
    if user_ids:
        db.query(User).filter(User.id.in_(user_ids), User.is_demo.is_(True)).delete(
            synchronize_session=False
        )
    db.commit()


def main() -> None:
    parser = argparse.ArgumentParser(description="Seed or clean development-only booking data.")
    parser.add_argument(
        "action", choices=("seed", "cleanup"), nargs="?", default="seed"
    )
    args = parser.parse_args()
    with SessionLocal() as db:
        if args.action == "cleanup":
            cleanup_demo_bookings(db)
            print("Removed demo schedules, providers, visit types, and demo hours.")
        else:
            doctors = seed_demo_bookings(db)
            print(f"Seeded {len(doctors)} fictional development-only providers.")


if __name__ == "__main__":
    main()
