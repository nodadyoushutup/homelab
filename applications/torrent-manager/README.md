# torrent-manager

Flask application for tracking torrent metadata with a Jinja2 UI, SQLAlchemy
persistence, and a Docker build context aligned with other `applications/`
services in this repo.

## Layout

```text
applications/torrent-manager/
├── config/
│   └── config.yaml            # default config baked into the image
├── Dockerfile
├── entrypoint.sh
├── requirements.txt
├── src/torrent_manager/
│   ├── app.py                 # Flask factory
│   ├── config_loader.py       # YAML config loading
│   ├── extensions.py          # db = SQLAlchemy()
│   ├── models/
│   │   ├── base.py            # BaseModel (abstract), BaseRecord (in-memory)
│   │   ├── crud.py            # CRUDModel (abstract)
│   │   └── torrent.py         # example persisted model
│   ├── routes/
│   ├── services/
│   │   └── qbittorrent/       # Web API client + multi-client registry
│   ├── qbittorrent_settings.py
│   ├── templates/
│   └── static/
└── tests/
```

## Configuration (YAML)

All app settings live in a **single YAML file**. The repo ships a working default at
`config/config.yaml`. The Docker image copies it to **`/etc/torrent-manager/config.yaml`**.

Mount your own file over that path at container start:

```bash
docker run --rm -p 8080:8080 \
  -v torrent-manager-data:/data \
  -v /path/to/my-config.yaml:/etc/torrent-manager/config.yaml:ro \
  torrent-manager:local
```

For local dev, the loader falls back to the bundled `config/config.yaml` when
`/etc/torrent-manager/config.yaml` is absent. Override the path with
`TORRENT_MANAGER_CONFIG_PATH` if needed.

### Schema

```yaml
app:
  secret_key: dev-only-change-me
  database_url: sqlite:////data/torrent-manager.db
  debug: false
  sqlalchemy_echo: false

qbittorrent:
  defaults:
    username: admin
    password: shared-secret
    insecure_tls: false
    timeout_sec: 20
  clients:
    - id: movie_0
      base_url: http://192.168.1.100:10895
    - id: television_1
      base_url: http://192.168.1.100:10901
      password: per-client-override
```

Each `clients[]` entry needs `id` and `base_url`. Username, password, TLS, and
timeout inherit from `qbittorrent.defaults` unless set on the client row.
Password is required for each configured client (via defaults or per-client).

At runtime the app builds a `QBitTorrentRegistry` with one authenticated client
handle per configured id. See `/clients` and `/healthz/qbittorrent`.

Process bind tuning (`HOST`, `PORT`, `GUNICORN_*`) remains environment-based for
the container entrypoint.

## Model inheritance

| Class | Role |
| --- | --- |
| `BaseRecord` | Abstract in-memory object with `id`, timestamps, `to_dict()`, and `update_from_dict()`. Use for DTOs that should not be stored. |
| `BaseModel` | Abstract SQLAlchemy model with `id`, `created_at`, `updated_at`, serialization helpers. Inherit directly when a table needs custom persistence without generic CRUD helpers. |
| `CRUDModel` | Extends `BaseModel` with `get_by_id`, `list_all`, `create`, `save`, `delete`, and `delete_by_id`. Most tables should inherit this. |
| `Torrent` | Concrete example table inheriting `CRUDModel`. |

## Run locally

```bash
cd applications/torrent-manager
python -m venv .venv
./.venv/bin/pip install -r requirements.txt
export PYTHONPATH=src
./.venv/bin/python -m torrent_manager
```

Open `http://127.0.0.1:8080`.

## Tests

```bash
cd applications/torrent-manager
PYTHONPATH=src ./.venv/bin/python -m unittest discover -s tests -v
```

## Docker

```bash
docker build -t torrent-manager:local applications/torrent-manager
docker run --rm -p 8080:8080 -v torrent-manager-data:/data torrent-manager:local
```

Healthcheck:

```bash
docker run --rm torrent-manager:local healthcheck --host=127.0.0.1 --port=8080
```

## Next steps

- Wire Swarm Terraform slice and image publish target when ready to deploy
- Replace SQLite with PostgreSQL for multi-replica deployments
- Sync torrent rows from each configured qBittorrent client into the local database
