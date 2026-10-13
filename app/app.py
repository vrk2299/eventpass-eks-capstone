from __future__ import annotations

import hmac
import os
import secrets
import time
from datetime import date
from urllib.parse import quote_plus

from flask import Flask, Response, abort, flash, redirect, render_template, request, url_for
from sqlalchemy import CheckConstraint, Date, ForeignKey, Integer, String, Text, create_engine, select, update
from sqlalchemy.dialects.mysql import insert as mysql_insert
from sqlalchemy.exc import OperationalError
from sqlalchemy.orm import DeclarativeBase, Mapped, joinedload, mapped_column, relationship, sessionmaker


class Base(DeclarativeBase):
    pass


class Event(Base):
    __tablename__ = "events"
    __table_args__ = (
        CheckConstraint("price_cents >= 0", name="ck_events_price_nonnegative"),
        CheckConstraint("tickets_left >= 0", name="ck_events_tickets_nonnegative"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    slug: Mapped[str] = mapped_column(String(120), unique=True, nullable=False)
    name: Mapped[str] = mapped_column(String(160), nullable=False)
    category: Mapped[str] = mapped_column(String(80), nullable=False)
    venue: Mapped[str] = mapped_column(String(160), nullable=False)
    event_date: Mapped[date] = mapped_column(Date, nullable=False)
    description: Mapped[str] = mapped_column(Text, nullable=False, default="")
    price_cents: Mapped[int] = mapped_column(Integer, nullable=False)
    tickets_left: Mapped[int] = mapped_column(Integer, nullable=False)
    bookings: Mapped[list["Booking"]] = relationship(back_populates="event")


class Booking(Base):
    __tablename__ = "bookings"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    event_id: Mapped[int] = mapped_column(ForeignKey("events.id"), nullable=False)
    confirmation_code: Mapped[str] = mapped_column(String(24), unique=True, nullable=False)
    booked_at: Mapped[str] = mapped_column(String(32), nullable=False)
    event: Mapped[Event] = relationship(back_populates="bookings")


def database_url() -> str:
    host = os.getenv("DB_HOST", "127.0.0.1")
    port = os.getenv("DB_PORT", "3306")
    name = os.getenv("DB_NAME", "eventpass")
    user = quote_plus(os.getenv("DB_USER", "eventpass"))
    password = quote_plus(os.getenv("DB_PASSWORD", ""))
    return f"mysql+pymysql://{user}:{password}@{host}:{port}/{name}?charset=utf8mb4"


engine = create_engine(database_url(), pool_pre_ping=True, pool_recycle=1800)
SessionLocal = sessionmaker(bind=engine, expire_on_commit=False)
app = Flask(__name__)
app.secret_key = os.getenv("SECRET_KEY", "local-development-only")


def initialize_database() -> None:
    """Create the classroom schema and seed demo events once, retrying MySQL startup."""
    for attempt in range(30):
        try:
            Base.metadata.create_all(engine)
            with SessionLocal.begin() as db:
                if db.scalar(select(Event.id).limit(1)) is None:
                    db.execute(mysql_insert(Event.__table__).prefix_with("IGNORE"), [
                        {"slug": "neon-city-sessions", "name": "Neon City Sessions", "category": "Live music", "venue": "The Foundry, Mumbai", "event_date": date(2026, 11, 14), "description": "An intimate night of electronic and local sounds.", "price_cents": 3200, "tickets_left": 120},
                        {"slug": "taste-of-the-coast", "name": "Taste of the Coast", "category": "Food festival", "venue": "Harbor Park, Mumbai", "event_date": date(2026, 11, 21), "description": "Local chefs, small-batch makers, and sunset views.", "price_cents": 1800, "tickets_left": 240},
                        {"slug": "build-something-better", "name": "Build Something Better", "category": "Technology", "venue": "Studio Hall, Mumbai", "event_date": date(2026, 12, 3), "description": "A one-day gathering for people who make useful things.", "price_cents": 4900, "tickets_left": 85},
                    ])
            return
        except OperationalError:
            if attempt == 29:
                raise
            time.sleep(2)


def is_admin() -> bool:
    auth = request.authorization
    expected = os.getenv("ADMIN_PASSWORD", "")
    return bool(auth and auth.username == "admin" and expected and hmac.compare_digest(auth.password or "", expected))


def require_admin() -> Response | None:
    if not is_admin():
        return Response("Organizer sign-in required", 401, {"WWW-Authenticate": 'Basic realm="EventPass organizer"'})


@app.get("/")
def home():
    with SessionLocal() as db:
        events = db.scalars(select(Event).order_by(Event.event_date, Event.id)).all()
    return render_template("index.html", events=events)


@app.post("/events/<int:event_id>/reserve")
def reserve(event_id: int):
    code = "EP-" + secrets.token_hex(4).upper()
    with SessionLocal.begin() as db:
        result = db.execute(
            update(Event)
            .where(Event.id == event_id, Event.tickets_left > 0)
            .values(tickets_left=Event.tickets_left - 1)
        )
        if result.rowcount != 1:
            flash("That event is sold out or no longer available.", "error")
            return redirect(url_for("home"))
        db.add(Booking(event_id=event_id, confirmation_code=code, booked_at=time.strftime("%Y-%m-%d %H:%M:%S UTC", time.gmtime())))
    flash(f"Ticket reserved. Confirmation: {code}. This demo does not collect payment.", "success")
    return redirect(url_for("home"))


@app.route("/organizer", methods=["GET", "POST"])
def organizer():
    auth_error = require_admin()
    if auth_error:
        return auth_error
    if request.method == "POST":
        try:
            price_cents = round(float(request.form["price"]) * 100)
            quantity = int(request.form["quantity"])
            event_date = date.fromisoformat(request.form["event_date"])
            if price_cents < 0 or quantity < 1:
                raise ValueError
        except (KeyError, ValueError):
            abort(400, "Enter a valid date, nonnegative price, and ticket quantity greater than zero.")
        required = (request.form.get("name", "").strip(), request.form.get("category", "").strip(), request.form.get("venue", "").strip())
        if not all(required):
            abort(400, "Event name, category, and venue are required.")
        slug = "-".join(required[0].lower().split())[:120] + "-" + secrets.token_hex(3)
        with SessionLocal.begin() as db:
            db.add(Event(slug=slug, name=required[0], category=required[1], venue=required[2], event_date=event_date, description=request.form.get("description", "").strip(), price_cents=price_cents, tickets_left=quantity))
        flash("Event added.", "success")
        return redirect(url_for("organizer"))
    with SessionLocal() as db:
        bookings = db.scalars(select(Booking).options(joinedload(Booking.event)).order_by(Booking.id.desc()).limit(30)).all()
    return render_template("organizer.html", bookings=bookings)


@app.get("/healthz")
def healthz():
    try:
        with engine.connect() as db:
            db.exec_driver_sql("SELECT 1")
        return {"status": "ok", "database": "reachable"}
    except OperationalError:
        return {"status": "unavailable", "database": "unreachable"}, 503


@app.get("/livez")
def livez():
    return {"status": "ok"}


initialize_database()
