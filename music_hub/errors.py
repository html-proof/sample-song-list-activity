class MusicHubError(Exception):
    """Base application error."""


class InfrastructureUnavailable(MusicHubError):
    """A required database, cache, or authentication service is unavailable."""


class ProviderUnavailable(MusicHubError):
    """The configured music provider could not serve the request."""


class ResourceNotFound(MusicHubError):
    """The requested application or provider resource does not exist."""


class ForbiddenOperation(MusicHubError):
    """The authenticated user does not own the requested resource."""
