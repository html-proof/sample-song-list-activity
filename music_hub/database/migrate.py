import asyncio
import hashlib
from pathlib import Path

from music_hub.config import get_settings
from music_hub.database import Database


MIGRATIONS_DIR = Path(__file__).with_name("migrations")


async def apply_migrations() -> None:
    settings = get_settings()
    if not settings.database_url:
        raise RuntimeError("DATABASE_URL is not configured")

    database = Database(
        settings.database_url,
        min_size=1,
        max_size=1,
        require_ssl=settings.database_ssl,
        verify_ssl=settings.database_ssl_verify,
    )
    await database.connect()
    try:
        await database.execute(
            """
            CREATE TABLE IF NOT EXISTS schema_migrations (
                filename TEXT PRIMARY KEY,
                checksum TEXT NOT NULL,
                applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
            )
            """
        )
        applied_rows = await database.fetch(
            "SELECT filename, checksum FROM schema_migrations"
        )
        applied = {str(row["filename"]): str(row["checksum"]) for row in applied_rows}

        for path in sorted(MIGRATIONS_DIR.glob("*.sql")):
            sql = path.read_text(encoding="utf-8")
            checksum = hashlib.sha256(sql.encode("utf-8")).hexdigest()
            previous = applied.get(path.name)
            if previous == checksum:
                print(f"Already applied: {path.name}")
                continue
            if previous is not None:
                raise RuntimeError(
                    f"Migration {path.name} changed after it was applied"
                )
            print(f"Applying: {path.name}")
            await database.execute(sql)
            await database.execute(
                "INSERT INTO schema_migrations (filename, checksum) VALUES ($1, $2)",
                path.name,
                checksum,
            )
        print("Database migrations are current")
    finally:
        await database.close()


def main() -> None:
    asyncio.run(apply_migrations())


if __name__ == "__main__":
    main()
