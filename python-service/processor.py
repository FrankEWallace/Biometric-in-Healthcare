import cv2
import numpy as np


def preprocess(image: np.ndarray) -> np.ndarray:
    """Convert to grayscale and apply CLAHE."""
    if len(image.shape) == 3:
        gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    else:
        gray = image.copy()
    clahe = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(8, 8))
    return clahe.apply(gray)


def apply_gabor(image: np.ndarray) -> np.ndarray:
    """Apply a bank of Gabor filters and sum responses."""
    responses = []
    for theta in np.arange(0, np.pi, np.pi / 4):
        kernel = cv2.getGaborKernel(
            ksize=(21, 21),
            sigma=5.0,
            theta=theta,
            lambd=10.0,
            gamma=0.5,
            psi=0,
            ktype=cv2.CV_32F,
        )
        filtered = cv2.filter2D(image, cv2.CV_8UC3, kernel)
        responses.append(filtered)
    return np.max(np.stack(responses, axis=0), axis=0)


def extract_orb_template(image: np.ndarray) -> dict:
    """Detect ORB keypoints/descriptors and return a serializable template."""
    orb = cv2.ORB_create(nfeatures=500)
    keypoints, descriptors = orb.detectAndCompute(image, None)

    if descriptors is None:
        descriptors = np.zeros((0, 32), dtype=np.uint8)

    kp_data = [
        {
            "pt": kp.pt,
            "size": kp.size,
            "angle": kp.angle,
            "response": kp.response,
            "octave": kp.octave,
            "class_id": kp.class_id,
        }
        for kp in keypoints
    ]

    return {
        "keypoints": kp_data,
        "descriptors": descriptors.tolist(),
    }


def compute_quality_score(keypoints: list, image: np.ndarray) -> float:
    """
    Quality score [0, 1] — ratio of detected keypoints to a 500-keypoint target,
    capped at 1.0. Low keypoint count indicates a blurry or poorly captured image.
    """
    if not keypoints:
        return 0.0
    return min(len(keypoints) / 500.0, 1.0)


def build_template(image: np.ndarray) -> dict:
    """
    Full pipeline: CLAHE -> Gabor -> ORB.
    Returns { "template": {...}, "quality_score": float }
    """
    enhanced = preprocess(image)
    gabor_out = apply_gabor(enhanced)
    orb_result = extract_orb_template(gabor_out)
    quality = compute_quality_score(orb_result["keypoints"], gabor_out)
    return {"template": orb_result, "quality_score": round(quality, 3)}


def match_templates(probe: dict, candidate: dict) -> float:
    """Return a match score [0, 1] between two templates using BFMatcher."""
    probe_desc = np.array(probe["descriptors"], dtype=np.uint8)
    cand_desc = np.array(candidate["descriptors"], dtype=np.uint8)

    if probe_desc.shape[0] == 0 or cand_desc.shape[0] == 0:
        return 0.0

    bf = cv2.BFMatcher(cv2.NORM_HAMMING, crossCheck=False)
    matches = bf.knnMatch(probe_desc, cand_desc, k=2)

    good = []
    for m_pair in matches:
        if len(m_pair) == 2:
            m, n = m_pair
            if m.distance < 0.75 * n.distance:
                good.append(m)

    max_possible = min(probe_desc.shape[0], cand_desc.shape[0])
    return len(good) / max_possible if max_possible > 0 else 0.0
