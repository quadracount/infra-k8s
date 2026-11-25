# infra-k8s

Infraestructura de QuadraCount:

- `docker-compose.yml`: desarrollo local rápido.
- `k8s/`: manifiestos de Kubernetes (namespace `quadracount`). El pipeline los valida con `kubeconform`.
- `scripts/`: crear el Secret y desplegar en un cluster local.

Las imágenes se llaman `quadracount/<repo>:dev` en los dos casos: `docker compose build` construye las mismas que usa Kubernetes.

## Desarrollo local con Docker Compose

Todos los repos tienen que estar clonados en la misma carpeta, porque el compose construye las imágenes desde `../<repo>`:

```
quadracount/
├── activity-service/
├── bff-gateway/
├── infra-k8s/        <- desde aquí se ejecuta
└── ...
```

```bash
docker compose up -d --build --wait
docker compose ps
docker compose logs -f activity-service
docker compose down          # agregar -v para borrar también los datos de MongoDB
```

Están MongoDB, RabbitMQ, groups-service, balances-service, activity-service, bff-gateway y el frontend (http://localhost:8080). Falta mcp-server (Fase 5).

groups-service arranca con los datos de ejemplo de la sección 1 del plan: 6 usuarios (`martin@quadracount.dev`, `camila@…`, `sofia@…`, `diego@…`, `valentina@…`, `tomas@…`, todos con la contraseña `quadra123`), los 3 grupos de Martín, sus gastos y el pago de Diego. Saldos esperados en el depto: Martín +12.000, Camila +1.000, Sofía −5.000, Diego −8.000.

Si tu base de datos tiene datos de una versión anterior, empieza de cero para no mezclarlos: `docker compose down -v` (o `kubectl delete namespace quadracount` en Kubernetes).

| Qué | Dónde |
|---|---|
| GraphQL del BFF | http://localhost:3000/graphql |
| Interfaz de RabbitMQ | http://localhost:15672 (usuario `quadra`, contraseña `quadra`) |
| MongoDB | `mongodb://localhost:27017` |

Los puertos se publican solo en `127.0.0.1`, así que nadie más en tu red (por ejemplo, el wifi de la universidad) puede conectarse. Es importante porque MongoDB no tiene contraseña en desarrollo y el BFF todavía no tiene login. Las contraseñas de MongoDB llegan en la Fase 3, con un `Secret` de Kubernetes.

Las credenciales del compose son solo para desarrollo. Se pueden cambiar con un archivo `.env` en esta carpeta (no se commitea), con las variables `RABBITMQ_USER`, `RABBITMQ_PASSWORD`, `JWT_SECRET` e `INTERNAL_API_KEY`.

Para probar la conexión entre el BFF y activity-service, ver "Probar la conexión con activity-service" en el README de bff-gateway.

## Probar el flujo completo

En http://localhost:3000/graphql (GraphiQL), crear un gasto:

```graphql
mutation {
  createExpense(input: {
    groupId: "g-depto", description: "Gas", amount: 18000, paidBy: "u-sofia", source: MANUAL,
    shares: [
      { userId: "u-martin", amount: 4500 }, { userId: "u-camila", amount: 4500 },
      { userId: "u-sofia", amount: 4500 }, { userId: "u-diego", amount: 4500 }
    ]
  }) { id description }
}
```

Y ver que se refleja en los tres servicios con una sola consulta:

```graphql
{
  group(id: "g-depto") {
    name
    expenses { description amount paidBy { name } }  # groups-service
    balances { member { name } net }                 # balances-service
    settlementPlan { from { name } to { name } amount }
    activity(limit: 5) { text }                      # activity-service
  }
}
```

Prueba de resiliencia: `docker compose stop balances-service`, crear otro gasto (se guarda y aparece en el feed; el mensaje espera en la cola `balances.events` de la interfaz de RabbitMQ), y `docker compose start balances-service`: los saldos se ponen al día solos.

Para empezar de cero: `docker compose down -v && docker compose up -d --build --wait`.

## Kubernetes (cluster local)

Se probó con **kind** sobre Docker Desktop (Windows 11). También sirve minikube o el Kubernetes de Docker Desktop: `scripts/deploy-local.sh` detecta el contexto de `kubectl`. En Windows, los scripts se ejecutan con Git Bash.

### Primera vez

```bash
# Instalar kind: https://kind.sigs.k8s.io/docs/user/quick-start/#installation
kind create cluster --name quadracount

# Desde infra-k8s: construye las imágenes, las carga en kind, crea el Secret y aplica k8s/
./scripts/deploy-local.sh
kubectl get pods -n quadracount     # esperar a que todos estén Running y 1/1
```

Es normal que activity-service y groups-service se reinicien una vez al principio: arrancan antes de que MongoDB y RabbitMQ estén listos, y Kubernetes los vuelve a levantar solo.

Para actualizar después de cambiar código, se vuelve a ejecutar `./scripts/deploy-local.sh`: reconstruye las imágenes y reinicia los Deployments.

### Acceso desde el navegador

```bash
kubectl port-forward svc/bff-gateway 3000:3000 -n quadracount    # GraphQL: http://localhost:3000/graphql
kubectl port-forward svc/frontend-app 8080:80 -n quadracount      # http://localhost:8080
kubectl port-forward svc/rabbitmq 15672:15672 -n quadracount      # interfaz de RabbitMQ
```

Cada `port-forward` queda conectado a un pod: si ese pod se reemplaza (por ejemplo, con un nuevo despliegue), se corta y hay que volver a ejecutarlo. Detener antes el compose (`docker compose stop`), porque usa los mismos puertos.

### Secretos

El Secret `quadracount-secrets` **no está en el repo**. Lo crea `scripts/create-secret.sh` con contraseñas aleatorias (MongoDB, RabbitMQ, `JWT_SECRET`, `INTERNAL_API_KEY` y, si se define la variable, `ANTHROPIC_API_KEY`). Cada uno tiene sus propias contraseñas en su cluster.

- En Kubernetes, MongoDB **sí tiene contraseña** (a diferencia del compose). Los servicios arman su `MONGO_URL` con el usuario y la contraseña del Secret.
- Usuario de RabbitMQ: `quadra`. Contraseña: `kubectl get secret quadracount-secrets -n quadracount -o jsonpath='{.data.RABBITMQ_PASSWORD}' | base64 -d`
- El script no reemplaza un Secret existente, porque MongoDB crea su usuario solo la primera vez. Para empezar de cero: `kubectl delete namespace quadracount` (borra también los datos).

### Qué hay en `k8s/`

| Archivo | Contenido |
|---|---|
| `00-namespace.yaml` | Namespace `quadracount` |
| `10-configmap.yaml` | URLs entre servicios, `SEED_DEMO`, `CORS_ORIGINS`, `LLM_MODE` |
| `20-mongodb.yaml` | StatefulSet con PVC de 1 Gi y Service headless |
| `21-rabbitmq.yaml` | StatefulSet con PVC (los mensajes pendientes sobreviven a un reinicio) |
| `30-groups-service.yaml`, `31-balances-service.yaml` | Deployment + Service, con probes gRPC nativos (`grpc.health.v1`) |
| `32-activity-service.yaml` | Deployment sin Service (no expone puertos, solo usa RabbitMQ) |
| `40-bff-gateway.yaml` | Deployment + Service (puerto 3000) |
| `41-mcp-server.yaml` | Con `replicas: 0` hasta la Fase 5 |
| `50-frontend-app.yaml` | Deployment + Service (nginx, puerto 80) |

Los archivos llevan un número porque `kubectl apply -f k8s/` los aplica en orden alfabético.

**1 réplica por servicio:** las conexiones gRPC son persistentes, así que un Service `ClusterIP` no reparte las peticiones entre réplicas (todas irían a la misma). Balancear por petición requeriría un balanceador de capa 7 o un service mesh, fuera del alcance del proyecto.

### Prueba de resiliencia (guion de la demo)

```bash
kubectl scale deployment balances-service --replicas=0 -n quadracount
# crear un gasto en GraphiQL: se guarda y aparece en el feed, pero los saldos no cambian
# en la interfaz de RabbitMQ, la cola balances.events tiene 1 mensaje esperando
kubectl scale deployment balances-service --replicas=1 -n quadracount
# a los pocos segundos los saldos se ponen al día solos
```
