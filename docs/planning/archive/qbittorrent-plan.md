# qBittorrent Kubernetes rollout plan

This plan tracks deploying qBittorrent to Kubernetes with reusable Kustomize base templates and separate overlays for two instances (`movies`, `torrents`), including iSCSI-backed storage, Argo CD management, and public routing through Cloudflare + Nginx Proxy Manager. Public URL naming uses `qbittorrent.movies.nodadyoushutup.com` and `qbittorrent.television.nodadyoushutup.com`.

## Stage 0 - scope lock

- [x] Confirm deployment model: Kustomize base at `kubernetes/qbittorrent/base` with overlays per instance under `kubernetes/qbittorrent/overlays/*`.
  Mark complete when: both overlays render successfully with `kubectl kustomize`.
- [x] Confirm storage model: each instance uses iSCSI-backed PVCs for config + downloads.
  Mark complete when: overlay manifests contain PVCs using `storageClassName: truenas-iscsi-csi-retain`.

## Stage 1 - app manifests

- [x] Add reusable qBittorrent base manifests (deployment/service/pvc/ingress).
  Mark complete when: base resources are referenced by both overlays.
- [x] Add `movies` and `torrents` overlays with unique namespaces, ingress hosts, and download volume sizing.
  Mark complete when: each overlay renders with distinct namespace + hostname values.

## Stage 2 - Argo CD integration

- [x] Add a scoped Argo CD `AppProject` for qBittorrent instances.
  Mark complete when: project exists in `kubernetes/argocd-management` with both destinations.
- [x] Add Argo CD `Application` manifests for both overlays with automated sync (`prune` + `selfHeal`).
  Mark complete when: both app manifests target their overlay paths.

## Stage 3 - edge routing

- [x] Ensure Cloudflare DNS points `qbittorrent.movies.nodadyoushutup.com` and `qbittorrent.television.nodadyoushutup.com` at the public homelab edge IP.
  Mark complete when: public resolvers return `96.253.53.3` for both records.
- [x] Ensure Nginx Proxy Manager proxy hosts for both domains forward to Kubernetes ingress (`192.168.1.241:80`) with TLS certs.
  Mark complete when: NPM config has certificate + proxy host entries for both qBittorrent domains.

## Stage 4 - validation

- [x] Verify Kubernetes rollout and storage binding.
  Mark complete when: both qBittorrent pods are Ready and all PVCs are `Bound`.
- [x] Verify Argo CD app status from Git source.
  Mark complete when: both qBittorrent applications show `sync=Synced` and `health=Healthy` after commit/push.
- [x] Verify public HTTPS reachability.
  Mark complete when: both qBittorrent URLs respond successfully with valid TLS.
