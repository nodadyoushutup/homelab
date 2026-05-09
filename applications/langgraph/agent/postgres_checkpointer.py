from __future__ import annotations

import os
from contextlib import asynccontextmanager
from typing import AsyncIterator

from langgraph.checkpoint.postgres.aio import AsyncPostgresSaver


@asynccontextmanager
async def create_checkpointer() -> AsyncIterator[AsyncPostgresSaver]:
    postgres_uri = os.environ["POSTGRES_URI"]
    async with AsyncPostgresSaver.from_conn_string(postgres_uri) as checkpointer:
        await checkpointer.setup()
        yield checkpointer
