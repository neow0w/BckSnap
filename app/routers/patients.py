from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session

from ..database import get_db
from ..models import Appointment, Screening, User
from ..schemas import PatientOut, UserOut
from ..security import require_roles
from .screenings import _to_out as screening_out

router = APIRouter(prefix="/patients", tags=["patients"])


# Fig 10: "View a patient's profile?" -> "Display patient information"
# A doctor can only open patients who have an approved appointment.
@router.get("/{user_id}", response_model=PatientOut)
def patient_profile(
    user_id: int,
    db: Session = Depends(get_db),
    doctor: User = Depends(require_roles("doctor")),
):
    patient = db.get(User, user_id)
    has_approved = db.scalar(
        select(Appointment.id)
        .where(Appointment.user_id == user_id, Appointment.status == "approved")
        .limit(1)
    )
    if patient is None or patient.role != "user" or has_approved is None:
        raise HTTPException(status_code=404, detail="Patient not found")

    screenings = db.scalars(
        select(Screening)
        .where(Screening.user_id == user_id)
        .order_by(Screening.created_at.desc())
    ).all()
    return PatientOut(
        user=UserOut.model_validate(patient),
        screenings=[screening_out(s) for s in screenings],
    )