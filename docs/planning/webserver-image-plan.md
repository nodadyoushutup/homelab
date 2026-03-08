# Webserver Image (Swarm) plan

This plan tracks adding a new Docker Swarm app named `webserver-image` using an `nginx` container under `terraform/swarm/webserver-image/app`.

## Stage 0 - scope and deployment contract

- [x] Taxonomy locked: app-only Swarm service (`terraform/swarm/webserver-image/app`) with one state.
  Mark complete when: stage boundary and tfstate key are explicit.
- [x] Runtime target locked:
  - service name: `webserver-image`
  - node placement: `node.labels.role==swarm-cp-0`
  - architecture: `linux/aarch64`
  Mark complete when: service placement and platform constraints are present in Terraform.
- [x] Storage + config contract locked:
  - persistent Docker volume for image files
  - `nginx` configuration delivered via Terraform `docker_config`
  - directory listing/read with `GET`, upload/write with `POST` and `PUT`, removal with `DELETE`
  Mark complete when: `nginx` config enforces WebDAV and is mounted into the service.

## Stage 1 - stack scaffold

- [x] Create stack files:
  - `terraform/swarm/webserver-image/app/provider.tf`
  - `terraform/swarm/webserver-image/app/variables.tf`
  - `terraform/swarm/webserver-image/app/main.tf`
  - `terraform/swarm/webserver-image/app/nginx.conf.tftpl`
  - `terraform/swarm/webserver-image/app/pipeline/app.sh`
  Mark complete when: Terraform and shell syntax checks pass.
- [x] Implement service runtime:
  - overlay network
  - persistent volume (`webserver-image-data`)
  - pinned `nginx` image with arm64 platform support
  - published ingress port default `18088` -> container `8080`
  - healthcheck for local HTTP readiness
  Mark complete when: service spec validates and references the mounted volume/config.
- [x] Implement HTTP method behavior:
  - `GET` and directory browsing via `autoindex`
  - `DELETE` via `dav_methods`
  - `POST` remapped internally to `PUT` for object upload paths
  Mark complete when: config contains method handling and access controls.

## Stage 2 - operational parity

- [x] Add purge integration:
  - `scripts/docker/purge/webserver-image.sh`
  - aliases/listing entries in `scripts/docker/purge/purge.sh`
  Mark complete when: `scripts/docker/purge/purge.sh webserver-image` resolves the new service.

## Stage 3 - ingress and hostname routing

- [x] Add Nginx Proxy Manager certificate + proxy host entries in `/mnt/eapp/.tfvars/nginx-proxy-manager/config.tfvars`.
  Mark complete when: `webserver.image.nodadyoushutup.com` forwards to `192.168.1.26:18088` with TLS.
- [x] Run NPM pipelines and verify final endpoint behavior over hostname.
  Mark complete when: `terraform/swarm/nginx_proxy_manager/app/pipeline/app.sh` and `terraform/swarm/nginx_proxy_manager/config/pipeline/config.sh` succeed and HTTPS `GET/POST/DELETE` work.

## Validation notes

- Date: 2026-03-08
- Commands run:
  - `terraform fmt -recursive terraform/swarm/webserver-image/app`
  - `terraform -chdir=terraform/swarm/webserver-image/app init -backend=false -input=false`
  - `terraform -chdir=terraform/swarm/webserver-image/app validate`
  - `bash -n terraform/swarm/webserver-image/app/pipeline/app.sh scripts/docker/purge/webserver-image.sh scripts/docker/purge/purge.sh`
  - `terraform/swarm/webserver-image/app/pipeline/app.sh`
  - `terraform/swarm/nginx_proxy_manager/app/pipeline/app.sh`
  - `terraform/swarm/nginx_proxy_manager/config/pipeline/config.sh`
  - `docker -H ssh://swarm-cp-0.local service ls --format 'table {{.Name}}\t{{.Replicas}}\t{{.Ports}}' | rg 'webserver-image|NAME'`
  - `docker -H ssh://swarm-cp-0.local service ps webserver-image --no-trunc --format 'table {{.Name}}\t{{.Node}}\t{{.DesiredState}}\t{{.CurrentState}}\t{{.Error}}'`
  - `curl -I http://webserver.image.nodadyoushutup.com/`
  - `curl -X POST https://webserver.image.nodadyoushutup.com/packer/npm-path-check-<timestamp>.img --data-binary 'npm-proxy-check-payload'`
  - `curl https://webserver.image.nodadyoushutup.com/packer/npm-path-check-<timestamp>.img`
  - `curl -X DELETE https://webserver.image.nodadyoushutup.com/packer/npm-path-check-<timestamp>.img`
  - `curl -X POST http://192.168.1.26:18088/packer/healthcheck-<timestamp>.img --data-binary 'pipeline-check-payload'`
  - `curl http://192.168.1.26:18088/packer/healthcheck-<timestamp>.img`
  - `curl -X DELETE http://192.168.1.26:18088/packer/healthcheck-<timestamp>.img`
  - `docker run ... nginx -t -c /tmp/nginx.conf` (rendered template syntax check)
  - `docker run ...` + `curl` integration test of `POST` -> `GET` -> `DELETE` against `/packer/debian-12.img`
- Runtime check results:
  - `docker service` health settled at `webserver-image 1/1` on `swarm-cp-0`
  - `docker service` health settled at `nginx-proxy-manager 1/1` on `swarm-cp-0`
  - `http://webserver.image.nodadyoushutup.com/` -> `301` redirect to HTTPS
  - `GET https://webserver.image.nodadyoushutup.com/` -> `200`
  - `POST https://webserver.image.nodadyoushutup.com/packer/npm-path-check-<timestamp>.img` -> `201`
  - `GET https://webserver.image.nodadyoushutup.com/packer/npm-path-check-<timestamp>.img` -> `200` (body returned)
  - `DELETE https://webserver.image.nodadyoushutup.com/packer/npm-path-check-<timestamp>.img` -> `204`
  - `GET /` -> `200`
  - `POST /packer/debian-12.img` -> `201`
  - `GET /packer/debian-12.img` -> `200` (body returned)
  - `DELETE /packer/debian-12.img` -> `204`
  - `POST /packer/healthcheck-<timestamp>.img` -> `201`
  - `GET /packer/healthcheck-<timestamp>.img` -> `200` (body returned)
  - `DELETE /packer/healthcheck-<timestamp>.img` -> `204`

## Tfvars schema (sanitized)

```hcl
provider_config = {
  docker = {
    host = "ssh://<user>@<swarm-manager-ip>"
    ssh_opts = [
      "-o", "StrictHostKeyChecking=no",
      "-o", "UserKnownHostsFile=/dev/null",
      "-i", "~/.ssh/id_ed25519"
    ]
  }
}
```

## Usage notes

- Upload with `POST`/`PUT` by targeting a full object path (for example `/packer-images/debian-12.qcow2`).
- `POST` request bodies are mapped directly to WebDAV `PUT`; multipart form uploads are not transformed.
