import os


def main() -> None:
    # entrypoint.sh: native only when MCP_CODE_USE_NATIVE=1; else three local mcp-proxy + server.py.
    if os.environ.get("MCP_CODE_USE_NATIVE", "").strip().lower() in ("1", "true", "yes"):
        from mcp_code.native_server import main as native_main

        native_main()
        return
    from mcp_code.server import main as proxy_aggregate_main

    proxy_aggregate_main()


if __name__ == "__main__":
    main()
