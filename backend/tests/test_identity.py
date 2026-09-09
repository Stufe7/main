from app.identity import decide_from_signals, email_domain, names_plausibly_match, registrable_domain


def test_registrable_domain_strips_www_and_path() -> None:
    assert registrable_domain("https://www.dbs.com.sg/index.html") == "dbs.com.sg"
    assert registrable_domain("apple.com") == "apple.com"


def test_email_domain() -> None:
    assert email_domain("Jane.Doe@Apple.COM") == "apple.com"


def test_verified_when_domains_and_name_match() -> None:
    verdict = decide_from_signals(
        work_email="it@apple.com",
        company_name="Apple Inc.",
        company_url="https://www.apple.com",
        title="Apple",
        reachable=True,
    )
    assert verdict.decision == "Verified"
    assert verdict.reason_code == "DOMAIN_AND_NAME_MATCH"


def test_mismatch_goes_to_review_not_reject() -> None:
    verdict = decide_from_signals(
        work_email="sales@contoso.com",
        company_name="Contoso",
        company_url="https://www.microsoft.com",
        title="Microsoft",
        reachable=True,
    )
    assert verdict.decision == "Review Required"
    assert verdict.reason_code == "DOMAIN_MISMATCH"


def test_unreachable_is_review() -> None:
    verdict = decide_from_signals(
        work_email="ops@example.com",
        company_name="Example",
        company_url="https://no-such-host.invalid",
        title=None,
        reachable=False,
        fetch_error="ConnectError",
    )
    assert verdict.reason_code == "WEBSITE_UNREACHABLE"


def test_trading_name_tolerance() -> None:
    assert names_plausibly_match("DBS Bank Ltd", "DBS | Singapore's largest bank")
