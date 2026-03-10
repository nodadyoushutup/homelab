# Kasten Kubernetes backups plan

This plan tracks enabling Veeam Kasten backups in the homelab cluster using official Helm charts managed by Argo CD.

## Stage 0 - scope lock

- [x] Confirm official Helm charts are available for both Kasten and snapshot prerequisites.
  Mark complete when: chart sources resolve to `https://charts.kasten.io` (`k10`) and `https://piraeus.io/helm-charts` (`snapshot-controller`).
- [x] Confirm current cluster gap for snapshot APIs.
  Mark complete when: `VolumeSnapshot*` CRDs are absent and democratic-csi snapshotter logs show missing snapshot API resources.

## Stage 1 - GitOps manifests

- [x] Add Argo CD `Application` for snapshot controller.
  Mark complete when: `kubernetes/argocd-management/snapshot-controller-app.yaml` exists with automated sync and multi-source Helm values wiring.
- [x] Add snapshot-controller values and namespace manifests.
  Mark complete when: `kubernetes/snapshot-controller/values.yaml` defines controller version and `VolumeSnapshotClass` resources, and namespace manifest exists.
- [x] Add Argo CD `Application` for Kasten using official chart.
  Mark complete when: `kubernetes/argocd-management/kasten-app.yaml` exists and references chart `k10` with values from `kubernetes/kasten/values.yaml`.
- [x] Add baseline Kasten chart values.
  Mark complete when: `kubernetes/kasten/values.yaml` accepts EULA and sets persistent storage classes.

## Stage 2 - live rollout

- [x] Apply new Argo CD app manifests immediately with `kubectl apply`.
  Mark complete when: both `application/snapshot-controller` and `application/kasten` exist in namespace `argocd`.
- [x] Verify snapshot API/controller readiness.
  Mark complete when: `volumesnapshotclasses.snapshot.storage.k8s.io` CRD exists and snapshot-controller deployment is Ready.
- [x] Verify Kasten installation readiness.
  Mark complete when: Kasten pods are Ready in `kasten-io` and Argo app reports `Synced/Healthy`.

## Stage 3 - backup configuration

- [x] Configure S3-compatible location profile credentials in `kasten-io`.
  Mark complete when: `secret/kasten-s3-secret` exists in namespace `kasten-io` with valid S3 credentials.
- [x] Create a Kasten `Profile` and backup `Policy`.
  Mark complete when: `profiles.config.kio.kasten.io` and `policies.config.kio.kasten.io` objects are accepted by the API.
- [x] Validate profile connectivity and policy viability.
  Mark complete when: profile status is successful and Kasten can resolve the export target without credential errors.

## Stage 4 - final validation

- [x] Verify Argo CD health guardrails after rollout.
  Mark complete when: `argocd-server`, `argocd-repo-server`, `argocd-application-controller` are Ready and core applications remain healthy.

## Stage 5 - ingress and edge routing

- [x] Add Kubernetes ingress for `kasten.nodadyoushutup.com` on ingress-nginx.
  Mark complete when: host resolves through ingress and `curl -H 'Host: kasten.nodadyoushutup.com' http://192.168.1.241/kasten/` returns `200`.
- [x] Add root URL redirect for Kasten.
  Mark complete when: `curl -H 'Host: kasten.nodadyoushutup.com' http://192.168.1.241/` returns a redirect to `/kasten/`.
- [x] Ensure Cloudflare DNS and Nginx Proxy Manager forwarding exist for Kasten host.
  Mark complete when: `kasten.nodadyoushutup.com` reaches Kasten through NPM and `/` redirects to `/kasten/`.

## Notes

- Kasten chart deployment uses `apiservices.deployed: false` to avoid `FailedDiscoveryCheck` on this cluster while keeping core backup APIs (`config.kio.kasten.io`) healthy.
- Kasten persistence is configured on `truenas-nfs-csi-retain` to avoid iSCSI provisioning lock contention encountered during initial rollout.
- Kasten edge routing is served via NPM with a dedicated Let’s Encrypt cert for `kasten.nodadyoushutup.com` (issued `2026-03-10`, expires `2026-06-08`).
