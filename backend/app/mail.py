from __future__ import annotations

import logging

import httpx

from app.settings import settings

log = logging.getLogger(__name__)


def send_updates_mail(
    to_email: str, subject: str, text: str, *, required: bool = False
) -> None:
    if not settings.sendgrid_api_key:
        log.info("mail skipped (no SENDGRID_API_KEY): %s -> %s", subject, to_email)
        if required:
            raise RuntimeError("Email is not configured")
        return
    payload = {
        "personalizations": [{"to": [{"email": to_email}]}],
        "from": {"email": settings.mail_from_updates},
        "reply_to": {"email": settings.mail_reply_to_support},
        "subject": subject,
        "content": [{"type": "text/plain", "value": text}],
    }
    response = httpx.post(
        "https://api.sendgrid.com/v3/mail/send",
        headers={"Authorization": f"Bearer {settings.sendgrid_api_key}"},
        json=payload,
        timeout=15.0,
    )
    if response.status_code >= 300:
        log.error("SendGrid %s: %s", response.status_code, response.text)
        raise RuntimeError("mail send failed")


def send_admin_alert(subject: str, text: str) -> None:
    if not settings.sendgrid_api_key or not settings.mail_admin_to:
        log.info("admin alert skipped: %s", subject)
        return
    payload = {
        "personalizations": [{"to": [{"email": settings.mail_admin_to}]}],
        "from": {"email": settings.mail_from_noreply},
        "subject": subject,
        "content": [{"type": "text/plain", "value": text}],
    }
    response = httpx.post(
        "https://api.sendgrid.com/v3/mail/send",
        headers={"Authorization": f"Bearer {settings.sendgrid_api_key}"},
        json=payload,
        timeout=15.0,
    )
    if response.status_code >= 300:
        log.error("SendGrid admin %s: %s", response.status_code, response.text)
