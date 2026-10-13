from __future__ import annotations

import base64
from datetime import date

import pytest
from sqlalchemy import select

from app.app import Booking, Event, SessionLocal, app


@pytest.fixture(autouse=True)
def isolated_database():
    with SessionLocal.begin() as db:
        db.query(Booking).delete()
        db.query(Event).delete()
        db.add(Event(
            slug="test-concert",
            name="Test Concert",
            category="Music",
            venue="Test Hall",
            event_date=date(2027, 1, 15),
            description="A seeded test event.",
            price_cents=2500,
            tickets_left=2,
        ))
    yield
    with SessionLocal.begin() as db:
        db.query(Booking).delete()
        db.query(Event).delete()


@pytest.fixture
def client(monkeypatch):
    monkeypatch.setenv("ADMIN_PASSWORD", "test-organizer-password")
    app.config.update(TESTING=True)
    with app.test_client() as test_client:
        yield test_client


def admin_headers(password="test-organizer-password"):
    token = base64.b64encode(f"admin:{password}".encode()).decode()
    return {"Authorization": f"Basic {token}"}


def test_home_shows_seed_event(client):
    response = client.get("/")
    assert response.status_code == 200
    assert b"Test Concert" in response.data


def test_reservation_decrements_inventory_and_creates_confirmation(client):
    with SessionLocal() as db:
        event_id = db.scalar(select(Event.id).where(Event.slug == "test-concert"))

    response = client.post(f"/events/{event_id}/reserve")

    assert response.status_code == 302
    with SessionLocal() as db:
        event = db.get(Event, event_id)
        booking = db.scalar(select(Booking).where(Booking.event_id == event_id))
        assert event.tickets_left == 1
        assert booking.confirmation_code.startswith("EP-")


def test_sold_out_event_does_not_create_booking(client):
    with SessionLocal.begin() as db:
        event = db.scalar(select(Event).where(Event.slug == "test-concert"))
        event.tickets_left = 0
        event_id = event.id

    response = client.post(f"/events/{event_id}/reserve")

    assert response.status_code == 302
    with SessionLocal() as db:
        assert db.scalar(select(Booking.id).where(Booking.event_id == event_id)) is None
        assert db.get(Event, event_id).tickets_left == 0


def test_organizer_requires_password(client):
    response = client.get("/organizer")
    assert response.status_code == 401
    assert "Basic" in response.headers["WWW-Authenticate"]


def test_organizer_can_add_event(client):
    response = client.post("/organizer", headers=admin_headers(), data={
        "name": "New Event",
        "category": "Technology",
        "venue": "Studio Hall",
        "event_date": "2027-02-01",
        "price": "19.50",
        "quantity": "50",
        "description": "A test-created event.",
    })

    assert response.status_code == 302
    with SessionLocal() as db:
        event = db.scalar(select(Event).where(Event.name == "New Event"))
        assert event is not None
        assert event.price_cents == 1950
        assert event.tickets_left == 50


def test_health_endpoint_checks_database(client):
    response = client.get("/healthz")
    assert response.status_code == 200
    assert response.json == {"status": "ok", "database": "reachable"}
