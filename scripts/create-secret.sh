#!/usr/bin/env sh
# Crea el Secret quadracount-secrets en el cluster. Los valores NUNCA se commitean.
#
# Contraseñas aleatorias en hexadecimal (seguras dentro de las URLs mongodb:// y amqp://).
# Se puede fijar cualquier valor con una variable de entorno, por ejemplo:
#   ANTHROPIC_API_KEY=sk-... ./scripts/create-secret.sh
#
# No reemplaza un Secret existente: MongoDB crea su usuario administrador solo la
# primera vez que arranca, así que cambiar la contraseña después lo dejaría sin acceso.
# Para empezar de cero: kubectl delete namespace quadracount (borra también los datos).
set -eu

NS=quadracount
SECRET=quadracount-secrets

rand() { od -An -N16 -tx1 /dev/urandom | tr -d ' \n'; }

kubectl apply -f "$(dirname "$0")/../k8s/00-namespace.yaml" >/dev/null

if kubectl get secret "$SECRET" -n "$NS" >/dev/null 2>&1; then
  echo "El Secret $SECRET ya existe en $NS; no se modifica."
  exit 0
fi

set -- \
  --from-literal=MONGO_USER="${MONGO_USER:-quadra}" \
  --from-literal=MONGO_PASSWORD="${MONGO_PASSWORD:-$(rand)}" \
  --from-literal=RABBITMQ_USER="${RABBITMQ_USER:-quadra}" \
  --from-literal=RABBITMQ_PASSWORD="${RABBITMQ_PASSWORD:-$(rand)}" \
  --from-literal=JWT_SECRET="${JWT_SECRET:-$(rand)}" \
  --from-literal=INTERNAL_API_KEY="${INTERNAL_API_KEY:-$(rand)}"

if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
  set -- "$@" --from-literal=ANTHROPIC_API_KEY="$ANTHROPIC_API_KEY"
fi

kubectl create secret generic "$SECRET" -n "$NS" "$@"
echo "Secret $SECRET creado en $NS."
echo "Ver la contraseña de RabbitMQ (para la interfaz web):"
echo "  kubectl get secret $SECRET -n $NS -o jsonpath='{.data.RABBITMQ_PASSWORD}' | base64 -d"
