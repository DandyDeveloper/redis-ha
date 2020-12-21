{{/* vim: set filetype=mustache: */}}

{{- define "config-redis.conf" }}
{{- if .Values.redis.customConfig }}
{{ tpl .Values.redis.customConfig . | indent 4 }}
{{- else }}
    dir "/data"
    port {{ .Values.redis.port }}
    {{- if .Values.sentinel.tlsPort }}
    tls-port {{ .Values.redis.tlsPort }}
    tls-cert-file /tls-certs/{{ .Values.tls.certFile }}
    tls-key-file /tls-certs/{{ .Values.tls.keyFile }}
    {{- if .Values.tls.dhParamsFile }}
    tls-dh-params-file /tls-certs/{{ .Values.tls.dhParamsFile }}
    {{- end }}
    {{- if .Values.tls.caCertFile }}
    tls-ca-cert-file /tls-certs/{{ .Values.tls.caCertFile }}
    {{- end }}
    {{- if eq (default "yes" .Values.redis.authClients) "no"}}
    tls-auth-clients no
    {{- end }}
    tls-replication {{ if .Values.redis.tlsReplication }}yes{{ else }}no{{ end }}
    {{- end }}
    {{- range $key, $value := .Values.redis.config }}
    {{ $key }} {{ $value }}
    {{- end }}
{{- if .Values.auth }}
    requirepass replace-default-auth
    masterauth replace-default-auth
{{- end }}
{{- end }}
{{- end }}

{{- define "config-sentinel.conf" }}
{{- if .Values.sentinel.customConfig }}
{{ tpl .Values.sentinel.customConfig . | indent 4 }}
{{- else }}
    dir "/data"
    port {{ .Values.sentinel.port }}
    {{- if .Values.sentinel.tlsPort }}
    tls-port {{ .Values.sentinel.tlsPort }}
    tls-cert-file /tls-certs/{{ .Values.tls.certFile }}
    tls-key-file /tls-certs/{{ .Values.tls.keyFile }}
    {{- if .Values.tls.dhParamsFile }}
    tls-dh-params-file /tls-certs/{{ .Values.tls.dhParamsFile }}
    {{- end }}
    {{- if .Values.tls.caCertFile }}
    tls-ca-cert-file /tls-certs/{{ .Values.tls.caCertFile }}
    {{- end }}
    {{- if eq (default "yes" .Values.sentinel.authClients) "no"}}
    tls-auth-clients no
    {{- end }}
    tls-replication {{ if .Values.sentinel.tlsReplication }}yes{{ else }}no{{ end }}
    {{- end }}
    {{- range $key, $value := .Values.sentinel.config }}
    {{- if eq "maxclients" $key  }}
        {{ $key }} {{ $value }}
    {{- else }}
        sentinel {{ $key }} {{ template "redis-ha.masterGroupName" $ }} {{ $value }}
    {{- end }}
    {{- end }}
{{- if .Values.auth }}
    sentinel auth-pass {{ template "redis-ha.masterGroupName" . }} replace-default-auth
{{- if .Values.sentinel.auth }}
    requirepass replace-default-sentinel-auth
{{- end }}
{{- end }}
{{- end }}
{{- end }}

{{- define "config-init.sh" }}
    echo "$(date) Start..."
    HOSTNAME="$(hostname)"
    {{- if .Values.ro_replicas }}
    RO_REPLICAS="{{ .Values.ro_replicas }}"
    {{- end }}
    INDEX="${HOSTNAME##*-}"
    SENTINEL_PORT={{ .Values.sentinel.port }}
    MASTER=''
    MASTER_GROUP="{{ template "redis-ha.masterGroupName" . }}"
    QUORUM="{{ .Values.sentinel.quorum }}"
    REDIS_CONF=/data/conf/redis.conf
    REDIS_PORT={{ .Values.redis.port }}
    REDIS_TLS_PORT={{ .Values.redis.tlsPort }}
    SENTINEL_CONF=/data/conf/sentinel.conf
    SENTINEL_TLS_PORT={{ .Values.sentinel.tlsPort }}
    SERVICE={{ template "redis-ha.fullname" . }}
    SENTINEL_TLS_REPLICATION_ENABLED={{ default false .Values.sentinel.tlsReplication }}
    REDIS_TLS_REPLICATION_ENABLED={{ default false .Values.redis.tlsReplication }}
    set -eu

    sentinel_get_master() {
    set +e
        if [ "$SENTINEL_PORT" -eq 0 ]; then
            redis-cli -h "${SERVICE}" -p "${SENTINEL_TLS_PORT}" {{ if .Values.sentinel.auth }} -a "${SENTINELAUTH}"{{ end }} {{ if ne (default "yes" .Values.sentinel.authClients) "no"}} --tls --cacert /tls-certs/{{ .Values.tls.caCertFile }} --cert /tls-certs/{{ .Values.tls.certFile }} --key /tls-certs/{{ .Values.tls.keyFile }}{{ end }} sentinel get-master-addr-by-name "${MASTER_GROUP}" |\
            grep -E '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}'
        else
            redis-cli -h "${SERVICE}" -p "${SENTINEL_PORT}" {{ if .Values.sentinel.auth }} -a "${SENTINELAUTH}"{{ end }} sentinel get-master-addr-by-name "${MASTER_GROUP}" |\
            grep -E '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}'
        fi
    set -e
    }

    sentinel_get_master_retry() {
        master=''
        retry=${1}
        sleep=3
        for i in $(seq 1 "${retry}"); do
            master=$(sentinel_get_master)
            if [ -n "${master}" ]; then
                break
            fi
            sleep $((sleep + i))
        done
        echo "${master}"
    }

    identify_master() {
        echo "Identifying redis master (get-master-addr-by-name).."
        echo "  using sentinel ({{ template "redis-ha.fullname" . }}), sentinel group name ({{ template "redis-ha.masterGroupName" . }})"
        echo "  $(date).."
        MASTER="$(sentinel_get_master_retry 3)"
        if [ -n "${MASTER}" ]; then
            echo "  $(date) Found redis master (${MASTER})"
        else
            echo "  $(date) Did not find redis master (${MASTER})"
        fi
    }

    sentinel_update() {
        echo "Updating sentinel config.."
        echo "  evaluating sentinel id (\${SENTINEL_ID_${INDEX}})"
        eval MY_SENTINEL_ID="\$SENTINEL_ID_${INDEX}"
        echo "  sentinel id (${MY_SENTINEL_ID}), sentinel grp (${MASTER_GROUP}), quorum (${QUORUM})"
        sed -i "1s/^/sentinel myid ${MY_SENTINEL_ID}\\n/" "${SENTINEL_CONF}"
        if [ "$SENTINEL_TLS_REPLICATION_ENABLED" = true ]; then
            echo "  redis master (${1}:${REDIS_TLS_PORT})"
            sed -i "2s/^/sentinel monitor ${MASTER_GROUP} ${1} ${REDIS_TLS_PORT} ${QUORUM} \\n/" "${SENTINEL_CONF}"
        else
            echo "  redis master (${1}:${REDIS_PORT})"
            sed -i "2s/^/sentinel monitor ${MASTER_GROUP} ${1} ${REDIS_PORT} ${QUORUM} \\n/" "${SENTINEL_CONF}"
        fi
        echo "sentinel announce-ip ${ANNOUNCE_IP}" >> ${SENTINEL_CONF}
        if [ "$SENTINEL_PORT" -eq 0 ]; then
            echo "  announce (${ANNOUNCE_IP}:${SENTINEL_TLS_PORT})"
            echo "sentinel announce-port ${SENTINEL_TLS_PORT}" >> ${SENTINEL_CONF}
        else
            echo "  announce (${ANNOUNCE_IP}:${SENTINEL_PORT})"
            echo "sentinel announce-port ${SENTINEL_PORT}" >> ${SENTINEL_CONF}
        fi
    }

    redis_update() {
        echo "Updating redis config.."
        if [ "$REDIS_TLS_REPLICATION_ENABLED" = true ]; then
            echo "  we are slave of redis master (${1}:${REDIS_TLS_PORT})"
            echo "slaveof ${1} ${REDIS_TLS_PORT}" >> "${REDIS_CONF}"
            echo "slave-announce-port ${REDIS_TLS_PORT}" >> ${REDIS_CONF}
        else
            echo "  we are slave of redis master (${1}:${REDIS_PORT})"
            echo "slaveof ${1} ${REDIS_PORT}" >> "${REDIS_CONF}"
            echo "slave-announce-port ${REDIS_PORT}" >> ${REDIS_CONF}
        fi
        echo "slave-announce-ip ${ANNOUNCE_IP}" >> ${REDIS_CONF}
    }

    copy_config() {
        echo "Copying default redis config.."
        echo "  to '${REDIS_CONF}'"
        cp /readonly-config/redis.conf "${REDIS_CONF}"
        echo "Copying default sentinel config.."
        echo "  to '${SENTINEL_CONF}'"
        cp /readonly-config/sentinel.conf "${SENTINEL_CONF}"
    }

    setup_defaults() {
        echo "Setting up defaults.."
        echo "  using statefulset index (${INDEX})"
        if [ "${INDEX}" = "0" ]; then
            echo "Setting this pod as master for redis and sentinel.."
            echo "  using announce (${ANNOUNCE_IP})"
            redis_update "${ANNOUNCE_IP}"
            sentinel_update "${ANNOUNCE_IP}"
            echo "  make sure ${ANNOUNCE_IP} is not a slave (slaveof no one)"
            sed -i "s/^.*slaveof.*//" "${REDIS_CONF}"
        else
            echo "Getting redis master ip.."
            echo "  blindly assuming (${SERVICE}-announce-0) or (${SERVICE}-server-0) are master"
            DEFAULT_MASTER="$(getent_hosts 0 | awk '{ print $1 }')"
            echo "  identified redis (may be redis master) ip (${DEFAULT_MASTER})"
            if [ -z "${DEFAULT_MASTER}" ]; then
                echo "Error: Unable to resolve redis master (getent hosts)."
                exit 1
            fi
            echo "Setting default slave config for redis and sentinel.."
            echo "  using master ip (${DEFAULT_MASTER})"
            redis_update "${DEFAULT_MASTER}"
            sentinel_update "${DEFAULT_MASTER}"
        fi
    }

    redis_ping() {
    set +e
        if [ "$REDIS_PORT" -eq 0 ]; then
            redis-cli -h "${MASTER}"{{ if .Values.auth }} -a "${AUTH}"{{ end }} -p "${REDIS_TLS_PORT}" {{ if ne (default "yes" .Values.sentinel.authClients) "no"}} --tls --cacert /tls-certs/{{ .Values.tls.caCertFile }} --cert /tls-certs/{{ .Values.tls.certFile }} --key /tls-certs/{{ .Values.tls.keyFile }}{{ end }} ping
        else
            redis-cli -h "${MASTER}"{{ if .Values.auth }} -a "${AUTH}"{{ end }} -p "${REDIS_PORT}" ping
        fi
    set -e
    }

    redis_ping_retry() {
        ping=''
        retry=${1}
        sleep=3
        for i in $(seq 1 "${retry}"); do
            if [ "$(redis_ping)" = "PONG" ]; then
               ping='PONG'
               break
            fi
            sleep $((sleep + i))
            MASTER=$(sentinel_get_master)
        done
        echo "${ping}"
    }

    find_master() {
        echo "Verifying redis master.."
        if [ "$REDIS_PORT" -eq 0 ]; then
            echo "  ping (${MASTER}:${REDIS_TLS_PORT})"
        else
            echo "  ping (${MASTER}:${REDIS_PORT})"
        fi
        echo "  $(date).."
        if [ "$(redis_ping_retry 3)" != "PONG" ]; then
            echo "  $(date) Can't ping redis master (${MASTER})"
            echo "Attempting to force failover (sentinel failover).."
            
            if [ "$SENTINEL_PORT" -eq 0 ]; then
                echo "  on sentinel (${SERVICE}:${SENTINEL_TLS_PORT}), sentinel grp (${MASTER_GROUP})"
                echo "  $(date).."
                if redis-cli -h "${SERVICE}" -p "${SENTINEL_TLS_PORT}" {{ if .Values.sentinel.auth }} -a "${SENTINELAUTH}"{{ end }} {{ if ne (default "yes" .Values.sentinel.authClients) "no"}} --tls --cacert /tls-certs/{{ .Values.tls.caCertFile }} --cert /tls-certs/{{ .Values.tls.certFile }} --key /tls-certs/{{ .Values.tls.keyFile }}{{ end }} sentinel failover "${MASTER_GROUP}" | grep -q 'NOGOODSLAVE' ; then
                    echo "  $(date) Failover returned with 'NOGOODSLAVE'"
                    echo "Setting defaults for this pod.."
                    setup_defaults
                    return 0
                fi
            else
                echo "  on sentinel (${SERVICE}:${SENTINEL_PORT}), sentinel grp (${MASTER_GROUP})"
                echo "  $(date).."
                if redis-cli -h "${SERVICE}" -p "${SENTINEL_PORT}" {{ if .Values.sentinel.auth }} -a "${SENTINELAUTH}"{{ end }} sentinel failover "${MASTER_GROUP}" | grep -q 'NOGOODSLAVE' ; then
                    echo "  $(date) Failover returned with 'NOGOODSLAVE'"
                    echo "Setting defaults for this pod.."
                    setup_defaults
                    return 0
                fi
            fi    
                       
            echo "Hold on for 10sec"
            sleep 10
            echo "We should get redis master's ip now. Asking (get-master-addr-by-name).."
            if [ "$SENTINEL_PORT" -eq 0 ]; then
                echo "  sentinel (${SERVICE}:${SENTINEL_TLS_PORT}), sentinel grp (${MASTER_GROUP})"
            else
                echo "  sentinel (${SERVICE}:${SENTINEL_PORT}), sentinel grp (${MASTER_GROUP})"
            fi
            echo "  $(date).."
            MASTER="$(sentinel_get_master)"
            if [ "${MASTER}" ]; then
                echo "  $(date) Found redis master (${MASTER})"
                echo "Updating redis and sentinel config.."
                sentinel_update "${MASTER}"
                redis_update "${MASTER}"
            else
                echo "$(date) Error: Could not failover, exiting..."
                exit 1
            fi
        else
            echo "  $(date) Found reachable redis master (${MASTER})"
            echo "Updating redis and sentinel config.."
            sentinel_update "${MASTER}"
            redis_update "${MASTER}"
        fi
    }

    redis_ro_update() {
        echo "Updating read-only redis config.."
        echo "  redis.conf set 'replica-priority 0'"
        echo "replica-priority 0" >> ${REDIS_CONF}
    }

    getent_hosts() {
        index=${1:-${INDEX}}
        service="${SERVICE}-announce-${index}"
        pod="${SERVICE}-server-${index}"
        host=$(getent hosts "${service}")
        if [ -z "${host}" ]; then
            host=$(getent hosts "${pod}")
        fi
        echo "${host}"
    }

    mkdir -p /data/conf/

    echo "Initializing config.."
    copy_config

    # where is redis master
    identify_master

    echo "Identify announce ip for this pod.."
    echo "  using (${SERVICE}-announce-${INDEX}) or (${SERVICE}-server-${INDEX})"
    ANNOUNCE_IP=$(getent_hosts | awk '{ print $1 }')
    echo "  identified announce (${ANNOUNCE_IP})"
    if [ -z "${ANNOUNCE_IP}" ]; then
        "Error: Could not resolve the announce ip for this pod."
        exit 1
    elif [ "${MASTER}" ]; then
        find_master
    else
        setup_defaults
    fi

    {{- if .Values.ro_replicas }}
    # works only if index is less than 10
    echo "Verifying redis read-only replica.."
    echo "  we have RO_REPLICAS='${RO_REPLICAS}' with INDEX='${INDEX}'"
    if echo "${RO_REPLICAS}" | grep -q "${INDEX}" ; then
        redis_ro_update
    fi
    {{- end }}

    if [ "${AUTH:-}" ]; then
        echo "Setting redis auth values.."
        ESCAPED_AUTH=$(echo "${AUTH}" | sed -e 's/[\/&]/\\&/g');
        sed -i "s/replace-default-auth/${ESCAPED_AUTH}/" "${REDIS_CONF}" "${SENTINEL_CONF}"
    fi
    
    if [ "${SENTINELAUTH:-}" ]; then
        echo "Setting sentinel auth values"
        ESCAPED_AUTH_SENTINEL=$(echo "$SENTINELAUTH" | sed -e 's/[\/&]/\\&/g');
        sed -i "s/replace-default-sentinel-auth/${ESCAPED_AUTH_SENTINEL}/" "$SENTINEL_CONF"
    fi

    echo "$(date) Ready..."
{{- end }}

{{- define "config-haproxy.cfg" }}
{{- if .Values.haproxy.customConfig }}
{{ tpl .Values.haproxy.customConfig . | indent 4 }}
{{- else }}
    defaults REDIS
      mode tcp
      timeout connect {{ .Values.haproxy.timeout.connect }}
      timeout server {{ .Values.haproxy.timeout.server }}
      timeout client {{ .Values.haproxy.timeout.client }}
      timeout check {{ .Values.haproxy.timeout.check }}

    listen health_check_http_url
      bind :8888
      mode http
      monitor-uri /healthz
      option      dontlognull

    {{- $root := . }}
    {{- $fullName := include "redis-ha.fullname" . }}
    {{- $replicas := int (toString .Values.replicas) }}
    {{- $masterGroupName := include "redis-ha.masterGroupName" . }}
    {{- range $i := until $replicas }}
    # Check Sentinel and whether they are nominated master
    backend check_if_redis_is_master_{{ $i }}
      mode tcp
      option tcp-check
      tcp-check connect
      {{- if $root.auth }}
      tcp-check send AUTH\ {{ $root.redisPassword }}\r\n
      tcp-check expect string +OK
      {{- end }}
      tcp-check send PING\r\n
      tcp-check expect string +PONG
      tcp-check send SENTINEL\ get-master-addr-by-name\ {{ $masterGroupName }}\r\n
      tcp-check expect string REPLACE_ANNOUNCE{{ $i }}
      tcp-check send QUIT\r\n
      tcp-check expect string +OK
      {{- range $i := until $replicas }}
      server R{{ $i }} {{ $fullName }}-announce-{{ $i }}:26379 check inter 1s
      {{- end }}
    {{- end }}

    # decide redis backend to use
    #master
    frontend ft_redis_master
      bind *:{{ $root.Values.redis.port }}
      use_backend bk_redis_master
    {{- if .Values.haproxy.readOnly.enabled }}
    #slave
    frontend ft_redis_slave
      bind *:{{ .Values.haproxy.readOnly.port }}
      use_backend bk_redis_slave
    {{- end }}
    # Check all redis servers to see if they think they are master
    backend bk_redis_master
      {{- if .Values.haproxy.stickyBalancing }}
      balance source
      hash-type consistent
      {{- end }}
      mode tcp
      option tcp-check
      tcp-check connect
      {{- if .Values.auth }}
      tcp-check send AUTH\ REPLACE_AUTH_SECRET\r\n
      tcp-check expect string +OK
      {{- end }}
      tcp-check send PING\r\n
      tcp-check expect string +PONG
      tcp-check send info\ replication\r\n
      tcp-check expect string role:master
      tcp-check send QUIT\r\n
      tcp-check expect string +OK
      {{- range $i := until $replicas }}
      use-server R{{ $i }} if { srv_is_up(R{{ $i }}) } { nbsrv(check_if_redis_is_master_{{ $i }}) ge 2 }
      server R{{ $i }} {{ $fullName }}-announce-{{ $i }}:{{ $root.Values.redis.port }} check inter 1s fall 1 rise 1
      {{- end }}
    {{- if .Values.haproxy.readOnly.enabled }}
    backend bk_redis_slave
      {{- if .Values.haproxy.stickyBalancing }}
      balance source
      hash-type consistent
      {{- end }}
      mode tcp
      option tcp-check
      tcp-check connect
      {{- if .Values.auth }}
      tcp-check send AUTH\ REPLACE_AUTH_SECRET\r\n
      tcp-check expect string +OK
      {{- end }}
      tcp-check send PING\r\n
      tcp-check expect string +PONG
      tcp-check send info\ replication\r\n
      tcp-check expect  string role:slave
      tcp-check send QUIT\r\n
      tcp-check expect string +OK
      {{- range $i := until $replicas }}
      server R{{ $i }} {{ $fullName }}-announce-{{ $i }}:{{ $root.Values.redis.port }} check inter 1s fall 1 rise 1
      {{- end }}
    {{- end }}
    {{- if .Values.haproxy.metrics.enabled }}
    frontend metrics
      mode http
      bind *:{{ .Values.haproxy.metrics.port }}
      option http-use-htx
      http-request use-service prometheus-exporter if { path {{ .Values.haproxy.metrics.scrapePath }} }
    {{- end }}
{{- if .Values.haproxy.extraConfig }}
    # Additional configuration
{{ .Values.haproxy.extraConfig | indent 4 }}
{{- end }}
{{- end }}
{{- end }}


{{- define "config-haproxy_init.sh" }}
    HAPROXY_CONF=/data/haproxy.cfg
    cp /readonly/haproxy.cfg "$HAPROXY_CONF"
    {{- $fullName := include "redis-ha.fullname" . }}
    {{- $replicas := int (toString .Values.replicas) }}
    {{- range $i := until $replicas }}
    for loop in $(seq 1 10); do
      getent hosts {{ $fullName }}-announce-{{ $i }} && break
      echo "Waiting for service {{ $fullName }}-announce-{{ $i }} to be ready ($loop) ..." && sleep 1
    done
    ANNOUNCE_IP{{ $i }}=$(getent hosts "{{ $fullName }}-announce-{{ $i }}" | awk '{ print $1 }')
    if [ -z "$ANNOUNCE_IP{{ $i }}" ]; then
      echo "Could not resolve the announce ip for {{ $fullName }}-announce-{{ $i }}"
      exit 1
    fi
    sed -i "s/REPLACE_ANNOUNCE{{ $i }}/$ANNOUNCE_IP{{ $i }}/" "$HAPROXY_CONF"

    if [ "${AUTH:-}" ]; then
        echo "Setting auth values"
        ESCAPED_AUTH=$(echo "$AUTH" | sed -e 's/[\/&]/\\&/g');
        sed -i "s/REPLACE_AUTH_SECRET/${ESCAPED_AUTH}/" "$HAPROXY_CONF"
    fi
    {{- end }}
{{- end }}

{{- define "redis_liveness.sh" }}
    {{- if not (ne (int .Values.sentinel.port) 0) }}
    TLS_CLIENT_OPTION="--tls --cacert /tls-certs/{{ .Values.tls.caCertFile }} --cert /tls-certs/{{ .Values.tls.certFile }} --key /tls-certs/{{ .Values.tls.keyFile }}"
    {{- end }}
    response=$(
      redis-cli \
      {{- if .Values.auth }}
        -a "${AUTH}" --no-auth-warning \
      {{- end }}
        -h localhost \
      {{- if ne (int .Values.redis.port) 0 }}
        -p {{ .Values.redis.port }} \
      {{- else }}
        -p {{ .Values.redis.tlsPort }} ${TLS_CLIENT_OPTION} \
      {{- end}}
        ping
    )
    if [ "$response" != "PONG" ]; then
      echo "$response"
      exit 1
    fi
    echo "response=$response"
{{- end }}

{{- define "sentinel_liveness.sh" }}
    {{- if not (ne (int .Values.sentinel.port) 0) }}
    TLS_CLIENT_OPTION="--tls --cacert /tls-certs/{{ .Values.tls.caCertFile }} --cert /tls-certs/{{ .Values.tls.certFile }} --key /tls-certs/{{ .Values.tls.keyFile }}"
    {{- end }}
    response=$(
      redis-cli \
      {{- if .Values.auth }}
        -a "${SENTINELAUTH}" --no-auth-warning \
      {{- end }}
        -h localhost \
      {{- if ne (int .Values.sentinel.port) 0 }}
        -p {{ .Values.sentinel.port }} \
      {{- else }}
        -p {{ .Values.sentinel.tlsPort }} ${TLS_CLIENT_OPTION} \
      {{- end}}
        ping
    )
    if [ "$response" != "PONG" ]; then
      echo "$response"
      exit 1
    fi
    echo "response=$response"
{{- end }}

