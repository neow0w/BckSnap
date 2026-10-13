from pathlib import Path

from pydantic import ValidationError
from pydantic_settings import BaseSettings, SettingsConfigDict


PROJECT_ROOT = Path(__file__).resolve().parent.parent
ENV_FILE = PROJECT_ROOT / ".env"


class Settings(BaseSettings):
    database_url: str
    secret_key: str
    algorithm: str = "HS256"
    token_expire_days: int = 30
    scoliosis_threshold: float = 7.0
    upload_dir: str = "uploads"
    max_photo_mb: int = 5
    geocoding_user_agent: str = "BckSnap clinic discovery/1.0"
    consultation_url_template: str | None = None

    model_config = SettingsConfigDict(env_file=ENV_FILE, env_file_encoding="utf-8")


try:
    settings = Settings()
except ValidationError as exc:
    missing = [
        str(error["loc"][0])
        for error in exc.errors(include_input=False)
        if error["type"] == "missing"
    ]
    if not missing:
        raise
    raise RuntimeError(
        f"Missing required backend setting(s): {', '.join(missing)}. "
        f"Set them in {ENV_FILE} (copy .env.example) or in the environment."
    ) from None