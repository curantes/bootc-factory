#!/usr/bin/bash
# Role test: runs as root INSIDE an ephemeral VM, after scripts/vm-checks/base.sh.
# Gives both services a throwaway TLS config and checks they become ready.
set -euo pipefail

command -v openssl >/dev/null || { echo "openssl missing in image"; exit 1; }
tmp=$(mktemp -d)
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -days 1 \
	-subj /CN=localhost -addext subjectAltName=DNS:localhost \
	-keyout "$tmp/tls.key" -out "$tmp/tls.crt" 2>/dev/null

for svc in prometheus alertmanager; do
	install -d -m 0750 -g nobody "/etc/$svc/tls"
	install -m 0640 -g nobody "$tmp/tls.key" "$tmp/tls.crt" "/etc/$svc/tls/"
	install -m 0640 -g nobody "$tmp/tls.crt" "/etc/$svc/tls/ca.crt"
	printf 'tls_server_config:\n  cert_file: /etc/%s/tls/tls.crt\n  key_file: /etc/%s/tls/tls.key\n' \
		"$svc" "$svc" >"/etc/$svc/web.yml"
done

# An ephemeral VM is not a bootc install, so the bound-image store the
# Quadlets pass to podman (additionalimagestore) does not exist, and podman
# refuses to start without it. Create it empty, so podman pulls instead.
# /usr/lib/bootc/storage is a symlink into /sysroot/ostree; `readlink -f`
# fails while several parts of its target are missing, so follow one level.
store=/usr/lib/bootc/storage
if [[ ! -e $store ]]; then
	target=$(readlink "$store" || true)
	[[ -z $target || $target == /* ]] || target="$(dirname "$store")/$target"
	mkdir -p "${target:-$store}"
fi
[[ -d $store ]] || { echo "cannot create the bound-image store $store"; ls -la /usr/lib/bootc; exit 1; }

diagnose() {
	echo "--- bound-image store: $store -> $(readlink -f "$store" 2>&1)"
	for svc in prometheus alertmanager; do
		systemctl status --no-pager --full "$svc.service" || true
		journalctl -b -u "$svc.service" --no-pager | tail -40
	done
}

systemctl daemon-reload
systemctl start prometheus.service alertmanager.service || { diagnose; exit 1; }

ready() {
	local url=$1
	for _ in $(seq 60); do
		curl -fsk --cacert "$tmp/tls.crt" "$url" >/dev/null 2>&1 && return 0
		sleep 5
	done
	return 1
}
ready https://localhost:9090/-/ready || { journalctl -u prometheus --no-pager | tail -50; exit 1; }
ready https://localhost:9093/-/ready || { journalctl -u alertmanager --no-pager | tail -50; exit 1; }
echo "prometheus and alertmanager are ready"

code=$(curl -sk -o /dev/null -w '%{http_code}' -X POST https://localhost:9090/api/v1/admin/tsdb/snapshot)
[[ $code != 200 ]] || { echo "admin API is enabled"; exit 1; }
echo "admin API disabled (HTTP $code)"

firewall-cmd --permanent --query-service=bootc-prometheus
firewall-cmd --permanent --query-service=bootc-alertmanager
