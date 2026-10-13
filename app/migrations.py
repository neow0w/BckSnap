from sqlalchemy import Engine, inspect, text


def upgrade(engine: Engine) -> None:
    """Apply the additive clinic-booking migration without rewriting old rows."""
    with engine.begin() as connection:
        connection.execute(
            text(
                "CREATE TABLE IF NOT EXISTS schema_migrations ("
                "version VARCHAR(40) PRIMARY KEY, "
                "applied_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP)"
            )
        )
        applied = connection.execute(
            text("SELECT 1 FROM schema_migrations WHERE version = :version"),
            {"version": "001_clinic_booking"},
        ).first()
        if not applied:
            columns = {
                column["name"]
                for column in inspect(connection).get_columns("appointments")
            }
            additions = {
                "clinic_id": "INTEGER REFERENCES clinics(id)",
                "doctor_id": "INTEGER REFERENCES doctor_profiles(id)",
                "reference": "VARCHAR(24)",
                "cancellation_reason": "TEXT",
                "cancelled_at": "TIMESTAMP WITH TIME ZONE",
                "cancelled_by": "INTEGER REFERENCES users(id)",
                "consultation_url": "VARCHAR(2048)",
            }
            for name, type_sql in additions.items():
                if name not in columns:
                    connection.execute(
                        text(f"ALTER TABLE appointments ADD COLUMN {name} {type_sql}")
                    )

            connection.execute(
                text(
                    "UPDATE appointments SET status = 'rejected' "
                    "WHERE status = 'declined'"
                )
            )
            connection.execute(
                text(
                    "CREATE UNIQUE INDEX IF NOT EXISTS uq_appointments_reference "
                    "ON appointments (reference) WHERE reference IS NOT NULL"
                )
            )
            connection.execute(
                text(
                    "CREATE UNIQUE INDEX IF NOT EXISTS "
                    "uq_appointments_doctor_time_active "
                    "ON appointments (doctor_id, scheduled_at) "
                    "WHERE doctor_id IS NOT NULL AND scheduled_at IS NOT NULL "
                    "AND status IN ('pending', 'approved')"
                )
            )
            connection.execute(
                text(
                    "CREATE INDEX IF NOT EXISTS ix_appointments_clinic_status "
                    "ON appointments (clinic_id, status)"
                )
            )
            connection.execute(
                text(
                    "INSERT INTO schema_migrations (version) "
                    "VALUES ('001_clinic_booking')"
                )
            )

        screening_columns = {
            column["name"] for column in inspect(connection).get_columns("screenings")
        }
        if "idempotency_key" not in screening_columns:
            connection.execute(
                text("ALTER TABLE screenings ADD COLUMN idempotency_key VARCHAR(64)")
            )
        connection.execute(
            text(
                "CREATE UNIQUE INDEX IF NOT EXISTS "
                "uq_screenings_user_idempotency_key "
                "ON screenings (user_id, idempotency_key)"
            )
        )
        connection.execute(
            text(
                "INSERT INTO schema_migrations (version) "
                "VALUES ('002_screening_idempotency') "
                "ON CONFLICT (version) DO NOTHING"
            )
        )

        appointment_columns = {
            column["name"] for column in inspect(connection).get_columns("appointments")
        }
        if "updated_at" not in appointment_columns:
            connection.execute(
                text(
                    "ALTER TABLE appointments "
                    "ADD COLUMN updated_at TIMESTAMP WITH TIME ZONE"
                )
            )
        connection.execute(
            text(
                "UPDATE appointments SET updated_at = created_at "
                "WHERE updated_at IS NULL"
            )
        )
        connection.execute(
            text(
                "INSERT INTO schema_migrations (version) "
                "VALUES ('003_appointment_updated_at') "
                "ON CONFLICT (version) DO NOTHING"
            )
        )

        demo_columns = {
            "clinics": {"demo_operating_hours": "JSON"},
            "users": {"is_demo": "BOOLEAN NOT NULL DEFAULT FALSE"},
            "appointments": {"is_demo": "BOOLEAN NOT NULL DEFAULT FALSE"},
            "clinic_services": {"is_demo": "BOOLEAN NOT NULL DEFAULT FALSE"},
            "clinic_staff": {"is_demo": "BOOLEAN NOT NULL DEFAULT FALSE"},
            "doctor_profiles": {"is_demo": "BOOLEAN NOT NULL DEFAULT FALSE"},
            "doctor_schedules": {"is_demo": "BOOLEAN NOT NULL DEFAULT FALSE"},
        }
        for table_name, additions in demo_columns.items():
            existing_columns = {
                column["name"] for column in inspect(connection).get_columns(table_name)
            }
            for name, type_sql in additions.items():
                if name not in existing_columns:
                    connection.execute(
                        text(f"ALTER TABLE {table_name} ADD COLUMN {name} {type_sql}")
                    )
        connection.execute(
            text(
                "CREATE TABLE IF NOT EXISTS demo_appointment_types ("
                "id INTEGER PRIMARY KEY, "
                "clinic_id INTEGER NOT NULL REFERENCES clinics(id) ON DELETE CASCADE, "
                "mode VARCHAR(20) NOT NULL CHECK (mode IN ('online', 'physical')), "
                "name VARCHAR(120) NOT NULL, "
                "simulation_only BOOLEAN NOT NULL DEFAULT TRUE, "
                "CONSTRAINT uq_demo_appointment_type_clinic_mode "
                "UNIQUE (clinic_id, mode))"
            )
        )
        connection.execute(
            text(
                "CREATE INDEX IF NOT EXISTS ix_demo_appointment_types_clinic_id "
                "ON demo_appointment_types (clinic_id)"
            )
        )
        connection.execute(
            text(
                "INSERT INTO schema_migrations (version) "
                "VALUES ('004_development_demo_data') "
                "ON CONFLICT (version) DO NOTHING"
            )
        )

        account_columns = {
            column["name"] for column in inspect(connection).get_columns("users")
        }
        account_additions = {
            "first_name": "VARCHAR(100)",
            "middle_initial": "VARCHAR(2)",
            "last_name": "VARCHAR(100)",
            "birthdate": "DATE",
            "address": "VARCHAR(500)",
            "gender": "VARCHAR(30)",
            "contact_number": "VARCHAR(16)",
        }
        for name, type_sql in account_additions.items():
            if name not in account_columns:
                connection.execute(
                    text(f"ALTER TABLE users ADD COLUMN {name} {type_sql}")
                )

        duplicate_emails = connection.execute(
            text(
                "SELECT lower(email), COUNT(*) FROM users "
                "WHERE email IS NOT NULL GROUP BY lower(email) HAVING COUNT(*) > 1 "
                "LIMIT 1"
            )
        ).first()
        if duplicate_emails is not None:
            raise RuntimeError(
                "Cannot enforce case-insensitive email uniqueness: existing user "
                "records contain duplicate email addresses differing only by case. "
                "Resolve those records before restarting the API."
            )
        connection.execute(
            text(
                "CREATE UNIQUE INDEX IF NOT EXISTS uq_users_email_lower "
                "ON users (lower(email)) WHERE email IS NOT NULL"
            )
        )
        connection.execute(
            text(
                "INSERT INTO schema_migrations (version) "
                "VALUES ('005_account_registration') "
                "ON CONFLICT (version) DO NOTHING"
            )
        )
