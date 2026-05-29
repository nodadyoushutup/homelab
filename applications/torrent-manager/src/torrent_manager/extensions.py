"""Shared Flask extensions."""

from __future__ import annotations

from flask_sqlalchemy import SQLAlchemy
from sqlalchemy.orm import DeclarativeBase


class Base(DeclarativeBase):
    """Declarative base passed to Flask-SQLAlchemy."""


db = SQLAlchemy(model_class=Base)
