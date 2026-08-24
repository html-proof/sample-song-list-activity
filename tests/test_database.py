import ssl

from music_hub.database.postgres import Database


def test_database_ssl_can_be_disabled():
    database = Database(None, require_ssl=False)

    assert database._ssl_parameter() is False


def test_database_ssl_require_mode_keeps_encryption_without_verification():
    database = Database(None, require_ssl=True, verify_ssl=False)

    assert database._ssl_parameter() == "require"


def test_database_ssl_verification_is_the_default():
    database = Database(None)

    context = database._ssl_parameter()

    assert isinstance(context, ssl.SSLContext)
    assert context.check_hostname is True
    assert context.verify_mode == ssl.CERT_REQUIRED
