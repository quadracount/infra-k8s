#!/usr/bin/env sh
# Construye las imágenes, las carga en el cluster local y aplica los manifiestos.
# Se ejecuta desde infra-k8s, con todos los repos clonados en la misma carpeta:
#   ./scripts/deploy-local.sh
#
# Funciona con kind, minikube y el Kubernetes de Docker Desktop (según el contexto
# actual de kubectl). Las imágenes se llaman quadracount/<repo>:dev.
set -eu

IMAGES="activity-service balances-service bff-gateway frontend-quadracount groups-service mcp-server"

echo "== Construyendo imágenes (docker compose build)"
docker compose build

CONTEXT=$(kubectl config current-context)
echo "== Cargando imágenes en el cluster ($CONTEXT)"
for name in $IMAGES; do
  image="quadracount/$name:dev"
  case "$CONTEXT" in
    kind-*) kind load docker-image "$image" --name "${CONTEXT#kind-}" ;;
    minikube) minikube image load "$image" ;;
    docker-desktop) : ;; # comparte las imágenes de Docker, no hace falta cargarlas
    *) echo "Contexto $CONTEXT desconocido: carga $image a mano" ;;
  esac
done

echo "== Secret"
./scripts/create-secret.sh

# Deployments que ya existían antes de este despliegue
EXISTING=$(kubectl get deployments -n quadracount -o name 2>/dev/null || true)

echo "== Aplicando manifiestos"
kubectl apply -f k8s/

# Las imágenes nuevas tienen el mismo tag (:dev), así que Kubernetes no las detecta solo:
# se reinician los Deployments que ya existían para que usen la versión recién construida.
if [ -n "$EXISTING" ]; then
  # shellcheck disable=SC2086
  kubectl rollout restart $EXISTING -n quadracount >/dev/null
fi

echo "== Listo. Estado de los pods:"
kubectl get pods -n quadracount
