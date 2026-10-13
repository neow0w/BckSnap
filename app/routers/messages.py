from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session

from ..database import get_db
from ..models import Message, User
from ..schemas import InboxItem, MessageCreate, MessageOut
from ..security import require_roles

router = APIRouter(prefix="/messages", tags=["messages"])


def _out(m: Message) -> MessageOut:
    return MessageOut(
        id=m.id,
        patient_id=m.patient_id,
        from_clinic=m.sender_id != m.patient_id,
        body=m.body,
        created_at=m.created_at,
    )


def _thread(patient_id: int, db: Session) -> list[MessageOut]:
    rows = db.scalars(
        select(Message)
        .where(Message.patient_id == patient_id)
        .order_by(Message.created_at.asc(), Message.id.asc())
    ).all()
    return [_out(m) for m in rows]


def _get_patient(patient_id: int, db: Session) -> User:
    patient = db.get(User, patient_id)
    if patient is None or patient.role != "user":
        raise HTTPException(status_code=404, detail="Patient not found")
    return patient


# Fig 8: "Send a message to the clinic"
@router.post("", response_model=MessageOut)
def send_to_clinic(
    data: MessageCreate,
    db: Session = Depends(get_db),
    user: User = Depends(require_roles("user")),
):
    if user.is_guest:
        raise HTTPException(
            status_code=403, detail="Please sign up before messaging the clinic"
        )
    msg = Message(patient_id=user.id, sender_id=user.id, body=data.body.strip())
    db.add(msg)
    db.commit()
    db.refresh(msg)
    return _out(msg)


# The patient's own conversation with the clinic
@router.get("/mine", response_model=list[MessageOut])
def my_thread(
    db: Session = Depends(get_db), user: User = Depends(require_roles("user"))
):
    return _thread(user.id, db)


# Receptionist inbox: one row per patient, newest conversation first
@router.get("/inbox", response_model=list[InboxItem])
def inbox(
    db: Session = Depends(get_db),
    staff: User = Depends(require_roles("receptionist")),
):
    rows = db.scalars(
        select(Message).order_by(Message.created_at.desc(), Message.id.desc())
    ).all()
    seen: set[int] = set()
    items: list[InboxItem] = []
    for m in rows:
        if m.patient_id in seen:
            continue
        seen.add(m.patient_id)
        patient = db.get(User, m.patient_id)
        items.append(
            InboxItem(
                patient_id=m.patient_id,
                patient_name=patient.name if patient else None,
                last_message=m.body,
                last_at=m.created_at,
                from_clinic=m.sender_id != m.patient_id,
            )
        )
    return items


@router.get("/patient/{patient_id}", response_model=list[MessageOut])
def patient_thread(
    patient_id: int,
    db: Session = Depends(get_db),
    staff: User = Depends(require_roles("receptionist")),
):
    _get_patient(patient_id, db)
    return _thread(patient_id, db)


# Fig 9: the receptionist contacts the patient
@router.post("/patient/{patient_id}", response_model=MessageOut)
def reply_to_patient(
    patient_id: int,
    data: MessageCreate,
    db: Session = Depends(get_db),
    staff: User = Depends(require_roles("receptionist")),
):
    _get_patient(patient_id, db)
    msg = Message(patient_id=patient_id, sender_id=staff.id, body=data.body.strip())
    db.add(msg)
    db.commit()
    db.refresh(msg)
    return _out(msg)    