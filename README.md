# chc-mirror

Helm chart that hourly mirrors CHC data-hub subfolders into `gs://sheerwater-public/chc-mirror` via wget.

## What it does

A CronJob mounts `gs://sheerwater-public` via GKE GCS FUSE CSI, installs GNU `wget` on Alpine, then mirrors each configured subfolder in order:

```text
wget -r -l inf --no-parent -N --reject "index.html*" \
  [-A <accept>] \
  https://data.chc.ucsb.edu/<path> \
  -P /mnt/sheerwater-public/chc-mirror/ \
  -e robots=off -nH
```

`-N` only re-fetches when the remote timestamp is newer. Optional `accept` maps to wget `-A` (comma-separated extensions/patterns). `-nH` keeps the URL path under the `-P` directory, so objects land at `gs://sheerwater-public/chc-mirror/<path>/` without repeating the path in `-P`.

## Prerequisites

- GKE cluster with the [Cloud Storage FUSE CSI driver](https://cloud.google.com/kubernetes-engine/docs/how-to/persistent-volumes/cloud-storage-fuse-csi-driver) enabled
- A GCP service account with write access to `gs://sheerwater-public` (e.g. `roles/storage.objectUser` on the bucket)
- Workload Identity binding from that GSA to the chart’s Kubernetes ServiceAccount

## Install

```bash
helm upgrade --install chc-mirror ./chart \
  --namespace chc-mirror --create-namespace \
  --set-json 'subfolders=[{"path":"products/CHIRPS-2.0","accept":"tif,nc"}]' \
  --set serviceAccount.annotations."iam\.gke\.io/gcp-service-account"=chc-mirror@PROJECT.iam.gserviceaccount.com
```

Or with a values file:

```yaml
subfolders:
  - path: products/CHIRPS-2.0
    accept: "tif,nc"
  - path: products/CHIRPS-2.0/docs
serviceAccount:
  annotations:
    iam.gke.io/gcp-service-account: chc-mirror@PROJECT.iam.gserviceaccount.com
```

## Values

| Key | Default | Description |
| --- | --- | --- |
| `schedule` | `"0 * * * *"` | Cron schedule (hourly) |
| `subfolders` | `[]` | Required list of `{path, accept?}` entries under the CHC base URL |
| `subfolders[].path` | — | Path under `wget.baseUrl` to mirror |
| `subfolders[].accept` | omitted | Optional wget `-A` filter (e.g. `tif,nc`) |
| `wget.baseUrl` | `https://data.chc.ucsb.edu` | CHC HTTP base URL |
| `wget.extraArgs` | recursive/no-parent/`-N` flags | Extra wget flags before the URL |
| `gcs.bucket` | `sheerwater-public` | Destination GCS bucket |
| `gcs.mountPath` | `/mnt/sheerwater-public` | Local mount path |
| `gcs.mirrorPrefix` | `chc-mirror` | Prefix under the bucket (`-P` target) |
| `serviceAccount.annotations` | `{}` | Set `iam.gke.io/gcp-service-account` for WI |
| `concurrencyPolicy` | `Forbid` | Skip overlapping runs |
| `activeDeadlineSeconds` | `3300` | Kill a run before the next hourly tick |

## Manual trigger

```bash
kubectl create job --from=cronjob/chc-mirror chc-mirror-manual -n chc-mirror
```
