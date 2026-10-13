from __future__ import annotations

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.database import SessionLocal
from app.models import Clinic, ClinicService


CLINICS = (
    {
        "name": "Physio Point Physical Therapy and Rehab Medicine Clinic Sta. Rosa",
        "address": (
            "Banawe De Santa Rosa Building, Purok 6, Units A17, A16, and A15, "
            "F. Reyes Street, Balibago, City of Santa Rosa, 4026 Laguna, Philippines"
        ),
        "phone": "0999 227 4014",
        "description": (
            "Clinic category and services were supplied for this listing. "
            "Contact the clinic to confirm current services and appointment availability."
        ),
        "services": ("Physical therapy", "Rehabilitation medicine"),
    },
    {
        "name": "MEDI-SKY Diagnostic Center and Multi-Specialty Clinic",
        "address": "718 Rizal Boulevard, City of Santa Rosa, 4026 Laguna, Philippines",
        "phone": "0950 282 5622",
        "description": (
            "The diagnostic center and multi-specialty clinic category was supplied "
            "for this listing. Specific services, specialties, and appointment "
            "availability have not been verified."
        ),
        "services": (),
    },
)


def seed_clinics(db: Session) -> list[Clinic]:
    seeded = []
    for data in CLINICS:
        matches = db.scalars(
            select(Clinic).where(Clinic.name == data["name"])
        ).all()
        if len(matches) > 1:
            raise RuntimeError(
                f"Multiple clinic records match the seed name: {data['name']}"
            )

        if matches:
            clinic = matches[0]
            clinic.address = data["address"]
            clinic.phone = data["phone"]
            clinic.description = data["description"]
        else:
            clinic = Clinic(
                name=data["name"],
                address=data["address"],
                phone=data["phone"],
                description=data["description"],
                timezone="Asia/Manila",
                latitude=None,
                longitude=None,
                operating_hours=None,
                supports_online=False,
                supports_physical=False,
                is_active=True,
            )
            db.add(clinic)
            db.flush()

        existing_services = {
            name.casefold()
            for name in db.scalars(
                select(ClinicService.name).where(
                    ClinicService.clinic_id == clinic.id
                )
            ).all()
        }
        for service_name in data["services"]:
            if service_name.casefold() not in existing_services:
                db.add(ClinicService(clinic_id=clinic.id, name=service_name))

        seeded.append(clinic)

    db.commit()
    for clinic in seeded:
        db.refresh(clinic)
    return seeded


def main() -> None:
    with SessionLocal() as db:
        for clinic in seed_clinics(db):
            print(f"Clinic ID {clinic.id}: {clinic.name}")


if __name__ == "__main__":
    main()
