#!/usr/bin/env python3
"""Generate container-centric Docker Grafana dashboard."""
import json
from copy import deepcopy
from pathlib import Path

JOB = "telegraf_docker_metrics"
DS = {"type": "prometheus", "uid": "prometheus"}


def sel(extra=""):
    base = (
        f'job="{JOB}", platform=~"$platform", engine_host=~"$host", '
        f'com_docker_swarm_service_name=~"$service", container_name=~"$container"'
    )
    return f"{base},{extra}" if extra else base


def sel_running(extra=""):
    parts = ['container_status="running"']
    if extra:
        parts.append(extra)
    return sel(",".join(parts))


def sel_swarm_running(extra=""):
    parts = ['com_docker_swarm_service_name!=""']
    if extra:
        parts.append(extra)
    return sel_running(",".join(parts))


STAT_THRESH = {
    "defaults": {
        "color": {"mode": "thresholds"},
        "decimals": 0,
        "thresholds": {"mode": "absolute", "steps": [{"color": "blue", "value": None}]},
        "unit": "short",
    },
    "overrides": [],
}
STAT_GREEN = deepcopy(STAT_THRESH)
STAT_GREEN["defaults"]["thresholds"]["steps"] = [{"color": "green", "value": None}]
STAT_WARN = deepcopy(STAT_THRESH)
STAT_WARN["defaults"]["thresholds"]["steps"] = [
    {"color": "green", "value": None},
    {"color": "yellow", "value": 1},
    {"color": "red", "value": 10},
]
STAT_PCT = {
    "defaults": {
        "color": {"mode": "thresholds"},
        "decimals": 1,
        "max": 100,
        "min": 0,
        "thresholds": {
            "mode": "absolute",
            "steps": [
                {"color": "green", "value": None},
                {"color": "yellow", "value": 70},
                {"color": "red", "value": 90},
            ],
        },
        "unit": "percent",
    },
    "overrides": [],
}
STAT_BPS = {
    "defaults": {
        "color": {"mode": "thresholds"},
        "decimals": 1,
        "thresholds": {
            "mode": "absolute",
            "steps": [
                {"color": "green", "value": None},
                {"color": "yellow", "value": 1048576},
                {"color": "red", "value": 10485760},
            ],
        },
        "unit": "Bps",
    },
    "overrides": [],
}
STAT_OPTS = {
    "colorMode": "value",
    "graphMode": "none",
    "justifyMode": "center",
    "orientation": "auto",
    "reduceOptions": {"calcs": ["lastNotNull"], "fields": "", "values": False},
    "textMode": "auto",
}
TS_CUSTOM = {
    "axisBorderShow": False,
    "axisCenteredZero": False,
    "axisColorMode": "text",
    "axisLabel": "",
    "axisPlacement": "auto",
    "barAlignment": 0,
    "drawStyle": "line",
    "fillOpacity": 15,
    "gradientMode": "none",
    "hideFrom": {"legend": False, "tooltip": False, "viz": False},
    "insertNulls": False,
    "lineInterpolation": "smooth",
    "lineWidth": 1,
    "pointSize": 5,
    "scaleDistribution": {"type": "linear"},
    "showPoints": "never",
    "spanNulls": False,
    "stacking": {"group": "A", "mode": "none"},
    "thresholdsStyle": {"mode": "off"},
}
TS_LEGEND = {
    "calcs": ["lastNotNull"],
    "displayMode": "table",
    "placement": "bottom",
    "showLegend": True,
}
TS_TOOLTIP = {"mode": "multi", "sort": "desc"}

_panel_id = 0


def next_id():
    global _panel_id
    _panel_id += 1
    return _panel_id


def row(title, y):
    return {
        "type": "row",
        "title": title,
        "gridPos": {"h": 1, "w": 24, "x": 0, "y": y},
        "id": next_id(),
        "collapsed": False,
        "panels": [],
    }


def stat_panel(title, expr, y, x, w, fc=None):
    return {
        "datasource": DS,
        "fieldConfig": fc or STAT_THRESH,
        "gridPos": {"h": 4, "w": w, "x": x, "y": y},
        "id": next_id(),
        "options": STAT_OPTS,
        "targets": [{"expr": expr, "instant": True, "legendFormat": "", "refId": "A"}],
        "title": title,
        "type": "stat",
    }


def timeseries(title, expr, y, x, w, h, unit, legend="{{container_name}}"):
    return {
        "datasource": DS,
        "fieldConfig": {
            "defaults": {
                "color": {"mode": "palette-classic"},
                "custom": TS_CUSTOM,
                "unit": unit,
            },
            "overrides": [],
        },
        "gridPos": {"h": h, "w": w, "x": x, "y": y},
        "id": next_id(),
        "options": {"legend": TS_LEGEND, "tooltip": TS_TOOLTIP},
        "targets": [{"expr": expr, "legendFormat": legend, "refId": "A"}],
        "title": title,
        "type": "timeseries",
    }


def barchart(title, expr, y, x, w, h):
    return {
        "datasource": DS,
        "fieldConfig": {
            "defaults": {
                "color": {"mode": "thresholds"},
                "decimals": 1,
                "max": 100,
                "min": 0,
                "thresholds": {
                    "mode": "absolute",
                    "steps": [
                        {"color": "green", "value": None},
                        {"color": "yellow", "value": 70},
                        {"color": "red", "value": 90},
                    ],
                },
                "unit": "percent",
                "custom": {
                    "axisBorderShow": False,
                    "axisCenteredZero": False,
                    "axisColorMode": "text",
                    "axisLabel": "",
                    "axisPlacement": "auto",
                    "fillOpacity": 80,
                    "gradientMode": "none",
                    "hideFrom": {"legend": False, "tooltip": False, "viz": False},
                    "lineWidth": 1,
                    "scaleDistribution": {"type": "linear"},
                    "thresholdsStyle": {"mode": "off"},
                },
            },
            "overrides": [],
        },
        "gridPos": {"h": h, "w": w, "x": x, "y": y},
        "id": next_id(),
        "options": {
            "barRadius": 0,
            "barWidth": 0.9,
            "fullHighlight": False,
            "groupWidth": 1,
            "legend": {"calcs": [], "displayMode": "list", "placement": "bottom", "showLegend": False},
            "orientation": "vertical",
            "showValue": "auto",
            "stacking": "none",
            "tooltip": {"mode": "single", "sort": "none"},
            "xField": "Service",
            "xTickLabelRotation": -45,
            "xTickLabelSpacing": 0,
        },
        "targets": [
            {
                "expr": expr,
                "instant": True,
                "legendFormat": "{{com_docker_swarm_service_name}}",
                "refId": "A",
            }
        ],
        "transformations": [
            {"id": "seriesToRows", "options": {}},
            {
                "id": "organize",
                "options": {
                    "indexByName": {"Metric": 0, "Value": 1},
                    "renameByName": {"Metric": "Service", "Value": title},
                },
            },
        ],
        "title": title,
        "type": "barchart",
    }


def main():
    S = sel_swarm_running()
    S_ALL = sel_running('com_docker_swarm_service_name!=""')
    HOST_SEL = sel('engine_host=~"$host"')

    panels = []
    y = 0

    panels.append(row("Overview", y))
    y += 1
    panels.append(stat_panel("Running containers", f"sum(docker_n_containers_running{{{HOST_SEL}}})", y, 0, 4, STAT_GREEN))
    panels.append(stat_panel("Stopped containers", f"sum(docker_n_containers_stopped{{{HOST_SEL}}})", y, 4, 4))
    panels.append(
        stat_panel(
            "Swarm services",
            f"count(count by (com_docker_swarm_service_name) (docker_container_mem_usage{{{S_ALL}}}))",
            y,
            8,
            4,
        )
    )
    panels.append(
        stat_panel(
            "Restarts (1h)",
            f"sum(increase(docker_container_status_restart_count{{{S}}}[1h]))",
            y,
            12,
            4,
            STAT_WARN,
        )
    )
    panels.append(
        stat_panel(
            "Unhealthy",
            f"count(docker_container_health_failing_streak{{{S}}} > 0)",
            y,
            16,
            4,
            STAT_WARN,
        )
    )
    panels.append(
        stat_panel(
            "CPU throttled",
            f"count(100 * rate(docker_container_cpu_throttling_throttled_periods{{{S}}}[5m]) / clamp_min(rate(docker_container_cpu_throttling_periods{{{S}}}[5m]), 0.00001) > 5)",
            y,
            20,
            4,
            STAT_WARN,
        )
    )

    y += 4
    panels.append(row("Running containers", y))
    y += 1
    panels.append(
        {
            "datasource": DS,
            "fieldConfig": {
                "defaults": {
                    "color": {"mode": "thresholds"},
                    "custom": {"align": "auto", "cellOptions": {"type": "auto"}, "inspect": False},
                    "thresholds": {"mode": "absolute", "steps": [{"color": "green", "value": None}]},
                },
                "overrides": [
                    {
                        "matcher": {"id": "byName", "options": "CPU %"},
                        "properties": [
                            {"id": "unit", "value": "percent"},
                            {"id": "decimals", "value": 1},
                            {"id": "custom.cellOptions", "value": {"type": "color-background"}},
                            {
                                "id": "thresholds",
                                "value": {
                                    "mode": "absolute",
                                    "steps": [
                                        {"color": "green", "value": None},
                                        {"color": "yellow", "value": 70},
                                        {"color": "red", "value": 90},
                                    ],
                                },
                            },
                        ],
                    },
                    {
                        "matcher": {"id": "byName", "options": "Mem %"},
                        "properties": [
                            {"id": "unit", "value": "percent"},
                            {"id": "decimals", "value": 1},
                            {"id": "custom.cellOptions", "value": {"type": "color-background"}},
                            {
                                "id": "thresholds",
                                "value": {
                                    "mode": "absolute",
                                    "steps": [
                                        {"color": "green", "value": None},
                                        {"color": "yellow", "value": 70},
                                        {"color": "red", "value": 90},
                                    ],
                                },
                            },
                        ],
                    },
                    {"matcher": {"id": "byName", "options": "Memory"}, "properties": [{"id": "unit", "value": "bytes"}]},
                    {"matcher": {"id": "byName", "options": "Network"}, "properties": [{"id": "unit", "value": "Bps"}]},
                ],
            },
            "gridPos": {"h": 12, "w": 24, "x": 0, "y": y},
            "id": next_id(),
            "options": {
                "cellHeight": "sm",
                "footer": {"countRows": False, "fields": "", "reducer": ["sum"], "show": False},
                "showHeader": True,
                "sortBy": [{"desc": True, "displayName": "CPU %"}],
            },
            "targets": [
                {"expr": f"docker_container_cpu_usage_percent{{{S}}}", "format": "table", "instant": True, "refId": "cpu"},
                {"expr": f"docker_container_mem_usage_percent{{{S}}}", "format": "table", "instant": True, "refId": "mem_pct"},
                {"expr": f"docker_container_mem_usage{{{S}}}", "format": "table", "instant": True, "refId": "mem"},
                {
                    "expr": f"rate(docker_container_net_rx_bytes{{{S}}}[5m]) + rate(docker_container_net_tx_bytes{{{S}}}[5m])",
                    "format": "table",
                    "instant": True,
                    "refId": "net",
                },
                {
                    "expr": f"increase(docker_container_status_restart_count{{{S}}}[24h])",
                    "format": "table",
                    "instant": True,
                    "refId": "restarts",
                },
            ],
            "title": "Container inventory",
            "transformations": [
                {"id": "seriesToColumns", "options": {"byField": "container_name"}},
                {
                    "id": "organize",
                    "options": {
                        "excludeByName": {
                            "Time": True,
                            "Time 1": True,
                            "Time 2": True,
                            "Time 3": True,
                            "Time 4": True,
                            "Time 5": True,
                            "__name__": True,
                            "__name__ 1": True,
                            "container_id": True,
                            "container_id 1": True,
                            "container_image": True,
                            "container_status": True,
                            "engine_host 1": True,
                            "engine_host 2": True,
                            "engine_host 3": True,
                            "engine_host 4": True,
                            "host": True,
                            "instance": True,
                            "job": True,
                            "platform": True,
                            "com_docker_swarm_node_id": True,
                            "com_docker_swarm_service_id": True,
                            "com_docker_swarm_task_id": True,
                        },
                        "indexByName": {
                            "com_docker_swarm_service_name": 0,
                            "container_name": 1,
                            "engine_host": 2,
                            "Value #cpu": 3,
                            "Value #mem_pct": 4,
                            "Value #mem": 5,
                            "Value #net": 6,
                            "Value #restarts": 7,
                        },
                        "renameByName": {
                            "Value #cpu": "CPU %",
                            "Value #mem_pct": "Mem %",
                            "Value #mem": "Memory",
                            "Value #net": "Network",
                            "Value #restarts": "Restarts 24h",
                            "com_docker_swarm_service_name": "Service",
                            "container_name": "Container",
                            "engine_host": "Host",
                        },
                    },
                },
            ],
            "type": "table",
        }
    )

    y += 12
    panels.append(row("Top services", y))
    y += 1
    panels.append(
        barchart(
            "CPU by service",
            f"topk(12, avg by (com_docker_swarm_service_name) (docker_container_cpu_usage_percent{{{S}}}))",
            y,
            0,
            12,
            10,
        )
    )
    panels.append(
        barchart(
            "Memory by service",
            f"topk(12, avg by (com_docker_swarm_service_name) (docker_container_mem_usage_percent{{{S}}}))",
            y,
            12,
            12,
            10,
        )
    )

    y += 10
    panels.append(row("Selection", y))
    y += 1
    panels.append(stat_panel("CPU", f"avg(docker_container_cpu_usage_percent{{{S}}})", y, 0, 6, STAT_PCT))
    panels.append(stat_panel("Memory", f"avg(docker_container_mem_usage_percent{{{S}}})", y, 6, 6, STAT_PCT))
    panels.append(
        stat_panel(
            "Network",
            f"sum(rate(docker_container_net_rx_bytes{{{S}}}[5m]) + rate(docker_container_net_tx_bytes{{{S}}}[5m]))",
            y,
            12,
            6,
            STAT_BPS,
        )
    )
    panels.append(
        stat_panel(
            "Block I/O",
            f"sum(rate(docker_container_blkio_io_service_bytes_recursive_read{{{S}}}[5m]) + rate(docker_container_blkio_io_service_bytes_recursive_write{{{S}}}[5m]))",
            y,
            18,
            6,
            STAT_BPS,
        )
    )

    y += 4
    panels.append(row("Over time", y))
    y += 1
    leg = "{{container_name}}"
    panels.append(timeseries("CPU", f"docker_container_cpu_usage_percent{{{S}}}", y, 0, 12, 10, "percent", leg))
    panels.append(timeseries("Memory", f"docker_container_mem_usage_percent{{{S}}}", y, 12, 12, 10, "percent", leg))
    y += 10
    panels.append(
        timeseries(
            "Network",
            f"rate(docker_container_net_rx_bytes{{{S}}}[5m]) + rate(docker_container_net_tx_bytes{{{S}}}[5m])",
            y,
            0,
            12,
            10,
            "Bps",
            leg,
        )
    )
    panels.append(
        timeseries(
            "Block I/O",
            f"rate(docker_container_blkio_io_service_bytes_recursive_read{{{S}}}[5m]) + rate(docker_container_blkio_io_service_bytes_recursive_write{{{S}}}[5m])",
            y,
            12,
            12,
            10,
            "Bps",
            leg,
        )
    )
    y += 10
    panels.append(
        timeseries(
            "Restarts",
            f"increase(docker_container_status_restart_count{{{S}}}[1h])",
            y,
            0,
            24,
            8,
            "short",
            leg,
        )
    )

    dashboard = {
        "annotations": {
            "list": [
                {
                    "builtIn": 1,
                    "datasource": {"type": "grafana", "uid": "-- Grafana --"},
                    "enable": True,
                    "hide": True,
                    "iconColor": "rgba(0, 211, 255, 1)",
                    "name": "Annotations & Alerts",
                    "type": "dashboard",
                }
            ]
        },
        "editable": True,
        "fiscalYearStartMonth": 0,
        "graphTooltip": 1,
        "links": [],
        "liveNow": False,
        "refresh": "30s",
        "schemaVersion": 39,
        "tags": ["homelab", "docker", "telegraf", "containers"],
        "time": {"from": "now-1h", "to": "now"},
        "timezone": "",
        "title": "Docker",
        "uid": "docker",
        "version": 2,
        "templating": {
            "list": [
                {
                    "name": "platform",
                    "label": "Type",
                    "type": "query",
                    "datasource": DS,
                    "definition": f'label_values(up{{job="{JOB}"}}, platform)',
                    "query": f'label_values(up{{job="{JOB}"}}, platform)',
                    "includeAll": True,
                    "allValue": ".*",
                    "multi": True,
                    "refresh": 1,
                    "sort": 1,
                    "current": {"selected": True, "text": "All", "value": "$__all"},
                },
                {
                    "name": "host",
                    "label": "Host",
                    "type": "query",
                    "datasource": DS,
                    "definition": f'label_values(docker_container_mem_usage{{job="{JOB}", platform=~"$platform", com_docker_swarm_service_name!=""}}, engine_host)',
                    "query": f'label_values(docker_container_mem_usage{{job="{JOB}", platform=~"$platform", com_docker_swarm_service_name!=""}}, engine_host)',
                    "includeAll": True,
                    "allValue": ".*",
                    "multi": True,
                    "refresh": 2,
                    "sort": 1,
                    "current": {"selected": True, "text": "All", "value": "$__all"},
                },
                {
                    "name": "service",
                    "label": "Service",
                    "type": "query",
                    "datasource": DS,
                    "definition": f'label_values(docker_container_mem_usage{{job="{JOB}", platform=~"$platform", engine_host=~"$host", com_docker_swarm_service_name!=""}}, com_docker_swarm_service_name)',
                    "query": f'label_values(docker_container_mem_usage{{job="{JOB}", platform=~"$platform", engine_host=~"$host", com_docker_swarm_service_name!=""}}, com_docker_swarm_service_name)',
                    "includeAll": True,
                    "allValue": ".*",
                    "multi": True,
                    "refresh": 2,
                    "sort": 1,
                    "current": {"selected": True, "text": "All", "value": "$__all"},
                },
                {
                    "name": "container",
                    "label": "Container",
                    "type": "query",
                    "datasource": DS,
                    "definition": f'label_values(docker_container_mem_usage{{job="{JOB}", platform=~"$platform", engine_host=~"$host", com_docker_swarm_service_name=~"$service", container_status="running"}}, container_name)',
                    "query": f'label_values(docker_container_mem_usage{{job="{JOB}", platform=~"$platform", engine_host=~"$host", com_docker_swarm_service_name=~"$service", container_status="running"}}, container_name)',
                    "includeAll": True,
                    "allValue": ".*",
                    "multi": True,
                    "refresh": 2,
                    "sort": 1,
                    "current": {"selected": True, "text": "All", "value": "$__all"},
                },
            ]
        },
        "panels": panels,
    }

    out = Path(__file__).with_name("docker.json")
    out.write_text(json.dumps(dashboard, indent=2) + "\n")
    print(f"wrote {out} ({len(panels)} panels)")


if __name__ == "__main__":
    main()
