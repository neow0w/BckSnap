from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from ..database import get_db
from ..models import User
from ..schemas import (
    LoginRequest,
    ResetConfirm,
    ResetRequest,
    SignUpRequest,
    TokenOut,
    UserOut,
)
from ..security import (
    create_access_token,
    create_reset_token,
    decode_reset_token,
    get_current_user,
    get_optional_user,
    hash_password,
    verify_password,
)

router = APIRouter(prefix="/auth", tags=["auth"])


def _token_response(user: User) -> TokenOut:
    return TokenOut(
        access_token=create_access_token(user.id),
        user=UserOut.model_validate(user),
    )


# Fig 7: "Start Screening" creates a temporary guest account.
@router.post("/guest", response_model=TokenOut)
def create_guest(db: Session = Depends(get_db)):
    user = User(is_guest=True, role="user")
    db.add(user)
    db.commit()
    db.refresh(user)
    return _token_response(user)


# Fig 7: Sign up. A guest is upgraded (same account, same screenings).
@router.post("/signup", response_model=TokenOut)
def signup(
    data: SignUpRequest,
    db: Session = Depends(get_db),
    current: User | None = Depends(get_optional_user),
):
    email = data.email.lower()
    if db.scalar(select(User.id).where(func.lower(User.email) == email)) is not None:
        raise HTTPException(status_code=409, detail="That email is already registered")

    if current is not None and current.is_guest:
        user = current  # upgrade the guest
    else:
        user = User(role="user")
        db.add(user)

    user.first_name = data.first_name
    user.middle_initial = data.middle_initial
    user.last_name = data.last_name
    user.birthdate = data.birthdate
    user.address = data.address
    user.gender = data.gender
    user.contact_number = data.contact_number
    user.name = " ".join(
        part
        for part in (
            data.first_name,
            f"{data.middle_initial}." if data.middle_initial else "",
            data.last_name,
        )
        if part
    )
    user.email = email
    user.password_hash = hash_password(data.password)
    user.is_guest = False
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        if db.scalar(select(User.id).where(func.lower(User.email) == email)) is not None:
            raise HTTPException(
                status_code=409, detail="That email is already registered"
            ) from None
        raise
    db.refresh(user)
    return _token_response(user)


# Fig 7: Login. The response includes the role, which answers
# "Is the user an admin?"
@router.post("/login", response_model=TokenOut)
def login(data: LoginRequest, db: Session = Depends(get_db)):
    user = db.scalar(select(User).where(func.lower(User.email) == data.email.lower()))
    if (
        user is None
        or user.password_hash is None
        or not verify_password(data.password, user.password_hash)
    ):
        raise HTTPException(status_code=401, detail="Incorrect email or password")
    return _token_response(user)


@router.get("/me", response_model=UserOut)
def me(user: User = Depends(get_current_user)):
    return user


# Fig 7: "Password reset email sent".
# During development the reset link is printed in the terminal.
# Real email sending comes later.
@router.post("/forgot-password")
def forgot_password(data: ResetRequest, db: Session = Depends(get_db)):
    user = db.scalar(select(User).where(func.lower(User.email) == data.email.lower()))
    if user is not None:
        token = create_reset_token(user.id)
        print(f"\n[DEV] Password reset token for {user.email}:\n{token}\n")
    # Same answer either way, so the API never reveals which emails exist.
    return {"message": "If an account exists for that email, a reset link has been sent."}


@router.post("/reset-password")
def reset_password(data: ResetConfirm, db: Session = Depends(get_db)):
    user_id = decode_reset_token(data.token)
    user = db.get(User, user_id) if user_id is not None else None
    if user is None:
        raise HTTPException(status_code=400, detail="Invalid or expired reset link")
    user.password_hash = hash_password(data.new_password)
    db.commit()
    return {"message": "Password updated"}