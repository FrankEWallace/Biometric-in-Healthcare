"""
Entry point — start the FastAPI service with uvicorn.

Usage:
    python run.py
"""

from dotenv import load_dotenv
load_dotenv()

import uvicorn

if __name__ == "__main__":
    uvicorn.run(
        "app.main:app",
        host="0.0.0.0",
        port=5001,          # Laravel FingerprintService.php points here
        reload=False,       # set reload=True during development
        log_level="info",
    )
