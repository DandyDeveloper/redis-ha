# Grafana Agent

[Grafana Agent](https://grafana.com/docs/agent/latest/) is an alternative to Prometheus specifically crafted for remote writes. Grafana Agent removes the fluff from Prometheus to provide a more compact experience with Prometheus.

## TL;DR

```bash
helm repo add dandydev https://dandydeveloper.github.io/charts
helm install dandydev/grafana-agent
```

By default, this chart will install a DaemonSet across all nodes. Those agents will scrape the metrics from the local node and its resources.

## Introduction

This chart bootstraps a [Grafana Agent](https://grafana.com/docs/agent/latest/).

## Prerequisites

* Kubernetes 1.15+
* PV provisioner support in the underlying infrastructure (if scrapingService.enabled)

## Installing the Chart

To install the chart

```bash
helm repo add dandydev https://dandydeveloper.github.io/charts
helm install dandydev/grafana-agent
```

## Uninstalling the Chart

To uninstall/delete the deployment:

```bash
helm delete <Release Name>
```

The command removes all the Kubernetes components associated with the chart and deletes the release.

## Configuration

The following table lists the configurable parameters of the Grafana Agent chart and their default values.

| Parameter | Description | Type | Default |
|-----|------|---------|-------------|
| `affinity` | Affinity rules | object | `{}` |
| `config.existingConfigMap` | An existing ConfigMap entity that already exists, or is deployed by a parent chart. Populate this to provide an existing config for Grafana Agent. This disables the charts configMap. | string | `""` |
| `config.logLevel` | Server log_level | string | `"info"` |
| `config.loki.configs` | Loki config content | string | see values.yaml |
| `config.loki.enabled` | Enable Loki config | bool | `true` |
| `config.prometheus.configs` | Scrape configs / General configs for the Prometheus scraping | string | see values.yaml |
| `config.prometheus.enabled` | Enable Prometheus config | bool | `true` |
| `config.prometheus.externalLabels` | External labels | object | `{}` |
| `config.prometheus.remoteWrite.auth` | Remote write username/password | string | `nil` |
| `config.prometheus.remoteWrite.url` | URL for the upstream federated Prometheus / Cortex instance | string | `"http://cortex.default.svc.cluster.local"` |
| `config.prometheus.scrapeInterval` | Global scrape interval | string | `"15s"` |
| `config.prometheus.walDir` | Directory mount point for Grafana Agent WAL | string | `"/var/lib/agent/data"` |
| `config.tempo.configs` | Tempo config content | string | see values.yaml |
| `config.tempo.enabled` | Enable Tempo config | bool | `true` |
| `consul` | Configure consul subchart resp. dependency chart Only deployed when scrapingServiceMode.enabled is true | object | see values.yaml |
| `extraVolumeMounts` | Extra Volume mounts | list | `[]` |
| `extraVolumes` | Extra Volumes | list | `[]` |
| `fullnameOverride` | Full name overrie for release | string | `""` |
| `image.pullPolicy` | Image pull policy | string | `"IfNotPresent"` |
| `image.repository` | Grafana Agent image | string | `"grafana/agent"` |
| `image.tag` | Overrides the image tag whose default is the chart appVersion. | string | `""` |
| `imagePullSecrets` | Pull secret for private repository | list | `[]` |
| `nameOverride` | Release name override | string | `""` |
| `nodeSelector` | Pod node selector | object | `{}` |
| `podAnnotations` | Pod annotations | object | `{}` |
| `podSecurityContext` | Pod Security Context | object | `{}` |
| `replicaCount` | Number of replicas of Grafana Agent deployment (only relevant for service scraping mode) | int | `3` |
| `resources` | Kubernetes pod resources | object | `{}` |
| `scrapingServiceMode.enabled` | Enabled scraping service mode. See below for more details | bool | `false` |
| `securityContext` | Container Security Context | object | see values.yaml |
| `service.port` | Kubernetes service port | int | `80` |
| `service.type` | Service Type | string | `"ClusterIP"` |
| `serviceAccount.annotations` | Annotations to add to the service account | object | `{}` |
| `serviceAccount.create` | Specifies whether a service account should be created | bool | `true` |
| `serviceAccount.name` | The name of the service account to use. If not set and create is true, a name is generated using the fullname template | string | `""` |
| `tolerations` | Pod tolerations | list | `[{"effect":"NoSchedule","operator":"Exists"}]` |
| `updateStrategy` | Update strategy | string | `"Recreate"` |

Specify each parameter using the `--set key=value[,key=value]` argument to `helm install`. For example,

```bash
$ helm repo add dandydev https://dandydeveloper.github.io/charts
$ helm install \
  --set tag=1.7.0 \
    dandydev/grafana-agent
```

The above command deploys a DaemonSet of the Grafana Agent in the `default` namespace.

# Scraping Service Mode
[Scraping Service mode](https://grafana.com/docs/agent/latest/scraping-service/)

----------------------------------------------
Autogenerated from chart metadata using [helm-docs](https://github.com/norwoodj/helm-docs)
