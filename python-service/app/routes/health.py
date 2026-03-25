from fastapi import APIRouter

router = APIRouter(tags=["health"])


@router.get("/health", summary="Liveness check")
def health() -> dict:
    """Returns OK when the service is running."""
    return {"status": "ok"}
