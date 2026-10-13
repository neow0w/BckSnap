import secrets
from pathlib import Path

from fastapi import APIRouter, Depends, File, Form, Header, HTTPException, UploadFile
from fastapi.responses import FileResponse
from sqlalchemy.exc import IntegrityError, SQLAlchemyError
from sqlalchemy import select
from sqlalchemy.orm import Session

from ..config import settings
from ..database import get_db
from ..models import Screening, User
from ..schemas import ScreeningOut
from ..security import get_current_user

router = APIRouter(prefix="/screenings", tags=["screenings"])

UPLOAD_DIR = Path(settings.upload_dir)
UPLOAD_DIR.mkdir(exist_ok=True)

STAFF_ROLES = ("receptionist", "doctor")


def _to_out(s: Screening) -> ScreeningOut:
    return ScreeningOut(
        id=s.id,
        user_id=s.user_id,
        angle=s.angle,
        has_scoliosis=s.has_scoliosis,
        has_photo=s.photo_path is not None,
        created_at=s.created_at,
    )


def _detect_extension(data: bytes) -> str | None:
    """Identify the image type from its first bytes, not from its name."""
    if data.startswith(b"\xff\xd8\xff"):
        return ".jpg"
    if data.startswith(b"\x89PNG\r\n\x1a\n"):
        return ".png"
    if data[:4] == b"RIFF" and data[8:12] == b"WEBP":
        return ".webp"
    return None


def _get_allowed(screening_id: int, db: Session, user: User) -> Screening:
    s = db.get(Screening, screening_id)
    # Same "not found" answer whether it is missing or not yours.
    if s is None or (s.user_id != user.id and user.role not in STAFF_ROLES):
        raise HTTPException(status_code=404, detail="Screening not found")
    return s


# Fig 7: "Generate and display the result of the scoliosis screening"
@router.post("", response_model=ScreeningOut)
def create_screening(
    angle: float = Form(...),
    photo: UploadFile | None = File(None),
    idempotency_key: str | None = Header(
        default=None, alias="Idempotency-Key", min_length=1, max_length=64
    ),
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    if not 0 <= angle <= 90:
        raise HTTPException(status_code=422, detail="Angle must be between 0 and 90")

    if idempotency_key is not None:
        existing = db.scalar(
            select(Screening).where(
                Screening.user_id == user.id,
                Screening.idempotency_key == idempotency_key,
            )
        )
        if existing is not None:
            if existing.angle != angle:
                raise HTTPException(
                    status_code=409,
                    detail="This screening request key was already used for another result",
                )
            return _to_out(existing)

    filename = None
    photo_path = None
    if photo is not None and photo.filename:
        max_bytes = settings.max_photo_mb * 1024 * 1024
        data = photo.file.read(max_bytes + 1)
        if len(data) > max_bytes:
            raise HTTPException(
                status_code=413,
                detail=f"Photo is larger than {settings.max_photo_mb} MB",
            )
        ext = _detect_extension(data)
        if ext is None:
            raise HTTPException(
                status_code=400, detail="Photo must be a JPEG, PNG, or WebP image"
            )
        filename = f"{secrets.token_hex(16)}{ext}"
        photo_path = UPLOAD_DIR / filename
        photo_path.write_bytes(data)

    screening = Screening(
        user_id=user.id,
        angle=angle,
        has_scoliosis=angle >= settings.scoliosis_threshold,
        photo_path=filename,
        idempotency_key=idempotency_key,
    )
    db.add(screening)
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        if idempotency_key is not None:
            existing = db.scalar(
                select(Screening).where(
                    Screening.user_id == user.id,
                    Screening.idempotency_key == idempotency_key,
                )
            )
            if existing is not None:
                if photo_path is not None:
                    photo_path.unlink(missing_ok=True)
                if existing.angle != angle:
                    raise HTTPException(
                        status_code=409,
                        detail="This screening request key was already used for another result",
                    )
                return _to_out(existing)
        if photo_path is not None:
            photo_path.unlink(missing_ok=True)
        raise
    except SQLAlchemyError:
        db.rollback()
        if photo_path is not None:
            photo_path.unlink(missing_ok=True)
        raise
    db.refresh(screening)
    return _to_out(screening)


# Note: "/mine" must be defined before "/{screening_id}".
@router.get("/mine", response_model=list[ScreeningOut])
def my_screenings(
    db: Session = Depends(get_db), user: User = Depends(get_current_user)
):
    rows = db.scalars(
        select(Screening)
        .where(Screening.user_id == user.id)
        .order_by(Screening.created_at.desc())
    ).all()
    return [_to_out(s) for s in rows]


@router.get("/{screening_id}", response_model=ScreeningOut)
def get_screening(
    screening_id: int,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    return _to_out(_get_allowed(screening_id, db, user))


# The photo is private health data, so it is served only to its owner
# and to clinic staff, never from a public folder.
@router.get("/{screening_id}/photo")
def get_photo(
    screening_id: int,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    s = _get_allowed(screening_id, db, user)
    if not s.photo_path:
        raise HTTPException(status_code=404, detail="No photo for this screening")
    path = UPLOAD_DIR / s.photo_path
    if not path.is_file():
        raise HTTPException(status_code=404, detail="Photo file is missing")
    return FileResponse(path)