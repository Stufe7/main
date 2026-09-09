from __future__ import annotations

import re
from dataclasses import dataclass
from urllib.parse import urlparse

LEGAL_SUFFIXES = {
    "ab",
    "ag",
    "and",
    "bank",
    "bv",
    "co",
    "company",
    "corp",
    "corporation",
    "gmbh",
    "group",
    "holding",
    "holdings",
    "inc",
    "incorporated",
    "kk",
    "limited",
    "llc",
    "llp",
    "lp",
    "ltd",
    "nv",
    "oy",
    "plc",
    "pte",
    "sa",
    "sas",
    "srl",
    "the",
}

SECOND_LEVEL_SUFFIXES = {
    "co.uk",
    "org.uk",
    "ac.uk",
    "gov.uk",
    "com.au",
    "net.au",
    "org.au",
    "com.sg",
    "com.hk",
    "com.my",
    "com.ph",
    "co.nz",
    "co.jp",
    "co.id",
    "com.br",
    "co.in",
    "com.cn",
    "com.tw",
}

TITLE_RE = re.compile(r"<title[^>]*>(.*?)</title>", re.I | re.S)
TOKEN_RE = re.compile(r"[a-z0-9]+")


def normalize_host(value: str) -> str:
    text = value.strip().lower()
    if "://" not in text:
        text = f"https://{text}"
    host = urlparse(text).hostname or ""
    host = host.removeprefix("www.")
    return host.rstrip(".")


def registrable_domain(host_or_url: str) -> str:
    host = normalize_host(host_or_url)
    labels = [part for part in host.split(".") if part]
    if len(labels) >= 3 and ".".join(labels[-2:]) in SECOND_LEVEL_SUFFIXES:
        return ".".join(labels[-3:])
    if len(labels) >= 2:
        return ".".join(labels[-2:])
    return host


def email_domain(email: str) -> str:
    return email.strip().lower().rsplit("@", 1)[-1].rstrip(".")


def name_tokens(name: str) -> set[str]:
    tokens = TOKEN_RE.findall(name.lower())
    return {token for token in tokens if token not in LEGAL_SUFFIXES and len(token) > 1}


def names_plausibly_match(company_name: str, *sources: str) -> bool:
    wanted = name_tokens(company_name)
    if not wanted:
        return False
    haystack = name_tokens(" ".join(source for source in sources if source))
    if wanted <= haystack:
        return True
    if any(token in haystack for token in wanted if len(token) >= 4):
        return True
    joined_wanted = " ".join(sorted(wanted))
    joined_hay = " ".join(sorted(haystack))
    if not joined_hay:
        return False
    from difflib import SequenceMatcher

    return SequenceMatcher(None, joined_wanted, joined_hay).ratio() >= 0.72


@dataclass(frozen=True)
class IdentityVerdict:
    decision: str
    reason_code: str
    summary: str
    email_domain: str
    website_domain: str
    title: str | None = None


def decide_from_signals(
    *,
    work_email: str,
    company_name: str,
    company_url: str,
    title: str | None,
    reachable: bool,
    fetch_error: str | None = None,
) -> IdentityVerdict:
    mail = email_domain(work_email)
    site = registrable_domain(company_url)
    sld = site.split(".")[0]
    if not reachable:
        return IdentityVerdict(
            decision="Review Required",
            reason_code="WEBSITE_UNREACHABLE",
            summary=fetch_error or "Company URL did not respond in time.",
            email_domain=mail,
            website_domain=site,
        )
    if mail != site:
        return IdentityVerdict(
            decision="Review Required",
            reason_code="DOMAIN_MISMATCH",
            summary=f"Work email domain {mail} does not match website domain {site}.",
            email_domain=mail,
            website_domain=site,
            title=title,
        )
    if names_plausibly_match(company_name, title or "", sld, site):
        return IdentityVerdict(
            decision="Verified",
            reason_code="DOMAIN_AND_NAME_MATCH",
            summary="Email domain matches website domain and company name is plausible.",
            email_domain=mail,
            website_domain=site,
            title=title,
        )
    return IdentityVerdict(
        decision="Review Required",
        reason_code="COMPANY_NAME_INCONCLUSIVE",
        summary="Email and website domains match, but the company name is not clearly on the site.",
        email_domain=mail,
        website_domain=site,
        title=title,
    )


def extract_title(html: str) -> str | None:
    match = TITLE_RE.search(html)
    if not match:
        return None
    title = re.sub(r"\s+", " ", match.group(1)).strip()
    return title or None


def verify_company_identity(
    *,
    work_email: str,
    company_name: str,
    company_url: str,
    timeout_seconds: float = 4.0,
) -> IdentityVerdict:
    import httpx

    url = company_url.strip()
    if not url.startswith(("http://", "https://")):
        url = f"https://{url}"
    title = None
    try:
        with httpx.Client(
            follow_redirects=True,
            timeout=timeout_seconds,
            headers={"User-Agent": "Stufe7-identity-check/1.0"},
            max_redirects=5,
        ) as client:
            response = client.get(url)
            title = extract_title(response.text[:200_000])
            reachable = response.status_code < 500
            error = None if reachable else f"HTTP {response.status_code}"
    except httpx.HTTPError as exc:
        return decide_from_signals(
            work_email=work_email,
            company_name=company_name,
            company_url=company_url,
            title=None,
            reachable=False,
            fetch_error=str(exc.__class__.__name__),
        )
    return decide_from_signals(
        work_email=work_email,
        company_name=company_name,
        company_url=company_url,
        title=title,
        reachable=reachable,
        fetch_error=error,
    )
