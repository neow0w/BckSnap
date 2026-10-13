from datetime import date, datetime, time
import re
from typing import Literal
from pydantic import BaseModel, EmailStr, Field, field_validator, model_validator


class SignUpRequest(BaseModel):
    first_name: str = Field(min_length=1, max_length=100)
    middle_initial: str | None = Field(default=None, max_length=2)
    last_name: str = Field(min_length=1, max_length=100)
    birthdate: date
    address: str = Field(min_length=1, max_length=500)
    gender: Literal["male", "female", "prefer_not_to_say"]
    email: EmailStr
    contact_number: str = Field(min_length=1, max_length=32)
    password: str = Field(min_length=8, max_length=72)
    confirm_password: str = Field(min_length=8, max_length=72)

    @field_validator("first_name", "last_name")
    @classmethod
    def trim_required_names(cls, value: str) -> str:
        value = " ".join(value.split())
        if not value:
            raise ValueError("This field is required")
        return value

    @field_validator("middle_initial", mode="before")
    @classmethod
    def normalize_middle_initial(cls, value: str | None) -> str | None:
        if value is None:
            return None
        value = value.strip()
        if not value:
            return None
        if re.fullmatch(r"[A-Za-z]\.?", value) is None:
            raise ValueError("Enter one letter, optionally followed by a period")
        return value[0].upper()

    @field_validator("birthdate")
    @classmethod
    def reject_future_birthdate(cls, value: date) -> date:
        if value > date.today():
            raise ValueError("Birthdate cannot be in the future")
        return value

    @field_validator("address")
    @classmethod
    def normalize_address(cls, value: str) -> str:
        value = " ".join(value.split())
        if not value:
            raise ValueError("Address is required")
        return value

    @field_validator("email", mode="before")
    @classmethod
    def normalize_email(cls, value: str) -> str:
        if not isinstance(value, str):
            return value
        return value.strip().lower()

    @field_validator("contact_number")
    @classmethod
    def normalize_philippine_mobile(cls, value: str) -> str:
        compact = re.sub(r"[\s()-]", "", value)
        if re.fullmatch(r"09\d{9}", compact):
            return f"+63{compact[1:]}"
        if re.fullmatch(r"\+639\d{9}", compact):
            return compact
        raise ValueError(
            "Enter a valid Philippine mobile number, such as 09XXXXXXXXX or +639XXXXXXXXX"
        )

    @field_validator("password")
    @classmethod
    def password_must_fit_bcrypt(cls, value: str) -> str:
        if len(value.encode("utf-8")) > 72:
            raise ValueError("Password must be no more than 72 UTF-8 bytes")
        return value

    @model_validator(mode="after")
    def validate_confirmation_and_full_name(self):
        if self.password != self.confirm_password:
            raise ValueError("Password and confirmation do not match")
        display_name = " ".join(
            part
            for part in (
                self.first_name,
                f"{self.middle_initial}." if self.middle_initial else "",
                self.last_name,
            )
            if part
        )
        if len(display_name) > 120:
            raise ValueError("Combined name must be 120 characters or fewer")
        return self


class LoginRequest(BaseModel):
    email: EmailStr
    password: str = Field(max_length=72)

    @field_validator("email", mode="before")
    @classmethod
    def normalize_email(cls, value: str) -> str:
        return value.strip().lower() if isinstance(value, str) else value


class ResetRequest(BaseModel):
    email: EmailStr

    @field_validator("email", mode="before")
    @classmethod
    def normalize_email(cls, value: str) -> str:
        return value.strip().lower() if isinstance(value, str) else value


class UserOut(BaseModel):
    id: int
    name: str | None
    first_name: str | None = None
    middle_initial: str | None = None
    last_name: str | None = None
    birthdate: date | None = None
    address: str | None = None
    gender: str | None = None
    contact_number: str | None = None
    email: str | None
    role: str
    is_guest: bool

    model_config = {"from_attributes": True}


class TokenOut(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user: UserOut

class ResetConfirm(BaseModel):
    token: str
    new_password: str = Field(min_length=6, max_length=72)

class ScreeningOut(BaseModel):
    id: int
    user_id: int
    angle: float
    has_scoliosis: bool
    has_photo: bool
    created_at: datetime

class AppointmentCreate(BaseModel):
    screening_id: int | None = None
    clinic_id: int | None = Field(default=None, gt=0)
    doctor_id: int | None = Field(default=None, gt=0)
    mode: Literal["online", "physical"] | None = None
    scheduled_at: datetime | None = None


class AppointmentApprove(BaseModel):
    mode: Literal["online", "physical"] | None = None
    scheduled_at: datetime | None = None
    consultation_url: str | None = Field(default=None, max_length=2048)

class AppointmentOut(BaseModel):
    id: int
    user_id: int
    patient_name: str | None
    screening_id: int | None
    status: str
    mode: str | None
    scheduled_at: datetime | None
    room_name: str | None
    created_at: datetime
    updated_at: datetime
    clinic_id: int | None = None
    clinic_name: str | None = None
    clinic_address: str | None = None
    doctor_id: int | None = None
    doctor_name: str | None = None
    reference: str | None = None
    cancellation_reason: str | None = None
    cancelled_at: datetime | None = None
    is_demo: bool = False

    model_config = {"from_attributes": True}


class AppointmentCancel(BaseModel):
    reason: str = Field(min_length=1, max_length=1000)

    @field_validator("reason")
    @classmethod
    def reason_must_not_be_blank(cls, value: str) -> str:
        value = value.strip()
        if not value:
            raise ValueError("A cancellation reason is required")
        return value

class RoomOut(BaseModel):
    room_name: str


class ConsultationOut(BaseModel):
    consultation_url: str


class ClinicServiceOut(BaseModel):
    id: int
    name: str
    specialization: str | None
    is_demo: bool = False

    model_config = {"from_attributes": True}


class DoctorOut(BaseModel):
    id: int
    user_id: int
    name: str | None
    specializations: list[str]
    professional_info: str | None
    supports_online: bool
    supports_physical: bool
    is_demo: bool = False


class DemoAppointmentTypeOut(BaseModel):
    mode: Literal["online", "physical"]
    name: str
    simulation_only: bool

    model_config = {"from_attributes": True}


class ClinicOut(BaseModel):
    id: int
    name: str
    description: str | None
    address: str
    latitude: float | None
    longitude: float | None
    phone: str | None
    email: str | None
    timezone: str
    operating_hours: dict[str, dict[str, str]] | None
    supports_online: bool
    supports_physical: bool
    demo_operating_hours: dict[str, list[dict[str, str | int]]] | None = None
    demo_appointment_types: list[DemoAppointmentTypeOut] = Field(default_factory=list)
    services: list[ClinicServiceOut] = Field(default_factory=list)
    doctors: list[DoctorOut] = Field(default_factory=list)
    distance_km: float | None = None


class ClinicCreate(BaseModel):
    name: str = Field(min_length=2, max_length=160)
    description: str | None = Field(default=None, max_length=4000)
    address: str = Field(min_length=3, max_length=500)
    latitude: float | None = Field(default=None, ge=-90, le=90)
    longitude: float | None = Field(default=None, ge=-180, le=180)
    phone: str | None = Field(default=None, max_length=40)
    email: str | None = Field(default=None, max_length=255)
    timezone: str = Field(default="UTC", min_length=1, max_length=64)
    operating_hours: dict[str, dict[str, str]] | None = None
    supports_online: bool = False
    supports_physical: bool = True
    services: list[str] = Field(default_factory=list, max_length=50)

    @field_validator("longitude")
    @classmethod
    def coordinates_must_be_paired(cls, value, info):
        latitude = info.data.get("latitude")
        if (latitude is None) != (value is None):
            raise ValueError("Latitude and longitude must be provided together")
        return value

    @field_validator("operating_hours")
    @classmethod
    def validate_operating_hours(cls, value):
        if value is None:
            return value
        weekdays = {
            "monday",
            "tuesday",
            "wednesday",
            "thursday",
            "friday",
            "saturday",
            "sunday",
        }
        for day, hours in value.items():
            if day not in weekdays:
                raise ValueError(f"Unknown weekday: {day}")
            if hours.get("closed") is True:
                continue
            try:
                opens = time.fromisoformat(hours["open"])
                closes = time.fromisoformat(hours["close"])
            except (KeyError, TypeError, ValueError):
                raise ValueError(
                    f"{day} must have valid open and close times"
                ) from None
            if closes <= opens:
                raise ValueError(f"{day} closing time must be after opening time")
        return value


class ClinicSearchOut(BaseModel):
    items: list[ClinicOut]


class GeocodeResult(BaseModel):
    label: str
    latitude: float
    longitude: float


class SlotOut(BaseModel):
    starts_at: datetime
    ends_at: datetime
    mode: Literal["online", "physical"]


class NotificationOut(BaseModel):
    id: int
    appointment_id: int
    event_type: str
    title: str
    message: str
    created_at: datetime
    read_at: datetime | None

    model_config = {"from_attributes": True}


class ScheduleCreate(BaseModel):
    weekday: int = Field(ge=0, le=6)
    start_time: time
    end_time: time
    duration_minutes: int = Field(default=30, ge=5, le=240)
    mode: Literal["online", "physical"]

    @field_validator("end_time")
    @classmethod
    def end_must_follow_start(cls, value: time, info):
        start = info.data.get("start_time")
        if start is not None and value <= start:
            raise ValueError("Schedule end time must be after its start time")
        return value


class DoctorCreate(BaseModel):
    user_id: int = Field(gt=0)
    specializations: list[str] = Field(default_factory=list, max_length=20)
    professional_info: str | None = Field(default=None, max_length=4000)
    supports_online: bool = False
    supports_physical: bool = True


class ClinicStaffCreate(BaseModel):
    user_id: int = Field(gt=0)


class ScheduleExceptionCreate(BaseModel):
    exception_date: date
    start_time: time | None = None
    end_time: time | None = None
    reason: str | None = Field(default=None, max_length=250)

    @field_validator("end_time")
    @classmethod
    def exception_times_must_be_paired(cls, value, info):
        start = info.data.get("start_time")
        if (start is None) != (value is None):
            raise ValueError("Exception start and end times must be provided together")
        if start is not None and value is not None and value <= start:
            raise ValueError("Exception end time must be after its start time")
        return value


class NotificationRead(BaseModel):
    read: bool = True

class PatientOut(BaseModel):
    user: UserOut
    screenings: list[ScreeningOut]

class MessageCreate(BaseModel):
    body: str = Field(min_length=1, max_length=2000)

class MessageOut(BaseModel):
    id: int
    patient_id: int
    from_clinic: bool
    body: str
    created_at: datetime

class InboxItem(BaseModel):
    patient_id: int
    patient_name: str | None
    last_message: str
    last_at: datetime
    from_clinic: bool