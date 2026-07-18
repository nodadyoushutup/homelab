"""SQLAlchemy models for the homelab-config application."""

from __future__ import annotations

import json
from datetime import datetime, timezone

from homelab_config.extensions import db

ROLE_MANAGER = "manager"
ROLE_WORKER = "worker"
VALID_ROLES = (ROLE_MANAGER, ROLE_WORKER)

DEFAULT_SSH_USER = "nodadyoushutup"
DEFAULT_SSH_PORT = 22


def _utcnow() -> datetime:
    """Return the current UTC time (timezone-aware)."""
    return datetime.now(timezone.utc)


class SwarmNode(db.Model):
    """A single machine that participates in the Docker Swarm.

    Each node maps to one entry under ``nodes:`` in
    ``.config/docker/swarm.yaml``. Exactly one node should carry the
    ``manager`` role (the control plane); the rest are ``worker`` nodes.
    """

    __tablename__ = "swarm_nodes"

    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(255), nullable=False, unique=True)
    host = db.Column(db.String(255), nullable=False)
    ssh_user = db.Column(db.String(255), nullable=False, default=DEFAULT_SSH_USER)
    role = db.Column(db.String(32), nullable=False, default=ROLE_WORKER)
    ssh_port = db.Column(db.Integer, nullable=False, default=DEFAULT_SSH_PORT)
    # Placement labels stored as a JSON object string ({"key": "value"}).
    labels_json = db.Column(db.Text, nullable=False, default="{}")
    created_at = db.Column(db.DateTime, nullable=False, default=_utcnow)
    updated_at = db.Column(
        db.DateTime, nullable=False, default=_utcnow, onupdate=_utcnow
    )

    @property
    def labels(self) -> dict[str, str]:
        """Return the node's placement labels as a string-keyed mapping."""
        try:
            data = json.loads(self.labels_json or "{}")
        except (TypeError, ValueError):
            return {}
        if not isinstance(data, dict):
            return {}
        return {str(key): str(value) for key, value in data.items()}

    @labels.setter
    def labels(self, value: dict[str, str] | None) -> None:
        """Store placement labels, dropping blank keys and stringifying values."""
        clean: dict[str, str] = {}
        if isinstance(value, dict):
            for key, raw in value.items():
                cleaned_key = str(key).strip()
                if cleaned_key:
                    clean[cleaned_key] = str(raw).strip()
        self.labels_json = json.dumps(clean, sort_keys=True)

    def to_dict(self) -> dict:
        """Return a JSON-serializable representation for the REST API."""
        return {
            "id": self.id,
            "name": self.name,
            "host": self.host,
            "ssh_user": self.ssh_user,
            "role": self.role,
            "ssh_port": self.ssh_port,
            "labels": self.labels,
            "created_at": self.created_at.isoformat() if self.created_at else None,
            "updated_at": self.updated_at.isoformat() if self.updated_at else None,
        }


__all__ = [
    "DEFAULT_SSH_PORT",
    "DEFAULT_SSH_USER",
    "ROLE_MANAGER",
    "ROLE_WORKER",
    "VALID_ROLES",
    "SwarmNode",
]
